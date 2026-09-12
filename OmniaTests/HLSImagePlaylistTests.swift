import Foundation
import XCTest
@testable import Omnia

final class HLSImagePlaylistTests: XCTestCase {
    func testParsesImageStreamAndTileTimeline() throws {
        let masterURL = try XCTUnwrap(URL(string: "https://media.example/master.m3u8"))
        let master = Data("""
        #EXTM3U
        #EXT-X-IMAGE-STREAM-INF:BANDWIDTH=20000,CODECS="jpeg",RESOLUTION=320x180,URI="images/index.m3u8"
        """.utf8)
        XCTAssertEqual(
            try HLSImagePlaylistParser.imagePlaylistURL(data: master, baseURL: masterURL),
            URL(string: "https://media.example/images/index.m3u8")
        )

        let playlistURL = try XCTUnwrap(URL(string: "https://media.example/images/index.m3u8"))
        let playlist = Data("""
        #EXTM3U
        #EXT-X-TARGETDURATION:10
        #EXTINF:10.0,
        #EXT-X-TILES:RESOLUTION=160x90,LAYOUT=5x2,DURATION=1.0
        sheet-0.jpg
        """.utf8)
        let storyboard = try HLSImagePlaylistParser.storyboard(
            data: playlist,
            playlistURL: playlistURL,
            allowedOriginURL: masterURL
        )

        XCTAssertEqual(storyboard.tiles.count, 10)
        XCTAssertEqual(storyboard.tiles[6].startTime, 6)
        XCTAssertEqual(
            storyboard.tiles[6].crop,
            PlaybackStoryboardCrop(x: 160, y: 90, width: 160, height: 90)
        )
    }

    func testRejectsNonHTTPSAndCrossOriginHLSResources() throws {
        let httpsBase = try XCTUnwrap(URL(string: "https://media.example/master.m3u8"))
        let nonHTTPS = Data("#EXTM3U\n#EXT-X-IMAGE-STREAM-INF:URI=\"http://media.example/image.m3u8\"".utf8)
        let crossOrigin = Data("#EXTM3U\n#EXT-X-IMAGE-STREAM-INF:URI=\"https://other.example/image.m3u8\"".utf8)

        XCTAssertThrowsError(
            try HLSImagePlaylistParser.imagePlaylistURL(data: nonHTTPS, baseURL: httpsBase)
        )
        XCTAssertThrowsError(
            try HLSImagePlaylistParser.imagePlaylistURL(data: crossOrigin, baseURL: httpsBase)
        )
    }

    func testRejectsMalformedOrUnboundedTileDeclarations() throws {
        let url = try XCTUnwrap(URL(string: "https://media.example/images.m3u8"))
        let tooMany = Data("""
        #EXTM3U
        #EXTINF:10,
        #EXT-X-TILES:RESOLUTION=160x90,LAYOUT=100x100,DURATION=0.001
        sheet.jpg
        """.utf8)
        XCTAssertThrowsError(
            try HLSImagePlaylistParser.storyboard(
                data: tooMany,
                playlistURL: url,
                allowedOriginURL: url
            )
        )
    }

    func testRejectsByteRangeImagePlaylist() throws {
        let url = try XCTUnwrap(URL(string: "https://media.example/images.m3u8"))
        let playlist = Data("""
        #EXTM3U
        #EXTINF:10,
        #EXT-X-TILES:RESOLUTION=160x90,LAYOUT=1x1,DURATION=10
        #EXT-X-BYTERANGE:100@0
        sheet.jpg
        """.utf8)

        XCTAssertThrowsError(
            try HLSImagePlaylistParser.storyboard(
                data: playlist,
                playlistURL: url,
                allowedOriginURL: url
            )
        )
    }
}
