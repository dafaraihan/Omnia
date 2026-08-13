#import "LocalTorrentEngine.h"

#if TARGET_OS_OSX
#import <atomic>
#import <climits>

static NSString *const OMLocalTorrentErrorDomain = @"PrimeDeca.Omnia.LocalTorrent";

typedef NS_ENUM(NSInteger, OMLocalTorrentErrorCode) {
    OMLocalTorrentErrorUnavailable = 1,
    OMLocalTorrentErrorInvalidInput = 2,
    OMLocalTorrentErrorMetadataTimeout = 3,
    OMLocalTorrentErrorInvalidFile = 4,
    OMLocalTorrentErrorItemTooLarge = 5,
    OMLocalTorrentErrorCancelled = 6,
    OMLocalTorrentErrorNativeFailure = 7,
};

static NSError *OMTorrentError(OMLocalTorrentErrorCode code, NSString *message) {
    return [NSError errorWithDomain:OMLocalTorrentErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

#if defined(OMNIA_LOCAL_TORRENT) && OMNIA_LOCAL_TORRENT
#include <chrono>
#include <filesystem>
#include <memory>
#include <thread>
#include <vector>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_info.hpp>

namespace lt = libtorrent;
namespace fs = std::filesystem;

static bool OMPathIsConfined(fs::path const& root, fs::path const& candidate) {
    auto normalizedRoot = root.lexically_normal();
    auto normalizedCandidate = candidate.lexically_normal();
    auto rootIterator = normalizedRoot.begin();
    auto candidateIterator = normalizedCandidate.begin();
    for (; rootIterator != normalizedRoot.end(); ++rootIterator, ++candidateIterator) {
        if (candidateIterator == normalizedCandidate.end() || *rootIterator != *candidateIterator) {
            return false;
        }
    }
    return true;
}

static bool OMIsPadFile(lt::file_storage const& files, lt::file_index_t index) {
    return (files.file_flags(index) & lt::file_storage::flag_pad_file) != lt::file_flags_t{};
}

@interface OMLocalTorrentEngine () {
    dispatch_queue_t _workQueue;
    std::atomic_bool _cancelled;
}
@property (nonatomic, readonly) NSURL *cacheDirectory;
@property (nonatomic, readonly) int64_t maximumDownloadBytes;
@property (nonatomic, readonly) int64_t minimumFreeBytes;
@property (nonatomic, readonly) int64_t downloadLimitBytesPerSecond;
@property (nonatomic, readonly) int64_t uploadLimitBytesPerSecond;
@end

@implementation OMLocalTorrentEngine

+ (BOOL)isAvailable { return YES; }

- (instancetype)initWithCacheDirectory:(NSURL *)cacheDirectory
                   maximumDownloadBytes:(int64_t)maximumDownloadBytes
                       minimumFreeBytes:(int64_t)minimumFreeBytes
             downloadLimitBytesPerSecond:(int64_t)downloadLimitBytesPerSecond
               uploadLimitBytesPerSecond:(int64_t)uploadLimitBytesPerSecond {
    self = [super init];
    if (!self) return nil;
    _cacheDirectory = [cacheDirectory copy];
    _maximumDownloadBytes = maximumDownloadBytes;
    _minimumFreeBytes = minimumFreeBytes;
    _downloadLimitBytesPerSecond = downloadLimitBytesPerSecond;
    _uploadLimitBytesPerSecond = uploadLimitBytesPerSecond;
    _workQueue = dispatch_queue_create("PrimeDeca.Omnia.LocalTorrent", DISPATCH_QUEUE_SERIAL);
    _cancelled.store(false);
    return self;
}

- (void)downloadMagnetURL:(NSURL *)magnetURL
                 fileIndex:(NSNumber *)fileIndex
                  progress:(OMLocalTorrentProgressHandler)progress
                completion:(OMLocalTorrentCompletionHandler)completion {
    if (!self.cacheDirectory.isFileURL || ![magnetURL.scheme.lowercaseString isEqualToString:@"magnet"] ||
        self.maximumDownloadBytes <= 0 || self.minimumFreeBytes < 0 ||
        self.downloadLimitBytesPerSecond < 0 || self.uploadLimitBytesPerSecond < 0 ||
        self.downloadLimitBytesPerSecond > INT_MAX || self.uploadLimitBytesPerSecond > INT_MAX) {
        completion(nil, OMTorrentError(OMLocalTorrentErrorInvalidInput, @"The local torrent request is invalid."));
        return;
    }

    _cancelled.store(false);
    NSURL *cacheDirectory = self.cacheDirectory;
    int64_t maximumDownloadBytes = self.maximumDownloadBytes;
    int64_t minimumFreeBytes = self.minimumFreeBytes;
    int64_t downloadLimitBytesPerSecond = self.downloadLimitBytesPerSecond;
    int64_t uploadLimitBytesPerSecond = self.uploadLimitBytesPerSecond;
    dispatch_async(_workQueue, ^{
        @autoreleasepool {
            [self runMagnetURL:magnetURL
                     fileIndex:fileIndex
                cacheDirectory:cacheDirectory
          maximumDownloadBytes:maximumDownloadBytes
              minimumFreeBytes:minimumFreeBytes
    downloadLimitBytesPerSecond:downloadLimitBytesPerSecond
      uploadLimitBytesPerSecond:uploadLimitBytesPerSecond
                       progress:progress
                     completion:completion];
        }
    });
}

- (void)cancel { _cancelled.store(true); }

- (void)runMagnetURL:(NSURL *)magnetURL
            fileIndex:(NSNumber *)requestedFileIndex
       cacheDirectory:(NSURL *)cacheDirectory
 maximumDownloadBytes:(int64_t)maximumDownloadBytes
     minimumFreeBytes:(int64_t)minimumFreeBytes
downloadLimitBytesPerSecond:(int64_t)downloadLimitBytesPerSecond
  uploadLimitBytesPerSecond:(int64_t)uploadLimitBytesPerSecond
              progress:(OMLocalTorrentProgressHandler)progressHandler
            completion:(OMLocalTorrentCompletionHandler)completion {
    auto finish = ^(NSURL *fileURL, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(fileURL, error); });
    };

    try {
        NSString *cachePath = cacheDirectory.path;
        if (cachePath.length == 0) {
            finish(nil, OMTorrentError(OMLocalTorrentErrorInvalidInput, @"The torrent cache path is invalid."));
            return;
        }
        NSError *directoryError = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtURL:cacheDirectory
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&directoryError]) {
            finish(nil, OMTorrentError(OMLocalTorrentErrorNativeFailure, @"Omnia could not prepare local torrent storage."));
            return;
        }

        lt::settings_pack settings;
        settings.set_int(lt::settings_pack::alert_mask,
            lt::alert_category::error | lt::alert_category::storage |
            lt::alert_category::status);
        settings.set_bool(lt::settings_pack::enable_lsd, false);
        settings.set_bool(lt::settings_pack::enable_upnp, false);
        settings.set_bool(lt::settings_pack::enable_natpmp, false);
        settings.set_bool(lt::settings_pack::enable_incoming_tcp, false);
        settings.set_bool(lt::settings_pack::enable_incoming_utp, false);
        settings.set_bool(lt::settings_pack::anonymous_mode, true);
        settings.set_int(lt::settings_pack::out_enc_policy, lt::settings_pack::pe_enabled);
        settings.set_int(lt::settings_pack::in_enc_policy, lt::settings_pack::pe_enabled);
        settings.set_str(lt::settings_pack::user_agent, "Omnia/1 local playback");
        settings.set_int(
            lt::settings_pack::download_rate_limit,
            static_cast<int>(downloadLimitBytesPerSecond)
        );
        settings.set_int(
            lt::settings_pack::upload_rate_limit,
            static_cast<int>(uploadLimitBytesPerSecond)
        );

        lt::session session(settings);
        lt::error_code parseError;
        lt::add_torrent_params parameters = lt::parse_magnet_uri(
            magnetURL.absoluteString.UTF8String, parseError);
        if (parseError) {
            finish(nil, OMTorrentError(OMLocalTorrentErrorInvalidInput, @"The magnet descriptor is invalid."));
            return;
        }
        parameters.save_path = cachePath.fileSystemRepresentation;
        lt::torrent_handle handle = session.add_torrent(std::move(parameters), parseError);
        if (parseError) {
            finish(nil, OMTorrentError(OMLocalTorrentErrorNativeFailure, @"The local torrent could not be added."));
            return;
        }

        auto metadataDeadline = std::chrono::steady_clock::now() + std::chrono::minutes(2);
        bool configuredFile = false;
        lt::file_index_t selectedIndex{0};
        std::int64_t selectedSize = 0;
        fs::path selectedPath;

        while (!_cancelled.load()) {
            if (!configuredFile && handle.status().has_metadata) {
                std::shared_ptr<lt::torrent_info const> info = handle.torrent_file();
                if (!info) continue;
                lt::file_storage const& files = info->files();
                if (files.num_files() <= 0) {
                    finish(nil, OMTorrentError(OMLocalTorrentErrorInvalidFile, @"The torrent contains no files."));
                    return;
                }

                if (requestedFileIndex != nil) {
                    NSInteger requested = requestedFileIndex.integerValue;
                    if (requested < 0 || requested >= files.num_files()) {
                        finish(nil, OMTorrentError(OMLocalTorrentErrorInvalidFile, @"The requested torrent file does not exist."));
                        return;
                    }
                    selectedIndex = lt::file_index_t(static_cast<int>(requested));
                } else {
                    std::int64_t largestSize = -1;
                    for (lt::file_index_t index : files.file_range()) {
                        if (OMIsPadFile(files, index)) continue;
                        std::int64_t size = files.file_size(index);
                        if (size > largestSize) {
                            largestSize = size;
                            selectedIndex = index;
                        }
                    }
                }

                selectedSize = files.file_size(selectedIndex);
                if (selectedSize < 0 || selectedSize > maximumDownloadBytes ||
                    OMIsPadFile(files, selectedIndex)) {
                    finish(nil, OMTorrentError(OMLocalTorrentErrorItemTooLarge, @"The selected torrent file exceeds the local item limit."));
                    return;
                }

                NSNumber *availableCapacity = nil;
                [cacheDirectory getResourceValue:&availableCapacity
                                           forKey:NSURLVolumeAvailableCapacityForImportantUsageKey
                                             error:nil];
                if (availableCapacity == nil ||
                    availableCapacity.longLongValue < selectedSize + minimumFreeBytes) {
                    finish(nil, OMTorrentError(OMLocalTorrentErrorItemTooLarge, @"There is not enough local storage for this torrent and the required reserve."));
                    return;
                }

                fs::path root(cachePath.fileSystemRepresentation);
                selectedPath = fs::path(files.file_path(selectedIndex, root.string()));
                if (!OMPathIsConfined(root, selectedPath)) {
                    finish(nil, OMTorrentError(OMLocalTorrentErrorInvalidFile, @"The torrent contains an unsafe file path."));
                    return;
                }

                std::vector<lt::download_priority_t> priorities(
                    static_cast<std::size_t>(files.num_files()), lt::dont_download);
                priorities[static_cast<std::size_t>(static_cast<int>(selectedIndex))] = lt::default_priority;
                handle.prioritize_files(priorities);
                handle.set_flags(lt::torrent_flags::sequential_download);
                configuredFile = true;
            }

            if (!configuredFile && std::chrono::steady_clock::now() >= metadataDeadline) {
                finish(nil, OMTorrentError(OMLocalTorrentErrorMetadataTimeout, @"Torrent metadata did not arrive before the local timeout."));
                return;
            }

            if (configuredFile) {
                std::vector<std::int64_t> fileProgress = handle.file_progress();
                std::size_t offset = static_cast<std::size_t>(static_cast<int>(selectedIndex));
                std::int64_t downloaded = offset < fileProgress.size() ? fileProgress[offset] : 0;
                double fraction = selectedSize > 0
                    ? std::min(std::max(double(downloaded) / double(selectedSize), 0.0), 1.0)
                    : 1.0;
                if (progressHandler) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        progressHandler(fraction, downloaded, selectedSize);
                    });
                }
                if (downloaded >= selectedSize) {
                    handle.pause();
                    session.remove_torrent(handle);
                    NSURL *fileURL = [NSURL fileURLWithPath:
                        [NSString stringWithUTF8String:selectedPath.string().c_str()]];
                    NSNumber *isRegular = nil;
                    NSNumber *isSymbolicLink = nil;
                    [fileURL getResourceValue:&isRegular forKey:NSURLIsRegularFileKey error:nil];
                    [fileURL getResourceValue:&isSymbolicLink forKey:NSURLIsSymbolicLinkKey error:nil];
                    if (!isRegular.boolValue || isSymbolicLink.boolValue) {
                        finish(nil, OMTorrentError(OMLocalTorrentErrorInvalidFile, @"The completed torrent output is not a regular local file."));
                        return;
                    }
                    finish(fileURL, nil);
                    return;
                }
            }

            std::vector<lt::alert *> alerts;
            session.pop_alerts(&alerts);
            for (lt::alert const *alert : alerts) {
                if (auto torrentError = lt::alert_cast<lt::torrent_error_alert>(alert)) {
                    finish(nil, OMTorrentError(OMLocalTorrentErrorNativeFailure, @"The local torrent transfer failed."));
                    return;
                }
                if (auto fileError = lt::alert_cast<lt::file_error_alert>(alert)) {
                    finish(nil, OMTorrentError(OMLocalTorrentErrorNativeFailure, @"The local torrent file could not be written."));
                    return;
                }
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(250));
        }

        handle.pause();
        session.remove_torrent(handle, lt::session::delete_partfile);
        finish(nil, OMTorrentError(OMLocalTorrentErrorCancelled, @"Local torrent playback was cancelled."));
    } catch (std::exception const&) {
        finish(nil, OMTorrentError(OMLocalTorrentErrorNativeFailure, @"The local torrent engine failed."));
    }
}

@end

#else

@implementation OMLocalTorrentEngine

+ (BOOL)isAvailable { return NO; }

- (instancetype)initWithCacheDirectory:(NSURL *)cacheDirectory
                   maximumDownloadBytes:(int64_t)maximumDownloadBytes
                       minimumFreeBytes:(int64_t)minimumFreeBytes
             downloadLimitBytesPerSecond:(int64_t)downloadLimitBytesPerSecond
               uploadLimitBytesPerSecond:(int64_t)uploadLimitBytesPerSecond {
    return [super init];
}

- (void)downloadMagnetURL:(NSURL *)magnetURL
                 fileIndex:(NSNumber *)fileIndex
                  progress:(OMLocalTorrentProgressHandler)progress
                completion:(OMLocalTorrentCompletionHandler)completion {
    completion(nil, OMTorrentError(OMLocalTorrentErrorUnavailable, @"The reviewed local torrent engine is not included in this build."));
}

- (void)cancel {}

@end
#endif
#endif
