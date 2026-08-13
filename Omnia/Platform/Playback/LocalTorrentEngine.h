#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

#if TARGET_OS_OSX
NS_ASSUME_NONNULL_BEGIN

typedef void (^OMLocalTorrentProgressHandler)(double progress, int64_t downloadedBytes, int64_t totalBytes);
typedef void (^OMLocalTorrentCompletionHandler)(NSURL * _Nullable fileURL, NSError * _Nullable error);

typedef NS_ENUM(NSInteger, OMLocalTorrentMediaKind) {
    OMLocalTorrentMediaKindFile = 0,
    OMLocalTorrentMediaKindBluRayDirectory = 1,
};

/// macOS-only, one-transfer local torrent adapter. The Swift boundary validates
/// the descriptor and storage plan before this object is created. The native
/// adapter never receives an add-on-selected output path.
@interface OMLocalTorrentEngine : NSObject

@property (class, nonatomic, readonly, getter=isAvailable) BOOL available;
@property (nonatomic, readonly) OMLocalTorrentMediaKind completedMediaKind;
@property (nonatomic, readonly) int64_t completedBytes;

- (instancetype)initWithCacheDirectory:(NSURL *)cacheDirectory
                   maximumDownloadBytes:(int64_t)maximumDownloadBytes
                       minimumFreeBytes:(int64_t)minimumFreeBytes
             downloadLimitBytesPerSecond:(int64_t)downloadLimitBytesPerSecond
               uploadLimitBytesPerSecond:(int64_t)uploadLimitBytesPerSecond
    NS_SWIFT_NAME(init(cacheDirectory:maximumDownloadBytes:minimumFreeBytes:downloadLimitBytesPerSecond:uploadLimitBytesPerSecond:))
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)downloadMagnetURL:(NSURL *)magnetURL
                 fileIndex:(nullable NSNumber *)fileIndex
                  progress:(nullable OMLocalTorrentProgressHandler)progress
                completion:(OMLocalTorrentCompletionHandler)completion
    NS_SWIFT_NAME(download(magnetURL:fileIndex:progress:completion:));

- (void)cancel;

+ (BOOL)isSupportedBluRayLayoutForTesting:(NSArray<NSString *> *)relativePaths
                                    sizes:(NSArray<NSNumber *> *)sizes
                    symbolicLinkIndices:(NSArray<NSNumber *> *)symbolicLinkIndices;
+ (int64_t)remainingDownloadBytesForTesting:(int64_t)selectedBytes
                                    rootURL:(NSURL *)rootURL
                           selectedFileURLs:(NSArray<NSURL *> *)selectedFileURLs;

@end

NS_ASSUME_NONNULL_END
#endif
