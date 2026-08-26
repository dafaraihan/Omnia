#import "LocalTorrentEngine.h"

#if TARGET_OS_OSX
#import <atomic>
#import <algorithm>
#import <cctype>
#import <climits>
#include <filesystem>
#include <vector>

namespace fs = std::filesystem;

struct OMMediaPath {
    fs::path relativePath;
    bool isSymbolicLink;
};

static std::string OMLowerASCII(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
    });
    return value;
}

static std::vector<std::string> OMPathComponents(fs::path const& path) {
    std::vector<std::string> components;
    for (auto const& component : path) components.push_back(component.string());
    return components;
}

static bool OMIsSafeRelativePath(fs::path const& path) {
    if (path.empty() || path.is_absolute()) return false;
    for (auto const& component : path) {
        auto value = component.string();
        if (value.empty() || value == "." || value == "..") return false;
    }
    return true;
}

static bool OMComponentsHaveCaseInsensitivePrefix(
    std::vector<std::string> const& components,
    std::vector<std::string> const& prefix
) {
    if (components.size() < prefix.size()) return false;
    for (std::size_t offset = 0; offset < prefix.size(); ++offset) {
        if (OMLowerASCII(components[offset]) != OMLowerASCII(prefix[offset])) return false;
    }
    return true;
}

static bool OMDetectBluRayRoot(
    std::vector<OMMediaPath> const& mediaPaths,
    fs::path& detectedRoot
) {
    bool foundMarker = false;
    std::vector<std::string> expectedPrefix;
    for (OMMediaPath const& mediaPath : mediaPaths) {
        if (mediaPath.isSymbolicLink) return false;
        fs::path const& relative = mediaPath.relativePath;
        if (!OMIsSafeRelativePath(relative)) return false;
        auto components = OMPathComponents(relative);
        if (components.size() < 2 ||
            OMLowerASCII(components.back()) != "index.bdmv" ||
            OMLowerASCII(components[components.size() - 2]) != "bdmv") {
            continue;
        }
        std::vector<std::string> rootComponents(
            components.begin(), components.end() - 2);
        if (foundMarker) return false;
        foundMarker = true;
        expectedPrefix = rootComponents;
        detectedRoot.clear();
        for (auto const& component : rootComponents) detectedRoot /= component;
    }
    if (!foundMarker) return false;

    auto bdmvPrefix = expectedPrefix;
    bdmvPrefix.push_back("BDMV");
    for (OMMediaPath const& mediaPath : mediaPaths) {
        if (!OMComponentsHaveCaseInsensitivePrefix(
                OMPathComponents(mediaPath.relativePath),
                bdmvPrefix
            )) {
            return false;
        }
    }
    return true;
}

static int64_t OMRemainingDownloadBytes(
    int64_t selectedBytes,
    NSURL *rootURL,
    NSArray<NSURL *> *selectedFileURLs
) {
    if (selectedBytes <= 0 || !rootURL.isFileURL) return selectedBytes;
    NSString *rootPath = rootURL.standardizedURL.path;
    if (rootPath.length == 0) return selectedBytes;
    int64_t existingBytes = 0;
    for (NSURL *fileURL in selectedFileURLs) {
        NSString *path = fileURL.standardizedURL.path;
        if (![path hasPrefix:[rootPath stringByAppendingString:@"/"]]) continue;
        NSNumber *isRegular = nil;
        NSNumber *isSymbolicLink = nil;
        NSNumber *allocatedSize = nil;
        [fileURL getResourceValue:&isRegular forKey:NSURLIsRegularFileKey error:nil];
        [fileURL getResourceValue:&isSymbolicLink forKey:NSURLIsSymbolicLinkKey error:nil];
        [fileURL getResourceValue:&allocatedSize forKey:NSURLFileAllocatedSizeKey error:nil];
        if (!isRegular.boolValue || isSymbolicLink.boolValue ||
            allocatedSize == nil || allocatedSize.longLongValue < 0) {
            continue;
        }
        int64_t fileBytes = allocatedSize.longLongValue;
        if (fileBytes >= selectedBytes - existingBytes) return 0;
        existingBytes += fileBytes;
    }
    return selectedBytes - existingBytes;
}

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
#include <memory>
#include <thread>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_info.hpp>

namespace lt = libtorrent;

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

static bool OMIsSymbolicLink(lt::file_storage const& files, lt::file_index_t index) {
    return (files.file_flags(index) & lt::file_storage::flag_symlink) != lt::file_flags_t{};
}

static bool OMDetectBluRayRoot(lt::file_storage const& files, fs::path& detectedRoot) {
    std::vector<OMMediaPath> mediaPaths;
    for (lt::file_index_t index : files.file_range()) {
        if (!OMIsPadFile(files, index)) {
            mediaPaths.push_back({
                fs::path(files.file_path(index)),
                OMIsSymbolicLink(files, index),
            });
        }
    }
    return !mediaPaths.empty() && OMDetectBluRayRoot(mediaPaths, detectedRoot);
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
@property (nonatomic, readwrite) OMLocalTorrentMediaKind completedMediaKind;
@property (nonatomic, readwrite) int64_t completedBytes;
@end

@implementation OMLocalTorrentEngine

+ (BOOL)isAvailable { return YES; }

+ (BOOL)isSupportedBluRayLayoutForTesting:(NSArray<NSString *> *)relativePaths
                                    sizes:(NSArray<NSNumber *> *)sizes
                    symbolicLinkIndices:(NSArray<NSNumber *> *)symbolicLinkIndices {
    if (relativePaths.count == 0 || relativePaths.count != sizes.count ||
        relativePaths.count > 10000) {
        return NO;
    }
    NSSet<NSNumber *> *links = [NSSet setWithArray:symbolicLinkIndices];
    std::vector<OMMediaPath> mediaPaths;
    for (NSUInteger offset = 0; offset < relativePaths.count; ++offset) {
        NSString *path = relativePaths[offset];
        int64_t size = sizes[offset].longLongValue;
        if (path.length == 0 || size < 0) return NO;
        mediaPaths.push_back({
            fs::path(path.UTF8String),
            [links containsObject:@(offset)] == YES,
        });
    }
    fs::path root;
    return OMDetectBluRayRoot(mediaPaths, root);
}

+ (int64_t)remainingDownloadBytesForTesting:(int64_t)selectedBytes
                                    rootURL:(NSURL *)rootURL
                           selectedFileURLs:(NSArray<NSURL *> *)selectedFileURLs {
    return OMRemainingDownloadBytes(selectedBytes, rootURL, selectedFileURLs);
}

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
    _completedMediaKind = OMLocalTorrentMediaKindFile;
    _completedBytes = 0;
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
    self.completedMediaKind = OMLocalTorrentMediaKindFile;
    self.completedBytes = 0;
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
        bool selectedBluRayDirectory = false;
        std::vector<lt::file_index_t> selectedIndices;
        std::int64_t selectedSize = 0;
        fs::path selectedPath;

        while (!_cancelled.load()) {
            if (!configuredFile && handle.status().has_metadata) {
                std::shared_ptr<lt::torrent_info const> info = handle.torrent_file();
                if (!info) continue;
                #if LIBTORRENT_VERSION_NUM >= 20100
                lt::file_storage const& files = info->layout();
                #else
                lt::file_storage const& files = info->files();
                #endif
                if (files.num_files() <= 0 || files.num_files() > 10000) {
                    finish(nil, OMTorrentError(OMLocalTorrentErrorInvalidFile, @"The torrent contains no files."));
                    return;
                }
                for (lt::file_index_t index : files.file_range()) {
                    if (!OMIsPadFile(files, index) && OMIsSymbolicLink(files, index)) {
                        finish(nil, OMTorrentError(OMLocalTorrentErrorInvalidFile, @"The torrent contains an unsafe symbolic link."));
                        return;
                    }
                }

                fs::path bluRayRoot;
                selectedBluRayDirectory = OMDetectBluRayRoot(files, bluRayRoot);
                if (selectedBluRayDirectory) {
                    for (lt::file_index_t index : files.file_range()) {
                        if (OMIsPadFile(files, index)) continue;
                        std::int64_t size = files.file_size(index);
                        if (size < 0 || selectedSize > maximumDownloadBytes - size) {
                            finish(nil, OMTorrentError(OMLocalTorrentErrorItemTooLarge, @"The Blu-ray directory exceeds the local item limit."));
                            return;
                        }
                        selectedSize += size;
                        selectedIndices.push_back(index);
                    }
                    fs::path root(cachePath.fileSystemRepresentation);
                    selectedPath = (root / bluRayRoot).lexically_normal();
                } else {
                    lt::file_index_t selectedIndex{0};
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
                    selectedIndices.push_back(selectedIndex);
                    fs::path root(cachePath.fileSystemRepresentation);
                    selectedPath = fs::path(files.file_path(selectedIndex, root.string()));
                }

                if (selectedIndices.empty() || selectedSize <= 0) {
                    finish(nil, OMTorrentError(OMLocalTorrentErrorInvalidFile, @"The torrent contains no downloadable media."));
                    return;
                }
                fs::path root(cachePath.fileSystemRepresentation);
                if (!OMPathIsConfined(root, selectedPath)) {
                    finish(nil, OMTorrentError(OMLocalTorrentErrorInvalidFile, @"The torrent contains an unsafe file path."));
                    return;
                }
                for (lt::file_index_t index : selectedIndices) {
                    fs::path filePath(files.file_path(index, root.string()));
                    if (!OMPathIsConfined(root, filePath)) {
                        finish(nil, OMTorrentError(OMLocalTorrentErrorInvalidFile, @"The torrent contains an unsafe file path."));
                        return;
                    }
                }

                NSMutableArray<NSURL *> *selectedFileURLs = [NSMutableArray array];
                for (lt::file_index_t index : selectedIndices) {
                    fs::path path(files.file_path(index, root.string()));
                    [selectedFileURLs addObject:[NSURL fileURLWithPath:
                        [NSString stringWithUTF8String:path.string().c_str()]]];
                }
                std::int64_t remainingBytes = OMRemainingDownloadBytes(
                    selectedSize,
                    cacheDirectory,
                    selectedFileURLs
                );
                NSNumber *availableCapacity = nil;
                [cacheDirectory getResourceValue:&availableCapacity
                                           forKey:NSURLVolumeAvailableCapacityForImportantUsageKey
                                             error:nil];
                if (availableCapacity == nil ||
                    availableCapacity.longLongValue < minimumFreeBytes ||
                    remainingBytes > availableCapacity.longLongValue - minimumFreeBytes) {
                    finish(nil, OMTorrentError(OMLocalTorrentErrorItemTooLarge, @"There is not enough local storage for this torrent and the required reserve."));
                    return;
                }

                std::vector<lt::download_priority_t> priorities(
                    static_cast<std::size_t>(files.num_files()), lt::dont_download);
                for (lt::file_index_t index : selectedIndices) {
                    priorities[static_cast<std::size_t>(static_cast<int>(index))] = lt::default_priority;
                }
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
                std::int64_t downloaded = 0;
                for (lt::file_index_t index : selectedIndices) {
                    std::size_t offset = static_cast<std::size_t>(static_cast<int>(index));
                    if (offset >= fileProgress.size()) continue;
                    std::int64_t fileBytes = std::max(fileProgress[offset], std::int64_t{0});
                    if (fileBytes >= selectedSize - downloaded) {
                        downloaded = selectedSize;
                        break;
                    }
                    downloaded += fileBytes;
                }
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
                    NSNumber *isDirectory = nil;
                    NSNumber *isRegular = nil;
                    NSNumber *isSymbolicLink = nil;
                    [fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
                    [fileURL getResourceValue:&isRegular forKey:NSURLIsRegularFileKey error:nil];
                    [fileURL getResourceValue:&isSymbolicLink forKey:NSURLIsSymbolicLinkKey error:nil];
                    BOOL validType = selectedBluRayDirectory
                        ? isDirectory.boolValue
                        : isRegular.boolValue;
                    if (!validType || isSymbolicLink.boolValue) {
                        finish(nil, OMTorrentError(OMLocalTorrentErrorInvalidFile, @"The completed torrent output is not a regular local file."));
                        return;
                    }
                    self.completedMediaKind = selectedBluRayDirectory
                        ? OMLocalTorrentMediaKindBluRayDirectory
                        : OMLocalTorrentMediaKindFile;
                    self.completedBytes = selectedSize;
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

+ (BOOL)isSupportedBluRayLayoutForTesting:(NSArray<NSString *> *)relativePaths
                                    sizes:(NSArray<NSNumber *> *)sizes
                    symbolicLinkIndices:(NSArray<NSNumber *> *)symbolicLinkIndices {
    if (relativePaths.count == 0 || relativePaths.count != sizes.count ||
        relativePaths.count > 10000) {
        return NO;
    }
    NSSet<NSNumber *> *links = [NSSet setWithArray:symbolicLinkIndices];
    std::vector<OMMediaPath> mediaPaths;
    for (NSUInteger offset = 0; offset < relativePaths.count; ++offset) {
        NSString *path = relativePaths[offset];
        int64_t size = sizes[offset].longLongValue;
        if (path.length == 0 || size < 0) return NO;
        mediaPaths.push_back({
            fs::path(path.UTF8String),
            [links containsObject:@(offset)] == YES,
        });
    }
    fs::path root;
    return OMDetectBluRayRoot(mediaPaths, root);
}

+ (int64_t)remainingDownloadBytesForTesting:(int64_t)selectedBytes
                                    rootURL:(NSURL *)rootURL
                           selectedFileURLs:(NSArray<NSURL *> *)selectedFileURLs {
    return OMRemainingDownloadBytes(selectedBytes, rootURL, selectedFileURLs);
}

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
