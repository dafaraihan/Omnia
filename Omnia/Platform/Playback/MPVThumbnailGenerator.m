#import "MPVThumbnailGenerator.h"

#if TARGET_OS_OSX

#import <mpv/client.h>
#import <math.h>

static NSString *const OMMpvThumbnailErrorDomain = @"OMMpvThumbnailErrorDomain";
static void *OMMpvThumbnailQueueKey = &OMMpvThumbnailQueueKey;

typedef NS_ENUM(NSInteger, OMMpvThumbnailPhase) {
    OMMpvThumbnailPhaseIdle,
    OMMpvThumbnailPhaseWaitingForFile,
    OMMpvThumbnailPhaseSeeking,
    OMMpvThumbnailPhaseScreenshot,
};

@interface OMMpvThumbnailGenerator () {
    dispatch_queue_t _queue;
    mpv_handle *_mpv;
    NSURL *_URL;
    NSDictionary<NSString *, NSString *> *_requestHeaders;
    BOOL _stopped;
    BOOL _fileLoaded;
    BOOL _seekable;
    uint64_t _generation;
    uint64_t _pendingGeneration;
    double _requestedSeconds;
    NSSize _maximumSize;
    OMMpvThumbnailCompletion _completion;
    OMMpvThumbnailPhase _phase;
    BOOL _didReceiveSeekReply;
    BOOL _didRestartAfterSeek;
}
- (void)initializeCore;
- (void)handleWakeup;
- (void)drainEvents;
- (void)beginSeekIfPossible;
- (void)requestScreenshotIfReady;
- (void)cancelPendingRequestOnQueue;
- (nullable NSImage *)imageFromScreenshotNode:(mpv_node *)node;
- (NSError *)errorWithDescription:(NSString *)description;
- (void)finishWithImage:(nullable NSImage *)image error:(nullable NSError *)error;
+ (NSDictionary<NSString *, NSString *> *)safeRequestHeaders:(NSDictionary<NSString *, NSString *> *)headers;
@end

static void OMMpvThumbnailWakeup(void *context) {
    OMMpvThumbnailGenerator *generator = (__bridge OMMpvThumbnailGenerator *)context;
    [generator handleWakeup];
}

@implementation OMMpvThumbnailGenerator

- (instancetype)initWithURL:(NSURL *)URL
             requestHeaders:(NSDictionary<NSString *, NSString *> *)requestHeaders {
    self = [super init];
    if (!self) return nil;

    _URL = [URL copy];
    _requestHeaders = [[self class] safeRequestHeaders:requestHeaders];
    dispatch_queue_attr_t attributes = dispatch_queue_attr_make_with_qos_class(
        DISPATCH_QUEUE_SERIAL,
        QOS_CLASS_UTILITY,
        0
    );
    _queue = dispatch_queue_create("app.omnia.timeline-thumbnail", attributes);
    dispatch_queue_set_specific(_queue, OMMpvThumbnailQueueKey, OMMpvThumbnailQueueKey, NULL);
    dispatch_sync(_queue, ^{
        [self initializeCore];
    });
    return self;
}

- (void)dealloc {
    [self stop];
}

+ (NSDictionary<NSString *, NSString *> *)safeRequestHeaders:(NSDictionary<NSString *, NSString *> *)headers {
    NSSet<NSString *> *forbidden = [NSSet setWithArray:@[
        @"host", @"connection", @"content-length", @"range"
    ]];
    NSMutableDictionary<NSString *, NSString *> *safe = [NSMutableDictionary dictionary];
    NSCharacterSet *newlines = NSCharacterSet.newlineCharacterSet;
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        if (![name isKindOfClass:NSString.class] || ![value isKindOfClass:NSString.class]) return;
        NSString *trimmedName = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *trimmedValue = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmedName.length == 0
            || [trimmedName lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 256
            || [trimmedValue lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 8192
            || [forbidden containsObject:trimmedName.lowercaseString]
            || [trimmedName rangeOfCharacterFromSet:newlines].location != NSNotFound
            || [trimmedValue rangeOfCharacterFromSet:newlines].location != NSNotFound) return;
        safe[trimmedName] = trimmedValue;
    }];
    return [safe copy];
}

- (void)initializeCore {
    if (_stopped) return;
    _mpv = mpv_create();
    if (!_mpv) return;

    mpv_set_option_string(_mpv, "config", "no");
    mpv_set_option_string(_mpv, "terminal", "no");
    mpv_set_option_string(_mpv, "load-scripts", "no");
    mpv_set_option_string(_mpv, "load-console", "no");
    mpv_set_option_string(_mpv, "load-stats-overlay", "no");
    mpv_set_option_string(_mpv, "load-auto-profiles", "no");
    mpv_set_option_string(_mpv, "load-select", "no");
    mpv_set_option_string(_mpv, "load-positioning", "no");
    mpv_set_option_string(_mpv, "load-commands", "no");
    mpv_set_option_string(_mpv, "load-context-menu", "no");
    mpv_set_option_string(_mpv, "osc", "no");
    mpv_set_option_string(_mpv, "ytdl", "no");
    mpv_set_option_string(_mpv, "audio", "no");
    mpv_set_option_string(_mpv, "ao", "null");
    mpv_set_option_string(_mpv, "vo", "null");
    mpv_set_option_string(_mpv, "pause", "yes");
    mpv_set_option_string(_mpv, "keep-open", "yes");
    mpv_set_option_string(_mpv, "hwdec", "auto-safe");
    mpv_set_option_string(_mpv, "hr-seek", "yes");
    // Previews jump straight to one frame, so reading far ahead is wasted.
    // mpv's default stream cache would keep up to 200 MB per decoder.
    mpv_set_option_string(_mpv, "demuxer-max-bytes", "32MiB");
    mpv_set_option_string(_mpv, "demuxer-max-back-bytes", "0");
    mpv_set_option_string(_mpv, "demuxer-readahead-secs", "1");

    if (mpv_initialize(_mpv) < 0) {
        mpv_terminate_destroy(_mpv);
        _mpv = NULL;
        return;
    }
    if (_requestHeaders.count > 0) {
        NSMutableArray<NSString *> *fields = [NSMutableArray arrayWithCapacity:_requestHeaders.count];
        [_requestHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
            [fields addObject:[NSString stringWithFormat:@"%@: %@", name, value]];
        }];
        NSString *headerFields = [fields componentsJoinedByString:@"\n"];
        mpv_set_property_string(_mpv, "http-header-fields", headerFields.UTF8String);
    }

    mpv_set_wakeup_callback(_mpv, OMMpvThumbnailWakeup, (__bridge void *)self);
    const char *loadCommand[] = { "loadfile", _URL.absoluteString.UTF8String, "replace", NULL };
    if (mpv_command(_mpv, loadCommand) < 0) {
        mpv_set_wakeup_callback(_mpv, NULL, NULL);
        mpv_terminate_destroy(_mpv);
        _mpv = NULL;
    }
}

- (void)handleWakeup {
    dispatch_async(_queue, ^{
        [self drainEvents];
    });
}

- (uint64_t)requestFrameAt:(double)seconds
               maximumSize:(NSSize)maximumSize
                completion:(OMMpvThumbnailCompletion)completion {
    __block uint64_t requestID = 0;
    dispatch_sync(_queue, ^{
        if (self->_stopped || !self->_mpv || !isfinite(seconds) || seconds < 0
            || !isfinite(maximumSize.width) || !isfinite(maximumSize.height)
            || maximumSize.width <= 0 || maximumSize.height <= 0) {
            NSError *error = [self errorWithDescription:@"Timeline preview is unavailable for this source."];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
            return;
        }

        [self cancelPendingRequestOnQueue];
        self->_generation += 1;
        if (self->_generation == 0) self->_generation = 1;
        self->_pendingGeneration = self->_generation;
        requestID = self->_pendingGeneration;
        self->_requestedSeconds = seconds;
        self->_maximumSize = NSMakeSize(MIN(maximumSize.width, 320), MIN(maximumSize.height, 180));
        self->_completion = [completion copy];
        self->_phase = self->_fileLoaded ? OMMpvThumbnailPhaseIdle : OMMpvThumbnailPhaseWaitingForFile;
        self->_didReceiveSeekReply = NO;
        self->_didRestartAfterSeek = NO;
        [self beginSeekIfPossible];
    });
    return requestID;
}

- (void)cancelPendingRequest {
    if (dispatch_get_specific(OMMpvThumbnailQueueKey)) {
        [self cancelPendingRequestOnQueue];
    } else {
        dispatch_sync(_queue, ^{
            [self cancelPendingRequestOnQueue];
        });
    }
}

- (void)cancelPendingRequestOnQueue {
    if (!_completion) return;
    if (_mpv && _pendingGeneration != 0) {
        mpv_abort_async_command(_mpv, _pendingGeneration);
    }
    NSError *error = [self errorWithDescription:@"Timeline preview was cancelled."];
    [self finishWithImage:nil error:error];
}

- (void)beginSeekIfPossible {
    if (!_completion || !_fileLoaded) return;
    if (!_seekable) {
        [self finishWithImage:nil error:[self errorWithDescription:@"Timeline preview is unavailable for this source."]];
        return;
    }
    NSString *seconds = [NSString stringWithFormat:@"%.3f", _requestedSeconds];
    const char *seek[] = { "seek", seconds.UTF8String, "absolute+exact", NULL };
    _phase = OMMpvThumbnailPhaseSeeking;
    int status = mpv_command_async(_mpv, _pendingGeneration, seek);
    if (status < 0) {
        [self finishWithImage:nil error:[self errorWithDescription:@"Timeline preview is unavailable for this source."]];
    }
}

- (void)requestScreenshotIfReady {
    if (_phase != OMMpvThumbnailPhaseSeeking
        || !_didReceiveSeekReply
        || !_didRestartAfterSeek
        || !_completion) return;

    char commandName[] = "screenshot-raw";
    char flags[] = "video";
    char format[] = "bgra";
    mpv_node values[3] = {
        { .u.string = commandName, .format = MPV_FORMAT_STRING },
        { .u.string = flags, .format = MPV_FORMAT_STRING },
        { .u.string = format, .format = MPV_FORMAT_STRING },
    };
    mpv_node_list list = { .num = 3, .values = values, .keys = NULL };
    mpv_node arguments = { .u.list = &list, .format = MPV_FORMAT_NODE_ARRAY };
    _phase = OMMpvThumbnailPhaseScreenshot;
    int status = mpv_command_node_async(_mpv, _pendingGeneration, &arguments);
    if (status < 0) {
        [self finishWithImage:nil error:[self errorWithDescription:@"The preview frame could not be decoded."]];
    }
}

- (void)drainEvents {
    if (!_mpv || _stopped) return;
    while (_mpv) {
        mpv_event *event = mpv_wait_event(_mpv, 0);
        if (!event || event->event_id == MPV_EVENT_NONE) break;

        switch (event->event_id) {
        case MPV_EVENT_FILE_LOADED: {
            _fileLoaded = YES;
            int seekable = 0;
            _seekable = mpv_get_property(_mpv, "seekable", MPV_FORMAT_FLAG, &seekable) >= 0
                && seekable != 0;
            [self beginSeekIfPossible];
            break;
        }
        case MPV_EVENT_PLAYBACK_RESTART:
            if (_phase == OMMpvThumbnailPhaseSeeking) {
                _didRestartAfterSeek = YES;
                [self requestScreenshotIfReady];
            }
            break;
        case MPV_EVENT_COMMAND_REPLY:
            if (event->reply_userdata != _pendingGeneration || !_completion) break;
            if (_phase == OMMpvThumbnailPhaseSeeking) {
                if (event->error < 0) {
                    [self finishWithImage:nil error:[self errorWithDescription:@"Timeline preview is unavailable for this source."]];
                } else {
                    _didReceiveSeekReply = YES;
                    [self requestScreenshotIfReady];
                }
            } else if (_phase == OMMpvThumbnailPhaseScreenshot) {
                if (event->error < 0) {
                    [self finishWithImage:nil error:[self errorWithDescription:@"The preview frame could not be decoded."]];
                } else {
                    mpv_event_command *reply = event->data;
                    NSImage *image = reply ? [self imageFromScreenshotNode:&reply->result] : nil;
                    NSError *error = image
                        ? nil
                        : [self errorWithDescription:@"The preview frame could not be decoded."];
                    [self finishWithImage:image error:error];
                }
            }
            break;
        case MPV_EVENT_END_FILE:
            if (_completion) {
                [self finishWithImage:nil error:[self errorWithDescription:@"Timeline preview is unavailable for this source."]];
            }
            break;
        default:
            break;
        }
    }
}

- (NSImage *)imageFromScreenshotNode:(mpv_node *)node {
    if (!node || node->format != MPV_FORMAT_NODE_MAP || !node->u.list) return nil;
    mpv_node_list *map = node->u.list;
    mpv_node *widthNode = NULL;
    mpv_node *heightNode = NULL;
    mpv_node *strideNode = NULL;
    mpv_node *formatNode = NULL;
    mpv_node *dataNode = NULL;
    for (int index = 0; index < map->num; index += 1) {
        const char *key = map->keys[index];
        if (!key) continue;
        if (strcmp(key, "w") == 0) widthNode = &map->values[index];
        else if (strcmp(key, "h") == 0) heightNode = &map->values[index];
        else if (strcmp(key, "stride") == 0) strideNode = &map->values[index];
        else if (strcmp(key, "format") == 0) formatNode = &map->values[index];
        else if (strcmp(key, "data") == 0) dataNode = &map->values[index];
    }
    if (!widthNode || widthNode->format != MPV_FORMAT_INT64
        || !heightNode || heightNode->format != MPV_FORMAT_INT64
        || !strideNode || strideNode->format != MPV_FORMAT_INT64
        || !formatNode || formatNode->format != MPV_FORMAT_STRING
        || !formatNode->u.string || strcmp(formatNode->u.string, "bgra") != 0
        || !dataNode || dataNode->format != MPV_FORMAT_BYTE_ARRAY || !dataNode->u.ba) return nil;

    int64_t width = widthNode->u.int64;
    int64_t height = heightNode->u.int64;
    int64_t stride = strideNode->u.int64;
    mpv_byte_array *bytes = dataNode->u.ba;
    if (width <= 0 || height <= 0 || width > 8192 || height > 8192 || stride == 0) return nil;
    uint64_t absoluteStride = (uint64_t)llabs(stride);
    uint64_t rowBytes = (uint64_t)width * 4;
    uint64_t requiredBytes = absoluteStride * (uint64_t)(height - 1) + rowBytes;
    if (absoluteStride < rowBytes || requiredBytes > bytes->size || requiredBytes > 256ULL * 1024 * 1024) {
        return nil;
    }

    NSMutableData *contiguous = [NSMutableData dataWithLength:(NSUInteger)(rowBytes * (uint64_t)height)];
    if (!contiguous || !bytes->data) return nil;
    const uint8_t *source = bytes->data;
    uint8_t *destination = contiguous.mutableBytes;
    for (int64_t row = 0; row < height; row += 1) {
        const uint8_t *sourceRow = stride > 0
            ? source + row * stride
            : source + (height - 1 - row) * absoluteStride;
        memcpy(destination + row * rowBytes, sourceRow, (size_t)rowBytes);
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)contiguous);
    CGBitmapInfo bitmapInfo = (CGBitmapInfo)(
        kCGBitmapByteOrder32Little | (CGBitmapInfo)kCGImageAlphaPremultipliedFirst
    );
    CGImageRef sourceImage = CGImageCreate(
        (size_t)width,
        (size_t)height,
        8,
        32,
        (size_t)rowBytes,
        colorSpace,
        bitmapInfo,
        provider,
        NULL,
        false,
        kCGRenderingIntentDefault
    );
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    if (!sourceImage) return nil;

    size_t outputWidth = (size_t)MAX(1, llround(_maximumSize.width));
    size_t outputHeight = (size_t)MAX(1, llround(_maximumSize.height));
    CGColorSpaceRef outputColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(
        NULL,
        outputWidth,
        outputHeight,
        8,
        outputWidth * 4,
        outputColorSpace,
        (CGBitmapInfo)kCGImageAlphaPremultipliedLast
    );
    CGColorSpaceRelease(outputColorSpace);
    if (!context) {
        CGImageRelease(sourceImage);
        return nil;
    }
    double scale = MAX((double)outputWidth / (double)width, (double)outputHeight / (double)height);
    CGSize drawSize = CGSizeMake((double)width * scale, (double)height * scale);
    CGRect drawRect = CGRectMake(
        ((double)outputWidth - drawSize.width) / 2,
        ((double)outputHeight - drawSize.height) / 2,
        drawSize.width,
        drawSize.height
    );
    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    CGContextDrawImage(context, drawRect, sourceImage);
    CGImageRef outputImage = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    CGImageRelease(sourceImage);
    if (!outputImage) return nil;
    NSImage *image = [[NSImage alloc] initWithCGImage:outputImage size:_maximumSize];
    CGImageRelease(outputImage);
    return image;
}

- (NSError *)errorWithDescription:(NSString *)description {
    return [NSError errorWithDomain:OMMpvThumbnailErrorDomain
                               code:1
                           userInfo:@{ NSLocalizedDescriptionKey: description }];
}

- (void)finishWithImage:(NSImage *)image error:(NSError *)error {
    OMMpvThumbnailCompletion completion = _completion;
    _completion = nil;
    _pendingGeneration = 0;
    _phase = OMMpvThumbnailPhaseIdle;
    _didReceiveSeekReply = NO;
    _didRestartAfterSeek = NO;
    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(image, error);
        });
    }
}

- (void)stop {
    void (^shutdown)(void) = ^{
        if (self->_stopped) return;
        [self cancelPendingRequestOnQueue];
        self->_stopped = YES;
        if (self->_mpv) {
            mpv_set_wakeup_callback(self->_mpv, NULL, NULL);
            mpv_terminate_destroy(self->_mpv);
            self->_mpv = NULL;
        }
    };
    if (dispatch_get_specific(OMMpvThumbnailQueueKey)) {
        shutdown();
    } else {
        dispatch_sync(_queue, shutdown);
    }
}

@end

#endif
