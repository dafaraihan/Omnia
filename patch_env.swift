import Foundation

let path = "Omnia/UI/Components/HeroBackdropEnvironment.swift"
var content = try! String(contentsOfFile: path)
content = content.replacingOccurrences(of: """
        // Preserve stable frame during minor structural updates
        return WindowHeroPresentation(item: item, frame: existing.frame)
""", with: """
        return WindowHeroPresentation(item: item, frame: frame)
""")
try! content.write(toFile: path, atomically: true, encoding: .utf8)
