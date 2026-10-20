//
//  MPVPlayerController.m
//  Omnia
//

#import "MPVPlayerController.h"

#if TARGET_OS_OSX
#import <mpv/client.h>
#import <mpv/render_gl.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <QuartzCore/QuartzCore.h>
#import <os/lock.h>
#import <math.h>
#import <stdatomic.h>

/// mpv calls back on its own threads. Blocks dispatched to main hold this box
/// rather than the player or view, so a block that runs after the player is
/// gone finds a nil target instead of a freed object. The flag coalesces
/// bursts of callbacks into a single main-queue hop.
@interface OMMpvCallbackBox : NSObject {
@public
    atomic_bool _pending;
}
@property (nonatomic, weak, nullable) id target;
- (instancetype)initWithTarget:(id)target;
@end

@implementation OMMpvCallbackBox
- (instancetype)initWithTarget:(id)target {
    self = [super init];
    if (!self) return nil;
    _target = target;
    atomic_init(&_pending, false);
    return self;
}
@end

static dispatch_queue_t OMMpvTeardownQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("Omnia.mpv.teardown", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static void *OMOpenGLProcedureAddress(void *context, const char *name) {
    CFStringRef symbolName = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingASCII);
    void *address = CFBundleGetFunctionPointerForName(
        CFBundleGetBundleWithIdentifier(CFSTR("com.apple.opengl")),
        symbolName
    );
    CFRelease(symbolName);
    return address;
}

#ifndef GL_FRAMEBUFFER_BINDING
#define GL_FRAMEBUFFER_BINDING 0x8CA6
#endif

/// Draws mpv frames on a private serial queue instead of the main thread.
/// An NSOpenGLView only presents from the main thread, so every frame used to
/// compete with SwiftUI layout, hover tracking and the playback chrome; a busy
/// main thread showed up as dropped frames and sluggish controls. A
/// CAOpenGLLayer can be displayed from any thread.
@interface OMMpvVideoLayer : CAOpenGLLayer
@property (nonatomic, readonly) CGLContextObj cglContext;
@property (atomic, readonly) BOOL didRenderFrame;
- (void)attachRenderContext:(mpv_render_context *)renderContext;
/// Frees the render context with the GL context current, never while a frame
/// is being drawn.
- (void)freeRenderContext;
- (void)scheduleRender;
@end

@implementation OMMpvVideoLayer {
    CGLPixelFormatObj _pixelFormat;
    CGLContextObj _context;
    mpv_render_context *_renderContext;
    os_unfair_lock _renderLock;
    dispatch_queue_t _renderQueue;
    atomic_bool _renderPending;
    atomic_bool _didRenderFrame;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    _renderLock = OS_UNFAIR_LOCK_INIT;
    atomic_init(&_renderPending, false);
    atomic_init(&_didRenderFrame, false);
    _renderQueue = dispatch_queue_create(
        "Omnia.mpv.render",
        dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0)
    );

    CGLPixelFormatAttribute attributes[] = {
        kCGLPFAAccelerated,
        kCGLPFADoubleBuffer,
        kCGLPFAAllowOfflineRenderers,
        (CGLPixelFormatAttribute)0,
    };
    GLint formatCount = 0;
    if (CGLChoosePixelFormat(attributes, &_pixelFormat, &formatCount) != kCGLNoError || !_pixelFormat) {
        CGLPixelFormatAttribute fallbackAttributes[] = {
            kCGLPFADoubleBuffer,
            kCGLPFAAllowOfflineRenderers,
            (CGLPixelFormatAttribute)0,
        };
        CGLChoosePixelFormat(fallbackAttributes, &_pixelFormat, &formatCount);
    }
    if (_pixelFormat) {
        CGLCreateContext(_pixelFormat, NULL, &_context);
    }
    if (_context) {
        GLint swapInterval = 1;
        CGLSetParameter(_context, kCGLCPSwapInterval, &swapInterval);
    }

    self.asynchronous = NO;
    self.opaque = YES;
    self.needsDisplayOnBoundsChange = YES;
    CGColorRef black = CGColorCreateGenericRGB(0, 0, 0, 1);
    self.backgroundColor = black;
    CGColorRelease(black);
    return self;
}

- (void)dealloc {
    if (_context) CGLReleaseContext(_context);
    if (_pixelFormat) CGLReleasePixelFormat(_pixelFormat);
}

- (CGLContextObj)cglContext {
    return _context;
}

- (BOOL)didRenderFrame {
    return atomic_load(&_didRenderFrame);
}

- (CGLPixelFormatObj)copyCGLPixelFormatForDisplayMask:(uint32_t)mask {
    return _pixelFormat ? CGLRetainPixelFormat(_pixelFormat) : [super copyCGLPixelFormatForDisplayMask:mask];
}

- (CGLContextObj)copyCGLContextForPixelFormat:(CGLPixelFormatObj)pixelFormat {
    return _context ? CGLRetainContext(_context) : [super copyCGLContextForPixelFormat:pixelFormat];
}

- (BOOL)canDrawInCGLContext:(CGLContextObj)context
                pixelFormat:(CGLPixelFormatObj)pixelFormat
               forLayerTime:(CFTimeInterval)layerTime
                displayTime:(const CVTimeStamp *)displayTime {
    return YES;
}

- (void)drawInCGLContext:(CGLContextObj)context
             pixelFormat:(CGLPixelFormatObj)pixelFormat
            forLayerTime:(CFTimeInterval)layerTime
             displayTime:(const CVTimeStamp *)displayTime {
    CGLSetCurrentContext(context);
    os_unfair_lock_lock(&_renderLock);
    mpv_render_context *renderContext = _renderContext;
    if (renderContext) {
        GLint framebuffer = 0;
        glGetIntegerv(GL_FRAMEBUFFER_BINDING, &framebuffer);
        GLint viewport[4] = { 0, 0, 0, 0 };
        glGetIntegerv(GL_VIEWPORT, viewport);

        mpv_render_context_update(renderContext);
        mpv_opengl_fbo target = {
            .fbo = framebuffer,
            .w = MAX(viewport[2], 1),
            .h = MAX(viewport[3], 1),
            .internal_format = 0,
        };
        int flipY = 1;
        // Never let mpv sleep on this queue waiting for a frame's
        // presentation time; frame pacing comes from the update callback.
        int blockForTargetTime = 0;
        mpv_render_param parameters[] = {
            { MPV_RENDER_PARAM_OPENGL_FBO, &target },
            { MPV_RENDER_PARAM_FLIP_Y, &flipY },
            { MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, &blockForTargetTime },
            { MPV_RENDER_PARAM_INVALID, NULL },
        };
        if (mpv_render_context_render(renderContext, parameters) >= 0) {
            atomic_store(&_didRenderFrame, true);
        }
    } else {
        glClearColor(0, 0, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);
    }
    [super drawInCGLContext:context pixelFormat:pixelFormat forLayerTime:layerTime displayTime:displayTime];
    if (renderContext) {
        mpv_render_context_report_swap(renderContext);
    }
    os_unfair_lock_unlock(&_renderLock);
}

- (void)attachRenderContext:(mpv_render_context *)renderContext {
    os_unfair_lock_lock(&_renderLock);
    _renderContext = renderContext;
    os_unfair_lock_unlock(&_renderLock);
}

- (void)freeRenderContext {
    if (!_context) return;
    // Core Animation holds the CGL lock while it draws, so taking it here
    // (before the render lock, the same order as a draw) waits out any frame
    // in progress on the render queue.
    CGLLockContext(_context);
    os_unfair_lock_lock(&_renderLock);
    if (_renderContext) {
        CGLContextObj previous = CGLGetCurrentContext();
        CGLSetCurrentContext(_context);
        mpv_render_context_free(_renderContext);
        _renderContext = NULL;
        CGLSetCurrentContext(previous);
    }
    os_unfair_lock_unlock(&_renderLock);
    CGLUnlockContext(_context);
}

- (void)scheduleRender {
    if (atomic_exchange(&_renderPending, true)) return;
    dispatch_async(_renderQueue, ^{
        atomic_store(&self->_renderPending, false);
        [self display];
        // A display outside the main thread opens an implicit transaction
        // that nothing else would commit.
        [CATransaction flush];
    });
}

@end

@interface OMMpvVideoView : NSView
@property (nonatomic, readonly) OMMpvVideoLayer *videoLayer;
@end

@implementation OMMpvVideoView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;

    _videoLayer = [OMMpvVideoLayer layer];
    // Layer-hosting: assign the layer before turning on wantsLayer so AppKit
    // uses ours instead of creating a backing layer.
    self.layer = _videoLayer;
    self.wantsLayer = YES;
    self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    return self;
}

- (NSView *)hitTest:(NSPoint)point {
    // Video is a display-only surface. Let SwiftUI's playback chrome and its
    // gestures receive mouse events even when AppKit reorders native views
    // during an exclusive full-screen transition.
    return nil;
}

- (BOOL)isOpaque {
    return YES;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self updateContentsScale];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [self updateContentsScale];
}

- (void)updateContentsScale {
    CGFloat scale = self.window.backingScaleFactor;
    if (scale > 0 && _videoLayer.contentsScale != scale) {
        _videoLayer.contentsScale = scale;
        [_videoLayer scheduleRender];
    }
}

@end

@implementation OMMpvTrack

- (instancetype)initWithTrackID:(NSInteger)trackID
                          title:(NSString *)title
                       language:(NSString *)language
                          codec:(NSString *)codec
                       selected:(BOOL)selected {
    self = [super init];
    if (!self) return nil;
    _trackID = trackID;
    _title = [title copy];
    _language = [language copy];
    _codec = [codec copy];
    _selected = selected;
    return self;
}

@end

@interface OMMpvPlaybackSnapshot ()
@property (nonatomic, readwrite, copy) NSArray<OMMpvTrack *> *audioTracks;
@property (nonatomic, readwrite, copy) NSArray<OMMpvTrack *> *subtitleTracks;
@property (nonatomic, readwrite) BOOL tracksLoading;
@property (nonatomic, readwrite, copy, nullable) NSString *errorMessage;
- (instancetype)initWithAudioTracks:(NSArray<OMMpvTrack *> *)audioTracks
                      subtitleTracks:(NSArray<OMMpvTrack *> *)subtitleTracks
                       tracksLoading:(BOOL)tracksLoading
                         errorMessage:(nullable NSString *)errorMessage;
@end

@implementation OMMpvPlaybackSnapshot

- (instancetype)initWithAudioTracks:(NSArray<OMMpvTrack *> *)audioTracks
                      subtitleTracks:(NSArray<OMMpvTrack *> *)subtitleTracks
                       tracksLoading:(BOOL)tracksLoading
                         errorMessage:(NSString *)errorMessage {
    self = [super init];
    if (!self) return nil;
    _audioTracks = [audioTracks copy];
    _subtitleTracks = [subtitleTracks copy];
    _tracksLoading = tracksLoading;
    _errorMessage = [errorMessage copy];
    return self;
}

@end

typedef NS_ENUM(NSInteger, OMMpvTrackSelectionKind) {
    OMMpvTrackSelectionKindAudio,
    OMMpvTrackSelectionKindSubtitle,
};

@interface OMMpvPendingTrackSelection : NSObject
@property (nonatomic) OMMpvTrackSelectionKind kind;
@property (nonatomic, copy, nullable) OMMpvTrackSelectionCompletion completion;
@end

@implementation OMMpvPendingTrackSelection
@end

static void OMMpvRequestRedraw(void *context) {
    // Runs on an mpv thread. The layer coalesces requests and draws on its
    // own queue, so new frames never wait for the main thread.
    OMMpvCallbackBox *box = (__bridge OMMpvCallbackBox *)context;
    OMMpvVideoLayer *layer = box.target;
    [layer scheduleRender];
}

@interface OMMpvPlayerController () <NSWindowDelegate> {
    mpv_handle *_mpv;
    mpv_render_context *_renderContext;
    NSURL *_URL;
    NSDictionary<NSString *, NSString *> *_requestHeaders;
    NSURL *_blurayDeviceURL;
    BOOL _didStart;
    BOOL _stopped;
    BOOL _paused;
    double _volume;
    double _playbackRate;
    OMMpvVideoAspectMode _videoAspectMode;
    double _pendingPosition;
    NSArray<NSString *> *_preferredAudioLanguages;
    NSArray<NSString *> *_preferredSubtitleLanguages;
    BOOL _subtitlesDisabled;
    NSDictionary<NSString *, NSString *> *_playerOptions;
    NSDictionary<NSString *, id> *_subtitleStyle;
    BOOL _tracksLoading;
    BOOL _fileLoaded;
    NSView *_inlineVideoHost;
    NSPanel *_pictureInPicturePanel;
    BOOL _pictureInPictureActive;
    uint64_t _nextTrackSelectionRequestID;
    uint64_t _latestAudioTrackSelectionRequestID;
    uint64_t _latestSubtitleTrackSelectionRequestID;
    NSMutableDictionary<NSNumber *, OMMpvPendingTrackSelection *> *_pendingTrackSelections;
    OMMpvCallbackBox *_wakeupBox;
    OMMpvCallbackBox *_redrawBox;
}
@property (nonatomic, readwrite) OMMpvVideoView *videoView;
@property (nonatomic, readwrite, nullable) NSString *errorMessage;
- (void)drainEvents;
- (void)emitSnapshot;
- (void)embedVideoViewInHost:(NSView *)hostView;
- (NSPanel *)makePictureInPicturePanel;
- (void)applySubtitleStyleProperties;
- (void)applyPendingSeekIfReady;
- (uint64_t)nextTrackSelectionRequestID;
- (void)abortTrackSelectionRequest:(uint64_t)requestID;
- (void)finishTrackSelectionRequest:(uint64_t)requestID status:(int)status;
- (void)finishTrackSelectionForEvent:(mpv_event *)event;
@end

static void OMMpvWakeup(void *context) {
    OMMpvCallbackBox *box = (__bridge OMMpvCallbackBox *)context;
    if (atomic_exchange(&box->_pending, true)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        // Clear before draining so events that arrive mid-drain schedule
        // another pass instead of being dropped.
        atomic_store(&box->_pending, false);
        OMMpvPlayerController *controller = box.target;
        [controller drainEvents];
    });
}

@implementation OMMpvPlayerController

- (instancetype)initWithURL:(NSURL *)URL
              requestHeaders:(NSDictionary<NSString *, NSString *> *)requestHeaders {
    return [self initWithURL:URL requestHeaders:requestHeaders blurayDeviceURL:nil];
}

- (instancetype)initWithURL:(NSURL *)URL
              requestHeaders:(NSDictionary<NSString *, NSString *> *)requestHeaders
              blurayDeviceURL:(NSURL *)blurayDeviceURL {
    self = [super init];
    if (!self) return nil;

    _URL = URL;
    _requestHeaders = [requestHeaders copy];
    _blurayDeviceURL = [blurayDeviceURL copy];
    _volume = 100;
    _playbackRate = 1;
    _videoAspectMode = OMMpvVideoAspectModeOriginal;
    _tracksLoading = YES;
    _nextTrackSelectionRequestID = 100;
    _pendingTrackSelections = [NSMutableDictionary dictionary];
    _videoView = [[OMMpvVideoView alloc] initWithFrame:NSZeroRect];
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void)startIfNeeded {
    if (_didStart || _stopped || self.errorMessage) return;

    // Wait for a real window so the video layer has its backing scale before
    // the first frame. SwiftUI calls again after mounting if the first update
    // races with window attachment.
    if (!_videoView.window) return;

    _didStart = YES;
    _mpv = mpv_create();
    if (!_mpv) {
        [self failWithMessage:@"libmpv could not create a player core."];
        return;
    }

    // Omnia owns the playback UI. Keep libmpv's behavior deterministic and
    // use mpv's supported render API instead of macOS `wid` embedding.
    mpv_set_option_string(_mpv, "config", "no");
    mpv_set_option_string(_mpv, "terminal", "no");
    mpv_set_option_string(_mpv, "input-default-bindings", "no");
    mpv_set_option_string(_mpv, "input-vo-keyboard", "no");
    // Omnia supplies the complete playback interaction surface.  Disabling
    // mpv's bundled Lua scripts also avoids spinning up its optional JIT
    // script runtime inside a hardened macOS app.
    mpv_set_option_string(_mpv, "load-scripts", "no");
    mpv_set_option_string(_mpv, "load-console", "no");
    mpv_set_option_string(_mpv, "load-stats-overlay", "no");
    mpv_set_option_string(_mpv, "load-auto-profiles", "no");
    mpv_set_option_string(_mpv, "ytdl", "no");
    mpv_set_option_string(_mpv, "keep-open", "yes");
    mpv_set_option_string(_mpv, "osd-level", "0");
    mpv_set_option_string(_mpv, "vo", "libmpv");
    mpv_set_option_string(_mpv, "hwdec", "auto-safe");
    // display-resample needs a swap reported on every display refresh. Frames
    // are now drawn when mpv has one ready, not on each vsync, so let mpv time
    // video to the audio clock instead.
    mpv_set_option_string(_mpv, "video-sync", "audio");
    // Add-on links usually point at debrid CDNs or AIOStreams/MediaFlow
    // proxies. Some refuse mpv's own "libmpv" user agent, and their
    // connections drop mid-stream, so present a browser agent (an add-on's
    // own User-Agent header still wins), reconnect instead of failing, and
    // keep a read-ahead cache like Stremio's player.
    mpv_set_option_string(
        _mpv,
        "user-agent",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    );
    mpv_set_option_string(_mpv, "network-timeout", "30");
    mpv_set_option_string(
        _mpv,
        "stream-lavf-o",
        "reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=5"
    );
    mpv_set_option_string(_mpv, "cache", "yes");
    mpv_set_option_string(_mpv, "demuxer-max-bytes", "150MiB");
    mpv_set_option_string(_mpv, "demuxer-max-back-bytes", "50MiB");
    mpv_set_option_string(_mpv, "demuxer-readahead-secs", "20");
    mpv_set_option_string(
        _mpv,
        "keepaspect",
        _videoAspectMode == OMMpvVideoAspectModeStretch ? "no" : "yes"
    );
    mpv_set_option_string(
        _mpv,
        "panscan",
        _videoAspectMode == OMMpvVideoAspectModeFill ? "1" : "0"
    );
    if (_blurayDeviceURL) {
        // The Swift boundary accepts only a completed, cache-owned ISO or
        // BDMV directory. Loading the longest title avoids disc menus and
        // therefore never starts BD-J.
        mpv_set_option_string(_mpv, "bluray-device", _blurayDeviceURL.path.UTF8String);
    }

    if (_preferredAudioLanguages.count > 0) {
        mpv_set_option_string(
            _mpv,
            "alang",
            [_preferredAudioLanguages componentsJoinedByString:@","].UTF8String
        );
    }
    if (_preferredSubtitleLanguages.count > 0) {
        mpv_set_option_string(
            _mpv,
            "slang",
            [_preferredSubtitleLanguages componentsJoinedByString:@","].UTF8String
        );
    }
    if (_subtitlesDisabled) {
        mpv_set_option_string(_mpv, "sid", "no");
    }
    [self applyPlayerOptions];
    [self applySubtitleStyleOptions];

    if (mpv_initialize(_mpv) < 0) {
        [self failWithMessage:@"libmpv could not initialize the video renderer."];
        return;
    }

    _wakeupBox = [[OMMpvCallbackBox alloc] initWithTarget:self];
    mpv_set_wakeup_callback(_mpv, OMMpvWakeup, (__bridge void *)_wakeupBox);
    mpv_observe_property(_mpv, 1, "track-list", MPV_FORMAT_NONE);
    mpv_observe_property(_mpv, 2, "aid", MPV_FORMAT_NONE);
    mpv_observe_property(_mpv, 3, "sid", MPV_FORMAT_NONE);

    CGLContextObj glContext = _videoView.videoLayer.cglContext;
    if (!glContext) {
        [self failWithMessage:@"libmpv could not create its OpenGL render context."];
        return;
    }
    mpv_opengl_init_params openGLParameters = {
        .get_proc_address = OMOpenGLProcedureAddress,
        .get_proc_address_ctx = NULL,
    };
    mpv_render_param renderParameters[] = {
        { MPV_RENDER_PARAM_API_TYPE, (void *)MPV_RENDER_API_TYPE_OPENGL },
        { MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &openGLParameters },
        { MPV_RENDER_PARAM_INVALID, NULL },
    };
    CGLLockContext(glContext);
    CGLSetCurrentContext(glContext);
    int createStatus = mpv_render_context_create(&_renderContext, _mpv, renderParameters);
    CGLSetCurrentContext(NULL);
    CGLUnlockContext(glContext);
    if (createStatus < 0) {
        _renderContext = NULL;
        [self failWithMessage:@"libmpv could not create its OpenGL render context."];
        return;
    }
    [_videoView.videoLayer attachRenderContext:_renderContext];
    _redrawBox = [[OMMpvCallbackBox alloc] initWithTarget:_videoView.videoLayer];
    mpv_render_context_set_update_callback(
        _renderContext,
        OMMpvRequestRedraw,
        (__bridge void *)_redrawBox
    );
    [_videoView.videoLayer scheduleRender];

    if (_requestHeaders.count > 0) {
        NSMutableArray<NSString *> *fields = [NSMutableArray arrayWithCapacity:_requestHeaders.count];
        [_requestHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
            [fields addObject:[NSString stringWithFormat:@"%@: %@", key, value]];
        }];
        NSString *headerFields = [fields componentsJoinedByString:@"\n"];
        mpv_set_property_string(_mpv, "http-header-fields", headerFields.UTF8String);
    }

    [self setDouble:_volume forProperty:"volume"];
    [self setDouble:_playbackRate forProperty:"speed"];
    const char *loadCommand[] = { "loadfile", _URL.absoluteString.UTF8String, "replace", NULL };
    if (mpv_command(_mpv, loadCommand) < 0) {
        [self failWithMessage:@"libmpv could not open the selected stream."];
        return;
    }
    [self emitSnapshot];
    [self play];
}

- (BOOL)isPaused { return _mpv ? [self flagForProperty:"pause"] : _paused; }
- (double)position { return (_mpv && _fileLoaded) ? [self doubleForProperty:"time-pos"] : _pendingPosition; }
- (double)duration { return _mpv ? [self doubleForProperty:"duration"] : 0; }
- (double)volume { return _mpv ? [self doubleForProperty:"volume"] : _volume; }
- (double)playbackRate { return _mpv ? [self doubleForProperty:"speed"] : _playbackRate; }
- (BOOL)hasRenderedVideoFrame {
    if (!_videoView.videoLayer.didRenderFrame || !_mpv) return NO;
    int64_t videoWidth = 0;
    return mpv_get_property(_mpv, "video-params/w", MPV_FORMAT_INT64, &videoWidth) >= 0 && videoWidth > 0;
}
- (BOOL)pictureInPictureActive { return _pictureInPictureActive; }
- (BOOL)pictureInPicturePossible {
    return !_stopped && _inlineVideoHost != nil && _videoView != nil;
}
- (NSArray<OMMpvTrack *> *)audioTracks { return [self tracksOfType:@"audio"]; }
- (NSArray<OMMpvTrack *> *)subtitleTracks { return [self tracksOfType:@"sub"]; }

- (void)togglePause { self.paused ? [self play] : [self pause]; }
- (void)play { _paused = NO; [self setFlag:NO forProperty:"pause"]; }
- (void)pause { _paused = YES; [self setFlag:YES forProperty:"pause"]; }

- (void)seekBy:(double)seconds { [self seekTo:self.position + seconds]; }

- (void)seekTo:(double)seconds {
    _pendingPosition = MAX(0, seconds);
    [self applyPendingSeekIfReady];
}

- (void)applyPendingSeekIfReady {
    if (!_mpv || !_fileLoaded || _pendingPosition <= 0) return;
    NSString *position = [NSString stringWithFormat:@"%.3f", _pendingPosition];
    const char *command[] = { "seek", position.UTF8String, "absolute", NULL };
    if (mpv_command(_mpv, command) >= 0) {
        _pendingPosition = 0;
    }
}

- (void)setVolume:(double)volume {
    _volume = MIN(MAX(volume, 0), 100);
    [self setDouble:_volume forProperty:"volume"];
}

- (void)setPlaybackRate:(double)playbackRate {
    _playbackRate = MIN(MAX(playbackRate, 0.25), 4);
    [self setDouble:_playbackRate forProperty:"speed"];
}

- (void)setVideoAspectMode:(OMMpvVideoAspectMode)mode {
    _videoAspectMode = mode;
    switch (mode) {
        case OMMpvVideoAspectModeStretch:
            [self setFlag:NO forProperty:"keepaspect"];
            [self setDouble:0 forProperty:"panscan"];
            break;
        case OMMpvVideoAspectModeFill:
            [self setFlag:YES forProperty:"keepaspect"];
            [self setDouble:1 forProperty:"panscan"];
            break;
        case OMMpvVideoAspectModeOriginal:
        default:
            [self setFlag:YES forProperty:"keepaspect"];
            [self setDouble:0 forProperty:"panscan"];
            break;
    }
}

- (void)setPreferredAudioLanguages:(NSArray<NSString *> *)languages {
    if (_didStart) return;
    _preferredAudioLanguages = [languages copy];
}

- (void)setPreferredSubtitleLanguages:(NSArray<NSString *> *)languages {
    if (_didStart) return;
    _preferredSubtitleLanguages = [languages copy];
}

- (void)setSubtitlesDisabled:(BOOL)disabled {
    if (_didStart) return;
    _subtitlesDisabled = disabled;
}

- (void)setPlayerOptions:(NSDictionary<NSString *, NSString *> *)options {
    if (_didStart) return;
    _playerOptions = [options copy];
}

- (void)applyPlayerOptions {
    // Settings may only change these; everything else stays as configured
    // above.
    NSSet<NSString *> *allowed = [NSSet setWithArray:@[
        @"hwdec",
        @"vd-lavc-software-fallback",
        @"sub-filter-sdh",
        @"sub-filter-sdh-harder",
        @"subs-with-matching-audio",
        @"subs-fallback-forced",
    ]];
    [_playerOptions enumerateKeysAndObjectsUsingBlock:^(NSString *option, NSString *value, BOOL *stop) {
        if (![allowed containsObject:option] || ![value isKindOfClass:NSString.class] || value.length > 32) return;
        mpv_set_option_string(self->_mpv, option.UTF8String, value.UTF8String);
    }];
}

- (void)addSubtitleURL:(NSURL *)URL
                 title:(NSString *)title
              language:(NSString *)language
                select:(BOOL)select {
    if (!_mpv || _stopped || !URL) return;
    NSString *scheme = URL.scheme.lowercaseString;
    if (![scheme isEqualToString:@"https"] && ![scheme isEqualToString:@"http"]) return;
    NSString *safeTitle = title.length > 0 && title.length <= 120 ? title : @"Add-on subtitle";
    NSString *safeLanguage = language.length > 0 && language.length <= 16 ? language : @"";
    // Async, so a slow subtitle server never stalls the main thread.
    const char *command[] = {
        "sub-add",
        URL.absoluteString.UTF8String,
        select ? "select" : "auto",
        safeTitle.UTF8String,
        safeLanguage.UTF8String,
        NULL
    };
    mpv_command_async(_mpv, 0, command);
}

- (void)setSubtitleStyle:(NSDictionary<NSString *, id> *)style {
    NSMutableDictionary<NSString *, id> *mergedStyle = [_subtitleStyle mutableCopy]
        ?: [NSMutableDictionary dictionary];
    [mergedStyle addEntriesFromDictionary:style];
    _subtitleStyle = [mergedStyle copy];
    if (_didStart && _mpv) {
        [self applySubtitleStyleProperties];
    }
}

- (uint64_t)selectAudioTrackWithID:(NSInteger)trackID
                        completion:(OMMpvTrackSelectionCompletion)completion {
    if (!_mpv || _stopped) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(0, NO, @"Audio track selection is unavailable.");
            });
        }
        return 0;
    }

    [self abortTrackSelectionRequest:_latestAudioTrackSelectionRequestID];
    uint64_t requestID = [self nextTrackSelectionRequestID];
    OMMpvPendingTrackSelection *pending = [OMMpvPendingTrackSelection new];
    pending.kind = OMMpvTrackSelectionKindAudio;
    pending.completion = completion;
    _pendingTrackSelections[@(requestID)] = pending;
    _latestAudioTrackSelectionRequestID = requestID;

    int64_t value = (int64_t)trackID;
    int status = mpv_set_property_async(_mpv, requestID, "aid", MPV_FORMAT_INT64, &value);
    if (status < 0) {
        [self finishTrackSelectionRequest:requestID status:status];
    }
    return requestID;
}

- (uint64_t)selectSubtitleTrackWithID:(NSNumber *)trackID
                           completion:(OMMpvTrackSelectionCompletion)completion {
    if (!_mpv || _stopped) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(0, NO, @"Subtitle track selection is unavailable.");
            });
        }
        return 0;
    }

    [self abortTrackSelectionRequest:_latestSubtitleTrackSelectionRequestID];
    uint64_t requestID = [self nextTrackSelectionRequestID];
    OMMpvPendingTrackSelection *pending = [OMMpvPendingTrackSelection new];
    pending.kind = OMMpvTrackSelectionKindSubtitle;
    pending.completion = completion;
    _pendingTrackSelections[@(requestID)] = pending;
    _latestSubtitleTrackSelectionRequestID = requestID;

    int status;
    if (!trackID) {
        const char *disabled = "no";
        status = mpv_set_property_async(_mpv, requestID, "sid", MPV_FORMAT_STRING, &disabled);
    } else {
        int64_t value = trackID.longLongValue;
        status = mpv_set_property_async(_mpv, requestID, "sid", MPV_FORMAT_INT64, &value);
    }
    if (status < 0) {
        [self finishTrackSelectionRequest:requestID status:status];
    }
    return requestID;
}

- (uint64_t)nextTrackSelectionRequestID {
    do {
        _nextTrackSelectionRequestID += 1;
        if (_nextTrackSelectionRequestID == 0) {
            _nextTrackSelectionRequestID = 100;
        }
    } while (_pendingTrackSelections[@(_nextTrackSelectionRequestID)] != nil);
    return _nextTrackSelectionRequestID;
}

- (void)abortTrackSelectionRequest:(uint64_t)requestID {
    if (requestID == 0) return;
    OMMpvPendingTrackSelection *pending = _pendingTrackSelections[@(requestID)];
    if (!pending) return;

    if (_mpv) mpv_abort_async_command(_mpv, requestID);
    [_pendingTrackSelections removeObjectForKey:@(requestID)];
    OMMpvTrackSelectionCompletion completion = pending.completion;
    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(requestID, NO, nil);
        });
    }
}

- (void)finishTrackSelectionRequest:(uint64_t)requestID status:(int)status {
    OMMpvPendingTrackSelection *pending = _pendingTrackSelections[@(requestID)];
    if (!pending) return;
    [_pendingTrackSelections removeObjectForKey:@(requestID)];

    uint64_t latestRequestID = pending.kind == OMMpvTrackSelectionKindAudio
        ? _latestAudioTrackSelectionRequestID
        : _latestSubtitleTrackSelectionRequestID;
    if (requestID != latestRequestID) return;

    if (pending.kind == OMMpvTrackSelectionKindAudio) {
        _latestAudioTrackSelectionRequestID = 0;
    } else {
        _latestSubtitleTrackSelectionRequestID = 0;
    }

    BOOL succeeded = status >= 0;
    NSString *message = nil;
    if (!succeeded) {
        message = pending.kind == OMMpvTrackSelectionKindAudio
            ? @"The selected audio track could not be activated."
            : @"The selected subtitle track could not be activated.";
        self.errorMessage = message;
    } else if (
        [self.errorMessage isEqualToString:@"The selected audio track could not be activated."]
        || [self.errorMessage isEqualToString:@"The selected subtitle track could not be activated."]
    ) {
        self.errorMessage = nil;
    }

    OMMpvTrackSelectionCompletion completion = pending.completion;
    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(requestID, succeeded, message);
        });
    }
}

- (void)finishTrackSelectionForEvent:(mpv_event *)event {
    if (!event) return;
    [self finishTrackSelectionRequest:event->reply_userdata status:event->error];
}

- (void)cycleSubtitles {
    if (!_mpv) return;
    const char *command[] = { "cycle", "sub", NULL };
    mpv_command(_mpv, command);
}

- (void)cycleAudioTrack {
    if (!_mpv) return;
    const char *command[] = { "cycle", "audio", NULL };
    mpv_command(_mpv, command);
}

- (void)attachVideoViewToHost:(NSView *)hostView {
    NSAssert(NSThread.isMainThread, @"The video surface must be attached on the main thread.");
    if (_inlineVideoHost == hostView && _videoView.superview == hostView) {
        _videoView.frame = hostView.bounds;
        return;
    }

    if (!_pictureInPictureActive) {
        [_videoView removeFromSuperview];
    }
    _inlineVideoHost = hostView;
    if (!_pictureInPictureActive) {
        [self embedVideoViewInHost:hostView];
    }
}

- (void)detachVideoViewFromHost:(NSView *)hostView {
    NSAssert(NSThread.isMainThread, @"The video surface must be detached on the main thread.");
    if (_inlineVideoHost != hostView) return;

    if (!_pictureInPictureActive && _videoView.superview == hostView) {
        [_videoView removeFromSuperview];
    }
    _inlineVideoHost = nil;
}

- (void)enterPictureInPicture {
    if (!self.pictureInPicturePossible || _pictureInPictureActive) return;

    NSPanel *panel = _pictureInPicturePanel ?: [self makePictureInPicturePanel];
    _pictureInPicturePanel = panel;
    [self embedVideoViewInHost:panel.contentView];
    _pictureInPictureActive = YES;
    [panel orderFront:nil];
}

- (void)exitPictureInPicture {
    if (!_pictureInPictureActive) return;

    if (_inlineVideoHost) {
        [self embedVideoViewInHost:_inlineVideoHost];
    }
    [_pictureInPicturePanel orderOut:nil];
    _pictureInPictureActive = NO;
}

- (void)togglePictureInPicture {
    _pictureInPictureActive ? [self exitPictureInPicture] : [self enterPictureInPicture];
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    if (sender == _pictureInPicturePanel) {
        [self exitPictureInPicture];
        return NO;
    }
    return YES;
}

- (void)embedVideoViewInHost:(NSView *)hostView {
    if (_videoView.superview == hostView) {
        _videoView.frame = hostView.bounds;
        return;
    }

    [_videoView removeFromSuperview];
    _videoView.translatesAutoresizingMaskIntoConstraints = YES;
    _videoView.frame = hostView.bounds;
    _videoView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [hostView addSubview:_videoView];
    [_videoView.videoLayer scheduleRender];
}

- (NSPanel *)makePictureInPicturePanel {
    NSSize contentSize = NSMakeSize(480, 270);
    NSScreen *screen = _inlineVideoHost.window.screen ?: NSScreen.mainScreen;
    NSRect visibleFrame = screen.visibleFrame;
    NSRect contentRect = NSMakeRect(
        NSMaxX(visibleFrame) - contentSize.width - 24,
        NSMinY(visibleFrame) + 24,
        contentSize.width,
        contentSize.height
    );
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:contentRect
        styleMask:NSWindowStyleMaskTitled
            | NSWindowStyleMaskClosable
            | NSWindowStyleMaskResizable
            | NSWindowStyleMaskFullSizeContentView
            | NSWindowStyleMaskNonactivatingPanel
        backing:NSBackingStoreBuffered
        defer:NO
    ];
    panel.title = @"Picture in Picture";
    panel.titleVisibility = NSWindowTitleHidden;
    panel.titlebarAppearsTransparent = YES;
    panel.movableByWindowBackground = YES;
    panel.releasedWhenClosed = NO;
    panel.hidesOnDeactivate = NO;
    panel.level = NSFloatingWindowLevel;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
        | NSWindowCollectionBehaviorFullScreenAuxiliary;
    panel.contentAspectRatio = NSMakeSize(16, 9);
    panel.minSize = NSMakeSize(320, 180);
    panel.backgroundColor = NSColor.blackColor;
    panel.delegate = self;
    return panel;
}

- (void)stop {
    [self exitPictureInPicture];
    _inlineVideoHost = nil;
    _stopped = YES;
    for (NSNumber *requestID in _pendingTrackSelections.allKeys) {
        [self abortTrackSelectionRequest:requestID.unsignedLongLongValue];
    }
    [self destroyPlayer];
}

- (void)failWithMessage:(NSString *)message {
    self.errorMessage = message;
    _tracksLoading = NO;
    [self emitSnapshot];
    [self destroyPlayer];
}

- (NSString *)subtitleBackgroundRGBForBackground:(NSString *)background {
    NSString *rgb = _subtitleStyle[@"backgroundRGB"];
    if (![background isKindOfClass:NSString.class] || [background isEqualToString:@"none"]
        || ![rgb isKindOfClass:NSString.class] || rgb.length != 6) {
        return @"000000";
    }
    NSCharacterSet *nonHex = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFabcdef"] invertedSet];
    return [rgb rangeOfCharacterFromSet:nonHex].location == NSNotFound ? rgb.uppercaseString : @"000000";
}

- (void)applySubtitleStyleOptions {
    if (_subtitleStyle.count == 0) return;

    NSDictionary<NSString *, NSString *> *stringOptions = @{
        @"font": @"sub-font",
        @"textColor": @"sub-color",
        @"outlineColor": @"sub-outline-color",
        @"backgroundColor": @"sub-back-color",
        @"edgeStyle": @"sub-border-style",
        @"alignment": @"sub-align-x",
    };
    [stringOptions enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *option, BOOL *stop) {
        NSString *value = self->_subtitleStyle[key];
        if ([value isKindOfClass:NSString.class] && value.length <= 128) {
            mpv_set_option_string(self->_mpv, option.UTF8String, value.UTF8String);
        }
    }];

    NSDictionary<NSString *, NSString *> *numberOptions = @{
        @"fontSize": @"sub-font-size",
        @"scale": @"sub-scale",
        @"outlineSize": @"sub-outline-size",
        @"shadowOffset": @"sub-shadow-offset",
        @"shadowBlur": @"sub-blur",
        @"position": @"sub-pos",
        @"margin": @"sub-margin-x",
        @"delay": @"sub-delay",
    };
    [numberOptions enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *option, BOOL *stop) {
        NSNumber *value = self->_subtitleStyle[key];
        if ([value isKindOfClass:NSNumber.class] && isfinite(value.doubleValue)) {
            mpv_set_option_string(self->_mpv, option.UTF8String, value.stringValue.UTF8String);
        }
    }];

    NSNumber *bold = _subtitleStyle[@"bold"];
    NSNumber *italic = _subtitleStyle[@"italic"];
    mpv_set_option_string(_mpv, "sub-bold", bold.boolValue ? "yes" : "no");
    mpv_set_option_string(_mpv, "sub-italic", italic.boolValue ? "yes" : "no");
    NSNumber *shadowOpacity = _subtitleStyle[@"shadowOpacity"];
    NSString *background = _subtitleStyle[@"background"];
    if (shadowOpacity || background) {
        double alphaFraction = [background isEqualToString:@"solid"]
            ? 0.9
            : ([background isEqualToString:@"translucent"]
                ? 0.55
                : MIN(MAX(shadowOpacity.doubleValue, 0), 1));
        // With a box, sub-back-color is the box; without one it is the
        // shadow, which stays black.
        NSString *rgb = [self subtitleBackgroundRGBForBackground:background];
        NSString *color = [NSString stringWithFormat:@"#%02X%@", (int)llround(alphaFraction * 255), rgb];
        mpv_set_option_string(_mpv, "sub-back-color", color.UTF8String);
        mpv_set_option_string(
            _mpv,
            "sub-border-style",
            [background isEqualToString:@"none"] ? "outline-and-shadow" : "background-box"
        );
        mpv_set_option_string(_mpv, "sub-shadow-offset", shadowOpacity.doubleValue > 0 ? "2" : "0");
    }
    // Preserve authored ASS positioning while allowing the user's explicit
    // visual preference to override the style layer.
    mpv_set_option_string(_mpv, "sub-ass-override", "style");
}

- (void)applySubtitleStyleProperties {
    if (!_mpv || _subtitleStyle.count == 0) return;

    NSDictionary<NSString *, NSString *> *stringProperties = @{
        @"font": @"sub-font",
        @"textColor": @"sub-color",
        @"outlineColor": @"sub-outline-color",
        @"backgroundColor": @"sub-back-color",
        @"edgeStyle": @"sub-border-style",
        @"alignment": @"sub-align-x",
    };
    [stringProperties enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *property, BOOL *stop) {
        NSString *value = self->_subtitleStyle[key];
        if ([value isKindOfClass:NSString.class] && value.length <= 128) {
            mpv_set_property_string(self->_mpv, property.UTF8String, value.UTF8String);
        }
    }];

    NSDictionary<NSString *, NSString *> *numberProperties = @{
        @"fontSize": @"sub-font-size",
        @"scale": @"sub-scale",
        @"outlineSize": @"sub-outline-size",
        @"shadowOffset": @"sub-shadow-offset",
        @"shadowBlur": @"sub-blur",
        @"position": @"sub-pos",
        @"margin": @"sub-margin-x",
        @"delay": @"sub-delay",
    };
    [numberProperties enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *property, BOOL *stop) {
        NSNumber *value = self->_subtitleStyle[key];
        if ([value isKindOfClass:NSNumber.class] && isfinite(value.doubleValue)) {
            mpv_set_property_string(self->_mpv, property.UTF8String, value.stringValue.UTF8String);
        }
    }];

    NSNumber *bold = _subtitleStyle[@"bold"];
    NSNumber *italic = _subtitleStyle[@"italic"];
    if (bold) mpv_set_property_string(_mpv, "sub-bold", bold.boolValue ? "yes" : "no");
    if (italic) mpv_set_property_string(_mpv, "sub-italic", italic.boolValue ? "yes" : "no");
    NSNumber *shadowOpacity = _subtitleStyle[@"shadowOpacity"];
    NSString *background = _subtitleStyle[@"background"];
    if (shadowOpacity || background) {
        double alphaFraction = [background isEqualToString:@"solid"]
            ? 0.9
            : ([background isEqualToString:@"translucent"]
                ? 0.55
                : MIN(MAX(shadowOpacity.doubleValue, 0), 1));
        // With a box, sub-back-color is the box; without one it is the
        // shadow, which stays black.
        NSString *rgb = [self subtitleBackgroundRGBForBackground:background];
        NSString *color = [NSString stringWithFormat:@"#%02X%@", (int)llround(alphaFraction * 255), rgb];
        mpv_set_property_string(_mpv, "sub-back-color", color.UTF8String);
        mpv_set_property_string(
            _mpv,
            "sub-border-style",
            [background isEqualToString:@"none"] ? "outline-and-shadow" : "background-box"
        );
        mpv_set_property_string(_mpv, "sub-shadow-offset", shadowOpacity.doubleValue > 0 ? "2" : "0");
    }
    mpv_set_property_string(_mpv, "sub-ass-override", "style");
}

- (void)drainEvents {
    if (!_mpv || _stopped) return;

    BOOL shouldEmitSnapshot = NO;
    while (_mpv) {
        mpv_event *event = mpv_wait_event(_mpv, 0);
        if (!event || event->event_id == MPV_EVENT_NONE) break;

        switch (event->event_id) {
        case MPV_EVENT_START_FILE:
            _fileLoaded = NO;
            _tracksLoading = YES;
            self.errorMessage = nil;
            shouldEmitSnapshot = YES;
            break;
        case MPV_EVENT_FILE_LOADED:
            _fileLoaded = YES;
            _tracksLoading = NO;
            self.errorMessage = nil;
            [self applyPendingSeekIfReady];
            shouldEmitSnapshot = YES;
            break;
        case MPV_EVENT_PROPERTY_CHANGE:
            shouldEmitSnapshot = YES;
            break;
        case MPV_EVENT_SET_PROPERTY_REPLY:
            [self finishTrackSelectionForEvent:event];
            shouldEmitSnapshot = YES;
            break;
        case MPV_EVENT_END_FILE: {
            _tracksLoading = NO;
            mpv_event_end_file *endFile = event->data;
            if (endFile && endFile->reason == MPV_END_FILE_REASON_ERROR) {
                if (_blurayDeviceURL) {
                    self.errorMessage = @"This disc is not a supported unencrypted Blu-ray.";
                    shouldEmitSnapshot = YES;
                    break;
                }
                const char *description = mpv_error_string(endFile->error);
                NSString *detail = description
                    ? [NSString stringWithUTF8String:description]
                    : @"unknown playback error";
                self.errorMessage = [NSString stringWithFormat:
                    @"libmpv could not play the selected source (%@).",
                    detail
                ];
            }
            shouldEmitSnapshot = YES;
            break;
        }
        case MPV_EVENT_QUEUE_OVERFLOW:
            shouldEmitSnapshot = YES;
            break;
        default:
            break;
        }
    }

    if (shouldEmitSnapshot) [self emitSnapshot];
}

- (void)emitSnapshot {
    void (^handler)(OMMpvPlaybackSnapshot *) = self.stateChangeHandler;
    if (!handler) return;

    OMMpvPlaybackSnapshot *snapshot = [[OMMpvPlaybackSnapshot alloc]
        initWithAudioTracks:self.audioTracks
        subtitleTracks:self.subtitleTracks
        tracksLoading:_tracksLoading
        errorMessage:self.errorMessage
    ];
    handler(snapshot);
}

- (void)destroyPlayer {
    if (_renderContext) {
        mpv_render_context_set_update_callback(_renderContext, NULL, NULL);
        [_videoView.videoLayer freeRenderContext];
        _renderContext = NULL;
        [_videoView.videoLayer scheduleRender];
    }
    if (_mpv) {
        // Clearing the callback is synchronous, so mpv can't call into the box
        // after this line. Blocks already queued hold the box, not self.
        mpv_set_wakeup_callback(_mpv, NULL, NULL);
        mpv_handle *mpv = _mpv;
        _mpv = NULL;
        // mpv_terminate_destroy waits for the demuxer and network stream to
        // shut down, which can take seconds on a slow source. Do it off main
        // so closing the player doesn't freeze the app.
        dispatch_async(OMMpvTeardownQueue(), ^{
            mpv_terminate_destroy(mpv);
        });
    }
    self.stateChangeHandler = nil;
}

- (NSArray<OMMpvTrack *> *)tracksOfType:(NSString *)requestedType {
    if (!_mpv) return @[];

    int64_t count = 0;
    if (mpv_get_property(_mpv, "track-list/count", MPV_FORMAT_INT64, &count) < 0 || count <= 0) {
        return @[];
    }

    NSMutableArray<OMMpvTrack *> *tracks = [NSMutableArray array];
    for (int64_t index = 0; index < count; index += 1) {
        NSString *prefix = [NSString stringWithFormat:@"track-list/%ld", (long)index];
        NSString *type = [self stringForProperty:[prefix stringByAppendingString:@"/type"].UTF8String];
        if (![type isEqualToString:requestedType]) continue;

        int64_t trackID = 0;
        NSString *identifierProperty = [prefix stringByAppendingString:@"/id"];
        if (mpv_get_property(_mpv, identifierProperty.UTF8String, MPV_FORMAT_INT64, &trackID) < 0) {
            continue;
        }
        int selected = 0;
        NSString *selectedProperty = [prefix stringByAppendingString:@"/selected"];
        mpv_get_property(_mpv, selectedProperty.UTF8String, MPV_FORMAT_FLAG, &selected);

        [tracks addObject:[[OMMpvTrack alloc]
            initWithTrackID:(NSInteger)trackID
            title:[self stringForProperty:[prefix stringByAppendingString:@"/title"].UTF8String]
            language:[self stringForProperty:[prefix stringByAppendingString:@"/lang"].UTF8String]
            codec:[self stringForProperty:[prefix stringByAppendingString:@"/codec"].UTF8String]
            selected:selected != 0
        ]];
    }
    return tracks;
}

- (NSString *)stringForProperty:(const char *)property {
    if (!_mpv) return nil;
    char *value = mpv_get_property_string(_mpv, property);
    if (!value) return nil;
    NSString *result = [NSString stringWithUTF8String:value];
    mpv_free(value);
    return result.length > 0 ? result : nil;
}

- (BOOL)flagForProperty:(const char *)property {
    int value = 0;
    return mpv_get_property(_mpv, property, MPV_FORMAT_FLAG, &value) >= 0 && value != 0;
}

- (double)doubleForProperty:(const char *)property {
    double value = 0;
    return mpv_get_property(_mpv, property, MPV_FORMAT_DOUBLE, &value) >= 0 && isfinite(value) ? value : 0;
}

- (void)setFlag:(BOOL)value forProperty:(const char *)property {
    if (!_mpv) return;
    int flag = value ? 1 : 0;
    mpv_set_property(_mpv, property, MPV_FORMAT_FLAG, &flag);
}

- (void)setDouble:(double)value forProperty:(const char *)property {
    if (!_mpv) return;
    mpv_set_property(_mpv, property, MPV_FORMAT_DOUBLE, &value);
}

@end
#endif
