import Foundation

let path = "Omnia/UI/Components/HeroBackdropEnvironment.swift"
var content = try! String(contentsOfFile: path)
content = content.replacingOccurrences(of: """
    static func artworkFrame(windowWidth: CGFloat, measuredHeroFrame: CGRect) -> CGRect {
        CGRect(
            x: 0,
            y: measuredHeroFrame.minY,
            width: windowWidth,
            height: measuredHeroFrame.height
        )
    }
""", with: """
    static func artworkFrame(windowWidth: CGFloat, measuredHeroFrame: CGRect, backdropGlobalFrame: CGRect) -> CGRect {
        CGRect(
            x: 0,
            y: measuredHeroFrame.minY - backdropGlobalFrame.minY,
            width: windowWidth,
            height: measuredHeroFrame.height
        )
    }
""")
content = content.replacingOccurrences(of: """
    static func accentFrame(windowSize: CGSize, measuredHeroFrame: CGRect) -> CGRect {
        let originY = measuredHeroFrame.maxY
        return CGRect(
            x: 0,
            y: originY,
            width: windowSize.width,
            height: max(0, windowSize.height - originY)
        )
    }
""", with: """
    static func accentFrame(windowSize: CGSize, measuredHeroFrame: CGRect, backdropGlobalFrame: CGRect) -> CGRect {
        let originY = measuredHeroFrame.maxY - backdropGlobalFrame.minY
        return CGRect(
            x: 0,
            y: originY,
            width: windowSize.width,
            height: max(0, windowSize.height - originY)
        )
    }
""")
content = content.replacingOccurrences(of: """
                    let artworkFrame = WindowHeroBackdropLayout.artworkFrame(
                        windowWidth: proxy.size.width,
                        measuredHeroFrame: presentation.frame
                    )
                    let accentFrame = WindowHeroBackdropLayout.accentFrame(
                        windowSize: proxy.size,
                        measuredHeroFrame: presentation.frame
                    )
""", with: """
                    let artworkFrame = WindowHeroBackdropLayout.artworkFrame(
                        windowWidth: proxy.size.width,
                        measuredHeroFrame: presentation.frame,
                        backdropGlobalFrame: globalFrame
                    )
                    let accentFrame = WindowHeroBackdropLayout.accentFrame(
                        windowSize: proxy.size,
                        measuredHeroFrame: presentation.frame,
                        backdropGlobalFrame: globalFrame
                    )
""")
try! content.write(toFile: path, atomically: true, encoding: .utf8)
