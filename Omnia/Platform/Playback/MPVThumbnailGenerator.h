#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^OMMpvThumbnailCompletion)(
    NSImage * _Nullable image,
    NSError * _Nullable error
);

@interface OMMpvThumbnailGenerator : NSObject

- (instancetype)initWithURL:(NSURL *)URL
             requestHeaders:(NSDictionary<NSString *, NSString *> *)requestHeaders
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (uint64_t)requestFrameAt:(double)seconds
               maximumSize:(NSSize)maximumSize
                completion:(OMMpvThumbnailCompletion)completion
    NS_SWIFT_NAME(requestFrame(at:maximumSize:completion:));
- (void)cancelPendingRequest;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
