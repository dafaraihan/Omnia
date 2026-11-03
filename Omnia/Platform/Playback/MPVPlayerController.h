//
//  MPVPlayerController.h
//  Omnia
//

#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

#if TARGET_OS_OSX || OMNIA_IOS_MPV
#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
typedef NSView OMMpvPlatformView;
#else
#import <UIKit/UIKit.h>
#import <CoreVideo/CoreVideo.h>
typedef UIView OMMpvPlatformView;
#endif

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OMMpvVideoAspectMode) {
    OMMpvVideoAspectModeOriginal,
    OMMpvVideoAspectModeStretch,
    OMMpvVideoAspectModeFill,
};

typedef void (^OMMpvTrackSelectionCompletion)(
    uint64_t requestID,
    BOOL succeeded,
    NSString * _Nullable errorMessage
);

/// Immutable representation of one embedded media track reported by mpv.
@interface OMMpvTrack : NSObject

@property (nonatomic, readonly) NSInteger trackID;
@property (nonatomic, readonly, nullable) NSString *title;
@property (nonatomic, readonly, nullable) NSString *language;
@property (nonatomic, readonly, nullable) NSString *codec;
@property (nonatomic, readonly, getter=isSelected) BOOL selected;
/// Where an added subtitle file came from; nil for tracks inside the video.
@property (nonatomic, readonly, nullable) NSString *externalFilename;

- (instancetype)initWithTrackID:(NSInteger)trackID
                          title:(nullable NSString *)title
                       language:(nullable NSString *)language
                          codec:(nullable NSString *)codec
                       selected:(BOOL)selected;
- (instancetype)initWithTrackID:(NSInteger)trackID
                          title:(nullable NSString *)title
                       language:(nullable NSString *)language
                          codec:(nullable NSString *)codec
                       selected:(BOOL)selected
               externalFilename:(nullable NSString *)externalFilename NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

/// Immutable state published after relevant libmpv lifecycle and track events.
@interface OMMpvPlaybackSnapshot : NSObject

@property (nonatomic, readonly) NSArray<OMMpvTrack *> *audioTracks;
@property (nonatomic, readonly) NSArray<OMMpvTrack *> *subtitleTracks;
@property (nonatomic, readonly) BOOL tracksLoading;
@property (nonatomic, readonly, nullable) NSString *errorMessage;

- (instancetype)init NS_UNAVAILABLE;

@end

/// Thin Cocoa ownership wrapper around one libmpv core. Swift owns the
/// presentation and controls; libmpv owns demuxing, codecs, subtitles, and
/// the video output attached to `videoView`.
@interface OMMpvPlayerController : NSObject

@property (nonatomic, readonly) OMMpvPlatformView *videoView;
@property (nonatomic, readonly, nullable) NSString *errorMessage;
@property (nonatomic, readonly, getter=isPaused) BOOL paused;
@property (nonatomic, readonly) double position;
@property (nonatomic, readonly) double duration;
@property (nonatomic, readonly) double volume;
@property (nonatomic, readonly) double playbackRate;
@property (nonatomic, readonly) BOOL hasRenderedVideoFrame;
@property (nonatomic, readonly) BOOL pictureInPictureActive;
@property (nonatomic, readonly) BOOL pictureInPicturePossible;
@property (nonatomic, readonly) NSArray<OMMpvTrack *> *audioTracks;
@property (nonatomic, readonly) NSArray<OMMpvTrack *> *subtitleTracks;
@property (nonatomic, copy, nullable) void (^stateChangeHandler)(OMMpvPlaybackSnapshot *snapshot);
/// Draw with gpu-next on Metal (MoltenVK) instead of OpenGL. Set before
/// the player starts; ignored afterwards.
@property (nonatomic) BOOL prefersMetalRendering;
/// Whether Metal is drawing now. False when it was never asked for or fell
/// back to OpenGL.
@property (nonatomic, readonly) BOOL usingMetalRendering;
/// Why Metal was asked for but OpenGL is drawing, for Diagnostics.
@property (nonatomic, readonly, nullable) NSString *renderingFallbackReason;

- (instancetype)initWithURL:(NSURL *)URL
              requestHeaders:(NSDictionary<NSString *, NSString *> *)requestHeaders;
- (instancetype)initWithURL:(NSURL *)URL
              requestHeaders:(NSDictionary<NSString *, NSString *> *)requestHeaders
              blurayDeviceURL:(nullable NSURL *)blurayDeviceURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Starts only once `videoView` belongs to a real window. Calling this
/// repeatedly is safe and lets SwiftUI finish mounting the native view first.
- (void)startIfNeeded;
- (void)togglePause;
- (void)play;
- (void)pause;
- (void)seekBy:(double)seconds;
- (void)seekTo:(double)seconds;
/// A quick seek to the nearest keyframe, for following a timeline drag.
- (void)previewSeekTo:(double)seconds;
- (void)setVolume:(double)volume;
- (void)setPlaybackRate:(double)playbackRate;
- (void)setVideoAspectMode:(OMMpvVideoAspectMode)mode;
- (void)setPreferredAudioLanguages:(NSArray<NSString *> *)languages;
- (void)setPreferredSubtitleLanguages:(NSArray<NSString *> *)languages;
- (void)setSubtitlesDisabled:(BOOL)disabled;
- (void)setSubtitleStyle:(NSDictionary<NSString *, id> *)style;
/// Player options from Settings (decoder, subtitle filters), applied when
/// playback starts. Only options Omnia knows are accepted.
- (void)setPlayerOptions:(NSDictionary<NSString *, NSString *> *)options;
/// Adds an add-on's subtitle file as a track without blocking playback.
- (void)addSubtitleURL:(NSURL *)URL
                 title:(nullable NSString *)title
              language:(nullable NSString *)language
                select:(BOOL)select NS_SWIFT_NAME(addSubtitleURL(_:title:language:select:));
- (uint64_t)selectAudioTrackWithID:(NSInteger)trackID
                        completion:(nullable OMMpvTrackSelectionCompletion)completion
    NS_SWIFT_NAME(selectAudioTrack(id:completion:));
- (uint64_t)selectSubtitleTrackWithID:(nullable NSNumber *)trackID
                           completion:(nullable OMMpvTrackSelectionCompletion)completion
    NS_SWIFT_NAME(selectSubtitleTrack(id:completion:));
/// Measures how loud the audio is, without changing it, so subtitles can
/// be lined up with speech. Off by default.
- (void)setSpeechActivityProbeEnabled:(BOOL)enabled;
/// Loudness of the latest stretch of audio in dBFS, or nil while the probe
/// is off or has not heard anything yet.
- (nullable NSNumber *)speechActivityLevel;
- (void)cycleSubtitles;
- (void)cycleAudioTrack;
- (void)attachVideoViewToHost:(OMMpvPlatformView *)hostView;
- (void)detachVideoViewFromHost:(OMMpvPlatformView *)hostView;
- (void)enterPictureInPicture;
- (void)exitPictureInPicture;
- (void)togglePictureInPicture;
#if !TARGET_OS_OSX
/// iOS doesn't allow GPU work in the background, so while a video floats mpv
/// draws on the CPU and hands each frame to `frameHandler`, on a background
/// queue. Returns NO if it can't. The end call goes back to the Metal output.
- (BOOL)beginSampleBufferOutput:(void (^)(CVPixelBufferRef frame))frameHandler;
- (void)endSampleBufferOutput;
#endif
/// Saves the frame on screen, without subtitles, as an image at `URL` (the
/// extension picks the format). Blocks until the file is written.
- (BOOL)writeCurrentSceneToURL:(NSURL *)URL NS_SWIFT_NAME(writeCurrentScene(to:));
- (void)stop;

@end

NS_ASSUME_NONNULL_END
#endif
