//
//  MPVPlayerController.h
//  Omnia
//

#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>

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

- (instancetype)initWithTrackID:(NSInteger)trackID
                          title:(nullable NSString *)title
                       language:(nullable NSString *)language
                          codec:(nullable NSString *)codec
                       selected:(BOOL)selected NS_DESIGNATED_INITIALIZER;
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

@property (nonatomic, readonly) NSView *videoView;
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

- (instancetype)initWithURL:(NSURL *)URL
              requestHeaders:(NSDictionary<NSString *, NSString *> *)requestHeaders;
- (instancetype)initWithURL:(NSURL *)URL
              requestHeaders:(NSDictionary<NSString *, NSString *> *)requestHeaders
              blurayDeviceURL:(nullable NSURL *)blurayDeviceURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Starts only once `videoView` belongs to a real macOS window. Calling this
/// repeatedly is safe and lets SwiftUI finish mounting the native view first.
- (void)startIfNeeded;
- (void)togglePause;
- (void)play;
- (void)pause;
- (void)seekBy:(double)seconds;
- (void)seekTo:(double)seconds;
- (void)setVolume:(double)volume;
- (void)setPlaybackRate:(double)playbackRate;
- (void)setVideoAspectMode:(OMMpvVideoAspectMode)mode;
- (void)setPreferredAudioLanguages:(NSArray<NSString *> *)languages;
- (void)setPreferredSubtitleLanguages:(NSArray<NSString *> *)languages;
- (void)setSubtitlesDisabled:(BOOL)disabled;
- (void)setSubtitleStyle:(NSDictionary<NSString *, id> *)style;
- (uint64_t)selectAudioTrackWithID:(NSInteger)trackID
                        completion:(nullable OMMpvTrackSelectionCompletion)completion
    NS_SWIFT_NAME(selectAudioTrack(id:completion:));
- (uint64_t)selectSubtitleTrackWithID:(nullable NSNumber *)trackID
                           completion:(nullable OMMpvTrackSelectionCompletion)completion
    NS_SWIFT_NAME(selectSubtitleTrack(id:completion:));
- (void)cycleSubtitles;
- (void)cycleAudioTrack;
- (void)attachVideoViewToHost:(NSView *)hostView;
- (void)enterPictureInPicture;
- (void)exitPictureInPicture;
- (void)togglePictureInPicture;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
#endif
