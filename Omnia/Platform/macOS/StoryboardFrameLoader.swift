#if os(macOS)
import AppKit
import Foundation
import ImageIO

nonisolated struct PlaybackTimelinePreviewImage: @unchecked Sendable {
    let image: NSImage
    let byteCount: Int
}

nonisolated enum StoryboardFrameLoaderError: Error, Equatable {
    case noFrame
    case insecureURL
    case originRejected
    case invalidImage
    case boundsExceeded
    case invalidCrop
}

nonisolated enum StoryboardFrameLoader {
    static let maximumImageBytes = 4 * 1_024 * 1_024
    static let maximumSourceDimension = 8_192
    static let outputSize = CGSize(width: 320, height: 180)

    static func image(
        for timestamp: Double,
        descriptor: PlaybackStoryboardDescriptor,
        transport: any HTTPTransporting,
        requestHeaders: [String: String]
    ) async throws -> PlaybackTimelinePreviewImage {
        guard timestamp.isFinite, timestamp >= 0,
              descriptor.allowedOriginURL.scheme?.lowercased() == "https",
              let allowedOrigin = NormalizedOrigin(url: descriptor.allowedOriginURL) else {
            throw StoryboardFrameLoaderError.insecureURL
        }
        guard let tile = tile(for: timestamp, in: descriptor.tiles) else {
            throw StoryboardFrameLoaderError.noFrame
        }
        guard tile.imageURL.scheme?.lowercased() == "https" else {
            throw StoryboardFrameLoaderError.insecureURL
        }
        guard allowedOrigin.permits(tile.imageURL) else {
            throw StoryboardFrameLoaderError.originRejected
        }

        try Task.checkCancellation()
        let data = try await transport.data(
            for: HTTPRequestPolicy(
                url: tile.imageURL,
                allowedOrigin: allowedOrigin,
                timeout: 8,
                maximumResponseBytes: maximumImageBytes,
                acceptedContentTypes: ["image/jpeg", "image/png"],
                requestHeaders: requestHeaders
            )
        )
        try Task.checkCancellation()
        let image = try decodedImage(from: data, crop: tile.crop)
        try Task.checkCancellation()
        return PlaybackTimelinePreviewImage(
            image: image,
            byteCount: Int(outputSize.width * outputSize.height) * 4
        )
    }

    private static func tile(
        for timestamp: Double,
        in tiles: [PlaybackStoryboardTile]
    ) -> PlaybackStoryboardTile? {
        if let match = tiles.first(where: { $0.contains(timestamp) }) {
            return match
        }
        guard let last = tiles.last, timestamp == last.endTime else { return nil }
        return last
    }

    private static func decodedImage(
        from data: Data,
        crop: PlaybackStoryboardCrop?
    ) throws -> NSImage {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0 else {
            throw StoryboardFrameLoaderError.invalidImage
        }
        guard width <= maximumSourceDimension, height <= maximumSourceDimension else {
            throw StoryboardFrameLoaderError.boundsExceeded
        }
        guard let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw StoryboardFrameLoaderError.invalidImage
        }

        let croppedImage: CGImage
        if let crop {
            guard crop.x >= 0,
                  crop.y >= 0,
                  crop.width > 0,
                  crop.height > 0,
                  crop.x + crop.width <= sourceImage.width,
                  crop.y + crop.height <= sourceImage.height else {
                throw StoryboardFrameLoaderError.invalidCrop
            }
            let imageRect = CGRect(
                x: crop.x,
                y: sourceImage.height - crop.y - crop.height,
                width: crop.width,
                height: crop.height
            )
            guard let image = sourceImage.cropping(to: imageRect) else {
                throw StoryboardFrameLoaderError.invalidCrop
            }
            croppedImage = image
        } else {
            croppedImage = sourceImage
        }

        let outputWidth = Int(outputSize.width)
        let outputHeight = Int(outputSize.height)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: outputWidth,
                  height: outputHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: outputWidth * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw StoryboardFrameLoaderError.invalidImage
        }

        let scale = max(
            outputSize.width / CGFloat(croppedImage.width),
            outputSize.height / CGFloat(croppedImage.height)
        )
        let drawSize = CGSize(
            width: CGFloat(croppedImage.width) * scale,
            height: CGFloat(croppedImage.height) * scale
        )
        let drawRect = CGRect(
            x: (outputSize.width - drawSize.width) / 2,
            y: (outputSize.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        context.interpolationQuality = .medium
        context.draw(croppedImage, in: drawRect)
        guard let outputImage = context.makeImage() else {
            throw StoryboardFrameLoaderError.invalidImage
        }
        return NSImage(cgImage: outputImage, size: outputSize)
    }
}
#endif
