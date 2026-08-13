import XCTest
@testable import Omnia

final class AboutSettingsTests: XCTestCase {
    func testEveryApprovedAboutSectionHasContent() {
        for section in AboutSection.allCases {
            XCTAssertFalse(AboutCatalog.items(for: section).isEmpty, "Missing \(section)")
        }
    }

    func testDirectRuntimeResourcesAreDocumented() {
        let ids = Set(AboutCatalog.resources.map(\.id))
        let required: Set<String> = [
            "tmdb",
            "tvdb",
            "mdblist",
            "anilist",
            "youtube",
            "introdb",
            "stremio-addons",
            "avplayer",
            "libmpv",
            "supabase",
            "sign-in-with-apple",
            "google-auth",
            "facebook-auth",
            "swiftui",
            "foundation",
            "observation",
            "swiftdata",
            "avfoundation",
            "avkit",
            "authenticationservices",
            "cryptokit",
            "security",
            "uniformtypeidentifiers",
            "uikit",
            "appkit",
            "supabase-swift",
            "native-playback-libraries"
        ]

        XCTAssertTrue(required.isSubset(of: ids), "Missing \(required.subtracting(ids))")
    }

    func testEveryExternalResourceLinkUsesHTTPS() {
        for resource in AboutCatalog.resources {
            for link in resource.links {
                XCTAssertEqual(link.url.scheme, "https", "Unsafe About link: \(link.url)")
            }
        }
    }

    func testTMDBRequiredNoticeIsExact() throws {
        let tmdb = try XCTUnwrap(AboutCatalog.resources.first { $0.id == "tmdb" })

        XCTAssertEqual(
            tmdb.attribution,
            "This product uses the TMDB API but is not endorsed or certified by TMDB."
        )
    }

    func testNativePlaybackDescriptionMatchesPinnedMinimalClosure() throws {
        let nativePlayback = try XCTUnwrap(
            AboutCatalog.resources.first { $0.id == "native-playback-libraries" }
        )

        XCTAssertTrue(nativePlayback.purpose.contains("OpenSSL"))
        XCTAssertTrue(nativePlayback.purpose.contains("libtorrent"))
        XCTAssertFalse(nativePlayback.purpose.contains("MuJS"))
        XCTAssertFalse(nativePlayback.purpose.contains("LuaJIT"))
        XCTAssertTrue(nativePlayback.sections.contains(.licenses))
    }

    func testEveryMDBListRatingSourceHasHTTPSProvenanceAndAboutResource() {
        let aboutIDs = Set(AboutCatalog.resources.map(\.id))

        for record in MDBListRatingProviderProvenance.records {
            XCTAssertEqual(record.officialURL.scheme, "https")
            XCTAssertTrue(
                aboutIDs.contains(record.aboutResourceID),
                "Missing About resource for \(record.displayName)"
            )
        }
    }

    func testEveryRatingAssetIsInReviewedProvenanceMatrix() {
        let reviewed = Set(
            MDBListRatingProviderProvenance.records.flatMap(\.assetNames)
        )
        let registry = Set(
            MDBListRatingProviderRegistry.knownDescriptors.flatMap { descriptor in
                [descriptor.defaultAssetName, descriptor.negativeAssetName].compactMap { $0 }
            }
        ).union([MDBListRatingProviderRegistry.aggregateAssetName])

        XCTAssertEqual(registry, reviewed)
    }
}
