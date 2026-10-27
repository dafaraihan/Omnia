//
//  Omnia-Bridging-Header.h
//  Omnia
//

#if TARGET_OS_OSX
#import "Platform/Playback/MPVPlayerController.h"
#import "Platform/Playback/MPVThumbnailGenerator.h"
#import "Platform/Playback/LocalTorrentEngine.h"
#elif OMNIA_IOS_MPV
#import "Platform/Playback/MPVPlayerController.h"
#endif
