//
//  MPVPlayerController.m
//  Omnia
//

#import "MPVPlayerController.h"

#if TARGET_OS_OSX
#import <mpv/client.h>
#import <mpv/render_gl.h>
#import <OpenGL/gl.h>
#import <math.h>

static void *OMOpenGLProcedureAddress(void *context, const char *name) {
    CFStringRef symbolName = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingASCII);
    void *address = CFBundleGetFunctionPointerForName(
        CFBundleGetBundleWithIdentifier(CFSTR("com.apple.opengl")),
        symbolName
    );
    CFRelease(symbolName);
    return address;
}

@interface OMMpvOpenGLView : NSOpenGLView
@property (nonatomic, assign, nullable) mpv_render_context *renderContext;
@property (nonatomic, assign) BOOL didRenderFrame;
@end

@implementation OMMpvOpenGLView

- (instancetype)initWithFrame:(NSRect)frameRect {
    NSOpenGLPixelFormatAttribute attributes[] = {
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAAccelerated,
        0,
    };
    NSOpenGLPixelFormat *pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
    self = [super initWithFrame:frameRect pixelFormat:pixelFormat];
    if (!self) return nil;

    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.wantsBestResolutionOpenGLSurface = YES;
    GLint swapInterval = 1;
    [self.openGLContext setValues:&swapInterval forParameter:NSOpenGLCPSwapInterval];
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    [self.openGLContext makeCurrentContext];
    NSRect backingBounds = [self convertRectToBacking:self.bounds];
    int width = MAX((int)llround(NSWidth(backingBounds)), 1);
    int height = MAX((int)llround(NSHeight(backingBounds)), 1);

    if (self.renderContext) {
        mpv_render_context_update(self.renderContext);
        mpv_opengl_fbo framebuffer = {
            .fbo = 0,
            .w = width,
            .h = height,
            .internal_format = 0,
        };
        int flipY = 1;
        mpv_render_param parameters[] = {
            { MPV_RENDER_PARAM_OPENGL_FBO, &framebuffer },
            { MPV_RENDER_PARAM_FLIP_Y, &flipY },
            { MPV_RENDER_PARAM_INVALID, NULL },
        };
        if (mpv_render_context_render(self.renderContext, parameters) >= 0) {
            self.didRenderFrame = YES;
        }
    } else {
        glClearColor(0, 0, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);
    }
    [self.openGLContext flushBuffer];
}

- (void)reshape {
    [super reshape];
    self.needsDisplay = YES;
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
    OMMpvOpenGLView *view = (__bridge OMMpvOpenGLView *)context;
    dispatch_async(dispatch_get_main_queue(), ^{
        view.needsDisplay = YES;
    });
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
    NSDictionary<NSString *, id> *_subtitleStyle;
    BOOL _tracksLoading;
    BOOL _fileLoaded;
    __weak NSView *_inlineVideoHost;
    NSPanel *_pictureInPicturePanel;
    BOOL _pictureInPictureActive;
    uint64_t _nextTrackSelectionRequestID;
    uint64_t _latestAudioTrackSelectionRequestID;
    uint64_t _latestSubtitleTrackSelectionRequestID;
    NSMutableDictionary<NSNumber *, OMMpvPendingTrackSelection *> *_pendingTrackSelections;
}
@property (nonatomic, readwrite) OMMpvOpenGLView *videoView;
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
    OMMpvPlayerController *controller = (__bridge OMMpvPlayerController *)context;
    dispatch_async(dispatch_get_main_queue(), ^{
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
    _videoView = [[OMMpvOpenGLView alloc] initWithFrame:NSZeroRect];
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void)startIfNeeded {
    if (_didStart || _stopped || self.errorMessage) return;

    // The render context must be created on the same main/OpenGL thread that
    // draws it. SwiftUI calls again after mounting if the first update races
    // with window attachment.
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
    mpv_set_option_string(_mpv, "video-sync", "display-resample");
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
    [self applySubtitleStyleOptions];

    if (mpv_initialize(_mpv) < 0) {
        [self failWithMessage:@"libmpv could not initialize the video renderer."];
        return;
    }

    mpv_set_wakeup_callback(_mpv, OMMpvWakeup, (__bridge void *)self);
    mpv_observe_property(_mpv, 1, "track-list", MPV_FORMAT_NONE);
    mpv_observe_property(_mpv, 2, "aid", MPV_FORMAT_NONE);
    mpv_observe_property(_mpv, 3, "sid", MPV_FORMAT_NONE);

    [_videoView.openGLContext makeCurrentContext];
    mpv_opengl_init_params openGLParameters = {
        .get_proc_address = OMOpenGLProcedureAddress,
        .get_proc_address_ctx = NULL,
    };
    mpv_render_param renderParameters[] = {
        { MPV_RENDER_PARAM_API_TYPE, (void *)MPV_RENDER_API_TYPE_OPENGL },
        { MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &openGLParameters },
        { MPV_RENDER_PARAM_INVALID, NULL },
    };
    if (mpv_render_context_create(&_renderContext, _mpv, renderParameters) < 0) {
        [self failWithMessage:@"libmpv could not create its OpenGL render context."];
        return;
    }
    _videoView.renderContext = _renderContext;
    mpv_render_context_set_update_callback(
        _renderContext,
        OMMpvRequestRedraw,
        (__bridge void *)_videoView
    );
    _videoView.needsDisplay = YES;

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
    if (!_videoView.didRenderFrame || !_mpv) return NO;
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
    _inlineVideoHost = hostView;
    if (!_pictureInPictureActive) {
        [self embedVideoViewInHost:hostView];
    }
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
    _videoView.needsDisplay = YES;
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
        NSString *color = [NSString stringWithFormat:@"#%02X000000", (int)llround(alphaFraction * 255)];
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
        NSString *color = [NSString stringWithFormat:@"#%02X000000", (int)llround(alphaFraction * 255)];
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
        [_videoView.openGLContext makeCurrentContext];
        _videoView.renderContext = NULL;
        mpv_render_context_free(_renderContext);
        _renderContext = NULL;
        _videoView.needsDisplay = YES;
    }
    if (_mpv) {
        mpv_set_wakeup_callback(_mpv, NULL, NULL);
        mpv_terminate_destroy(_mpv);
        _mpv = NULL;
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
