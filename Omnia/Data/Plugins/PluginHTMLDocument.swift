//
//  PluginHTMLDocument.swift
//  Omnia
//

import Foundation

/// A forgiving HTML parser and CSS selector engine behind the plugins'
/// `cheerio` module. Scrapers read web pages with it, so it accepts the same
/// broken markup browsers do: unclosed tags, stray end tags, unquoted
/// attributes. Nodes are numbered in document order, which is the order
/// selectors return them in.
nonisolated final class PluginHTMLDocument {
    enum Kind { case document, element, text, comment }

    struct Node {
        var kind: Kind
        var name: String = ""
        var attributes: [(name: String, value: String)] = []
        var text: String = ""
        var parent: Int = -1
        var children: [Int] = []
    }

    private(set) var nodes: [Node] = [Node(kind: .document)]

    static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"
    ]
    static let rawTextElements: Set<String> = ["script", "style", "textarea", "title", "xmp", "plaintext"]

    init(html: String) {
        parse(Array(html.unicodeScalars))
    }

    // MARK: Parsing

    private func parse(_ input: [Unicode.Scalar]) {
        var stack: [Int] = [0]
        var index = 0
        var text = String.UnicodeScalarView()

        func flushText() {
            guard !text.isEmpty else { return }
            appendNode(Node(kind: .text, text: Self.decodeEntities(String(text))), to: stack.last!)
            text = String.UnicodeScalarView()
        }

        func hasPrefix(_ prefix: String, at position: Int, caseInsensitive: Bool = false) -> Bool {
            var position = position
            for scalar in prefix.unicodeScalars {
                guard position < input.count else { return false }
                let candidate = input[position]
                if caseInsensitive {
                    guard Self.lowercased(candidate) == Self.lowercased(scalar) else { return false }
                } else if candidate != scalar {
                    return false
                }
                position += 1
            }
            return true
        }

        func indexOf(_ needle: String, from start: Int, caseInsensitive: Bool = false) -> Int? {
            guard let first = needle.unicodeScalars.first else { return nil }
            var position = start
            while position < input.count {
                if (caseInsensitive ? Self.lowercased(input[position]) == Self.lowercased(first) : input[position] == first),
                   hasPrefix(needle, at: position, caseInsensitive: caseInsensitive) {
                    return position
                }
                position += 1
            }
            return nil
        }

        func closeElement(named name: String) {
            guard let match = stack.lastIndex(where: { $0 != 0 && nodes[$0].name == name }) else { return }
            stack.removeSubrange(match...)
        }

        func closeUntil(_ names: Set<String>, stoppingAt boundaries: Set<String>) {
            var position = stack.count - 1
            while position > 0 {
                let name = nodes[stack[position]].name
                if boundaries.contains(name) { return }
                if names.contains(name) {
                    stack.removeSubrange(position...)
                    return
                }
                position -= 1
            }
        }

        func closeUntil(_ name: String, stoppingAt boundaries: Set<String>) {
            closeUntil([name], stoppingAt: boundaries)
        }

        func closeImplied(by name: String) {
            // The tags browsers close for you when the next one starts.
            guard let current = stack.last, current != 0 else { return }
            let open = nodes[current].name
            switch name {
            case "li": if stack.contains(where: { nodes[$0].name == "li" }) { closeUntil("li", stoppingAt: ["ul", "ol"]) }
            case "dt", "dd":
                if open == "dt" || open == "dd" { stack.removeLast() }
            case "tr": closeUntil("tr", stoppingAt: ["table", "thead", "tbody", "tfoot"])
            case "td", "th":
                if let cell = stack.lastIndex(where: { ["td", "th"].contains(nodes[$0].name) }),
                   !stack[cell...].contains(where: { nodes[$0].name == "table" }) {
                    stack.removeSubrange(cell...)
                }
            case "thead", "tbody", "tfoot":
                closeUntil(["thead", "tbody", "tfoot"], stoppingAt: ["table"])
            case "option": if open == "option" { stack.removeLast() }
            case "optgroup": closeUntil(["option", "optgroup"], stoppingAt: ["select"])
            default: break
            }
            if Self.closesParagraph.contains(name), let paragraph = stack.lastIndex(where: { nodes[$0].name == "p" }),
               !stack[paragraph...].contains(where: { ["button", "table"].contains(nodes[$0].name) }) {
                stack.removeSubrange(paragraph...)
            }
        }

        while index < input.count {
            let scalar = input[index]
            guard scalar == "<", index + 1 < input.count else {
                text.append(scalar)
                index += 1
                continue
            }
            let next = input[index + 1]

            if hasPrefix("<!--", at: index) {
                flushText()
                let end = indexOf("-->", from: index + 4) ?? input.count
                let body = String(String.UnicodeScalarView(input[(index + 4)..<min(end, input.count)]))
                appendNode(Node(kind: .comment, text: body), to: stack.last!)
                index = min(end + 3, input.count)
                continue
            }
            if next == "!" || next == "?" {
                flushText()
                index = (indexOf(">", from: index) ?? input.count - 1) + 1
                continue
            }
            if next == "/" {
                var position = index + 2
                var name = ""
                while position < input.count, Self.isNameCharacter(input[position]) {
                    name.unicodeScalars.append(Self.lowercased(input[position]))
                    position += 1
                }
                guard !name.isEmpty else {
                    text.append(scalar)
                    index += 1
                    continue
                }
                flushText()
                index = (indexOf(">", from: position) ?? input.count - 1) + 1
                if name == "br" {
                    appendNode(Node(kind: .element, name: "br"), to: stack.last!)
                } else {
                    closeElement(named: name)
                }
                continue
            }
            guard Self.isLetter(next) else {
                text.append(scalar)
                index += 1
                continue
            }

            // A start tag.
            flushText()
            var position = index + 1
            var name = ""
            while position < input.count, Self.isNameCharacter(input[position]) {
                name.unicodeScalars.append(Self.lowercased(input[position]))
                position += 1
            }
            var attributes: [(name: String, value: String)] = []
            var selfClosing = false
            while position < input.count {
                while position < input.count, Self.isSpace(input[position]) { position += 1 }
                guard position < input.count else { break }
                let character = input[position]
                if character == ">" { position += 1; break }
                if character == "/" {
                    selfClosing = true
                    position += 1
                    continue
                }
                var attributeName = ""
                while position < input.count {
                    let current = input[position]
                    if Self.isSpace(current) || current == "=" || current == ">" || (current == "/" && attributeName.isEmpty == false && position + 1 < input.count && input[position + 1] == ">") { break }
                    attributeName.unicodeScalars.append(Self.lowercased(current))
                    position += 1
                }
                if attributeName.isEmpty {
                    position += 1
                    continue
                }
                while position < input.count, Self.isSpace(input[position]) { position += 1 }
                var value = ""
                if position < input.count, input[position] == "=" {
                    position += 1
                    while position < input.count, Self.isSpace(input[position]) { position += 1 }
                    if position < input.count, input[position] == "\"" || input[position] == "'" {
                        let quote = input[position]
                        position += 1
                        let start = position
                        while position < input.count, input[position] != quote { position += 1 }
                        value = String(String.UnicodeScalarView(input[start..<position]))
                        position = min(position + 1, input.count)
                    } else {
                        let start = position
                        while position < input.count, !Self.isSpace(input[position]), input[position] != ">" { position += 1 }
                        value = String(String.UnicodeScalarView(input[start..<position]))
                    }
                }
                if !attributes.contains(where: { $0.name == attributeName }) {
                    attributes.append((attributeName, Self.decodeEntities(value)))
                }
            }
            index = position

            closeImplied(by: name)
            let element = appendNode(Node(kind: .element, name: name, attributes: attributes), to: stack.last!)
            if Self.rawTextElements.contains(name), !selfClosing {
                let end = indexOf("</\(name)", from: index, caseInsensitive: true) ?? input.count
                if end > index {
                    var body = String(String.UnicodeScalarView(input[index..<end]))
                    if name == "textarea" || name == "title" { body = Self.decodeEntities(body) }
                    appendNode(Node(kind: .text, text: body), to: element)
                }
                index = end < input.count ? ((indexOf(">", from: end) ?? input.count - 1) + 1) : input.count
            } else if !selfClosing, !Self.voidElements.contains(name) {
                stack.append(element)
            }
        }
        flushText()
    }

    @discardableResult
    private func appendNode(_ node: Node, to parent: Int) -> Int {
        var node = node
        node.parent = parent
        nodes.append(node)
        let id = nodes.count - 1
        nodes[parent].children.append(id)
        return id
    }

    private static let closesParagraph: Set<String> = [
        "address", "article", "aside", "blockquote", "div", "dl", "fieldset", "footer", "form", "h1", "h2", "h3",
        "h4", "h5", "h6", "header", "hr", "main", "nav", "ol", "p", "pre", "section", "table", "ul"
    ]

    // MARK: Reading

    func isElement(_ id: Int) -> Bool {
        nodes.indices.contains(id) && nodes[id].kind == .element
    }

    func attribute(_ name: String, of id: Int) -> String? {
        guard nodes.indices.contains(id) else { return nil }
        let name = name.lowercased()
        return nodes[id].attributes.first { $0.name == name }?.value
    }

    func elementChildren(of id: Int) -> [Int] {
        guard nodes.indices.contains(id) else { return [] }
        return nodes[id].children.filter { nodes[$0].kind == .element }
    }

    func parentElement(of id: Int) -> Int? {
        guard nodes.indices.contains(id) else { return nil }
        let parent = nodes[id].parent
        return parent > 0 ? parent : nil
    }

    func elementSiblings(of id: Int) -> [Int] {
        guard nodes.indices.contains(id) else { return [] }
        return elementChildren(of: nodes[id].parent)
    }

    func previousElement(of id: Int) -> Int? {
        let siblings = elementSiblings(of: id)
        guard let position = siblings.firstIndex(of: id), position > 0 else { return nil }
        return siblings[position - 1]
    }

    func nextElement(of id: Int) -> Int? {
        let siblings = elementSiblings(of: id)
        guard let position = siblings.firstIndex(of: id), position + 1 < siblings.count else { return nil }
        return siblings[position + 1]
    }

    /// Every element below `id`, in document order.
    func descendants(of id: Int) -> [Int] {
        var result: [Int] = []
        var stack: [Int] = nodes.indices.contains(id) ? Array(nodes[id].children.reversed()) : []
        while let next = stack.popLast() {
            if nodes[next].kind == .element { result.append(next) }
            stack.append(contentsOf: nodes[next].children.reversed())
        }
        return result
    }

    func textContent(of id: Int) -> String {
        guard nodes.indices.contains(id) else { return "" }
        let node = nodes[id]
        switch node.kind {
        case .text: return node.text
        case .comment: return ""
        case .element, .document: return node.children.map(textContent(of:)).joined()
        }
    }

    func innerHTML(of id: Int) -> String {
        guard nodes.indices.contains(id) else { return "" }
        return nodes[id].children.map(outerHTML(of:)).joined()
    }

    func outerHTML(of id: Int) -> String {
        guard nodes.indices.contains(id) else { return "" }
        let node = nodes[id]
        switch node.kind {
        case .document:
            return innerHTML(of: id)
        case .comment:
            return "<!--\(node.text)-->"
        case .text:
            let parentName = nodes[node.parent].name
            return Self.rawTextElements.contains(parentName) ? node.text : Self.escape(node.text, attribute: false)
        case .element:
            let attributes = node.attributes.map { attribute in
                attribute.value.isEmpty ? " \(attribute.name)" : " \(attribute.name)=\"\(Self.escape(attribute.value, attribute: true))\""
            }.joined()
            if Self.voidElements.contains(node.name) { return "<\(node.name)\(attributes)>" }
            return "<\(node.name)\(attributes)>\(innerHTML(of: id))</\(node.name)>"
        }
    }

    // MARK: Selectors

    /// Elements below `roots` (the whole document for none) that match.
    func select(_ selector: String, within roots: [Int]? = nil) -> [Int] {
        guard let groups = try? PluginCSSSelector.parse(selector) else { return [] }
        let scopes = roots ?? [0]
        var candidates: [Int] = []
        var seen = Set<Int>()
        for root in scopes {
            for id in descendants(of: root) where seen.insert(id).inserted { candidates.append(id) }
        }
        candidates.sort()

        var matched = Set<Int>()
        for complex in groups {
            var hits = candidates.filter { matches($0, complex, at: complex.parts.count - 1, scopes: Set(scopes)) }
            hits = complex.applyPositional(to: hits)
            matched.formUnion(hits)
        }
        return matched.sorted()
    }

    /// Whether the element itself matches, as `.is()` and `.filter()` ask.
    func matches(_ id: Int, selector: String) -> Bool {
        guard isElement(id), let groups = try? PluginCSSSelector.parse(selector) else { return false }
        return groups.contains { matches(id, $0, at: $0.parts.count - 1, scopes: [0]) }
    }

    private func matches(_ id: Int, _ complex: PluginCSSSelector.Complex, at partIndex: Int, scopes: Set<Int>) -> Bool {
        let part = complex.parts[partIndex]
        guard matchesCompound(id, part.compound) else { return false }
        if partIndex == 0 {
            // A selector that starts with a combinator, like `> li` in
            // `.find("> li")`, is anchored to the element it searches from.
            switch part.combinator {
            case .none, .descendant: return part.combinator == .none || ancestors(of: id).contains(where: scopes.contains)
            case .child: return scopes.contains(nodes[id].parent)
            case .adjacent: return previousElement(of: id).map(scopes.contains) ?? false
            case .sibling: return elementSiblings(of: id).prefix { $0 != id }.contains(where: scopes.contains)
            }
        }
        switch part.combinator {
        case .none, .descendant:
            return ancestors(of: id).contains { matches($0, complex, at: partIndex - 1, scopes: scopes) }
        case .child:
            guard let parent = parentElement(of: id) else { return false }
            return matches(parent, complex, at: partIndex - 1, scopes: scopes)
        case .adjacent:
            guard let previous = previousElement(of: id) else { return false }
            return matches(previous, complex, at: partIndex - 1, scopes: scopes)
        case .sibling:
            return elementSiblings(of: id).prefix { $0 != id }.contains { matches($0, complex, at: partIndex - 1, scopes: scopes) }
        }
    }

    private func ancestors(of id: Int) -> [Int] {
        var result: [Int] = []
        var current = nodes[id].parent
        while current > 0 {
            result.append(current)
            current = nodes[current].parent
        }
        return result
    }

    private func matchesCompound(_ id: Int, _ compound: PluginCSSSelector.Compound) -> Bool {
        let node = nodes[id]
        guard node.kind == .element else { return false }
        if let tag = compound.tag, tag != "*", tag != node.name { return false }
        if let elementID = compound.id, attribute("id", of: id) != elementID { return false }
        if !compound.classes.isEmpty {
            let classes = Set((attribute("class", of: id) ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
            guard compound.classes.allSatisfy(classes.contains) else { return false }
        }
        for test in compound.attributes where !test.matches(attribute(test.name, of: id)) { return false }
        for pseudo in compound.pseudos where !matchesPseudo(id, pseudo) { return false }
        return true
    }

    private func matchesPseudo(_ id: Int, _ pseudo: PluginCSSSelector.Pseudo) -> Bool {
        switch pseudo {
        case let .nthChild(a, b, fromEnd, ofType):
            var siblings = elementSiblings(of: id)
            if ofType { siblings = siblings.filter { nodes[$0].name == nodes[id].name } }
            if fromEnd { siblings.reverse() }
            guard let position = siblings.firstIndex(of: id) else { return false }
            return PluginCSSSelector.nth(position + 1, a: a, b: b)
        case .onlyChild:
            return elementSiblings(of: id).count == 1
        case .onlyOfType:
            return elementSiblings(of: id).filter { nodes[$0].name == nodes[id].name }.count == 1
        case .empty:
            return nodes[id].children.allSatisfy { nodes[$0].kind == .comment || (nodes[$0].kind == .text && nodes[$0].text.isEmpty) }
        case .root:
            return nodes[id].parent == 0
        case let .contains(text):
            return textContent(of: id).contains(text)
        case let .not(groups):
            return !groups.contains { matches(id, $0, at: $0.parts.count - 1, scopes: [0]) }
        case let .has(groups):
            let below = Set(descendants(of: id))
            return groups.contains { complex in
                below.contains { matches($0, complex, at: complex.parts.count - 1, scopes: [id]) }
            }
        case let .attributeFlag(name):
            return attribute(name, of: id) != nil
        case .header:
            return ["h1", "h2", "h3", "h4", "h5", "h6"].contains(nodes[id].name)
        case .positional:
            // Applied to the whole match set, in `select`.
            return true
        }
    }

    // MARK: Text helpers

    static func escape(_ text: String, attribute: Bool) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<" where !attribute: result += "&lt;"
            case ">" where !attribute: result += "&gt;"
            case "\"" where attribute: result += "&quot;"
            case "\u{A0}": result += "&nbsp;"
            default: result.append(character)
            }
        }
        return result
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character == "&",
                  let semicolon = text[index...].prefix(34).firstIndex(of: ";")
            else {
                result.append(character)
                index = text.index(after: index)
                continue
            }
            let entity = text[text.index(after: index)..<semicolon]
            var decoded: String?
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                decoded = UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if entity.hasPrefix("#") {
                decoded = UInt32(entity.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                decoded = namedEntities[String(entity)]
            }
            if let decoded {
                result += decoded
                index = text.index(after: semicolon)
            } else {
                result.append(character)
                index = text.index(after: index)
            }
        }
        return result
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{A0}", "copy": "©", "reg": "®",
        "trade": "™", "hellip": "…", "mdash": "—", "ndash": "–", "lsquo": "‘", "rsquo": "’", "ldquo": "“",
        "rdquo": "”", "laquo": "«", "raquo": "»", "times": "×", "divide": "÷", "bull": "•", "middot": "·",
        "deg": "°", "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "sect": "§", "para": "¶", "frac12": "½",
        "frac14": "¼", "frac34": "¾", "eacute": "é", "egrave": "è", "ecirc": "ê", "aacute": "á", "agrave": "à",
        "acirc": "â", "atilde": "ã", "auml": "ä", "ccedil": "ç", "iacute": "í", "oacute": "ó", "ograve": "ò",
        "ocirc": "ô", "otilde": "õ", "ouml": "ö", "uacute": "ú", "uuml": "ü", "ntilde": "ñ", "szlig": "ß",
        "Eacute": "É", "Aacute": "Á", "Oacute": "Ó", "Uacute": "Ú", "Ntilde": "Ñ", "Ccedil": "Ç", "zwnj": "\u{200C}",
        "zwj": "\u{200D}", "lrm": "\u{200E}", "rlm": "\u{200F}", "ensp": "\u{2002}", "emsp": "\u{2003}",
        "thinsp": "\u{2009}", "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓", "star": "☆", "hearts": "♥"
    ]

    fileprivate static func lowercased(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        (65...90).contains(scalar.value) ? Unicode.Scalar(scalar.value + 32)! : scalar
    }

    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }

    private static func isNameCharacter(_ scalar: Unicode.Scalar) -> Bool {
        isLetter(scalar) || (48...57).contains(scalar.value) || scalar == "-" || scalar == "_" || scalar == ":"
    }

    private static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\n" || scalar == "\t" || scalar == "\r" || scalar == "\u{0C}"
    }
}

/// CSS selectors as cheerio understands them, including jQuery's
/// `:contains()`, `:eq()`, `:first` and `:last`.
nonisolated enum PluginCSSSelector {
    enum Combinator: Equatable { case none, descendant, child, adjacent, sibling }

    enum Pseudo {
        case nthChild(a: Int, b: Int, fromEnd: Bool, ofType: Bool)
        case onlyChild, onlyOfType, empty, root, header
        case contains(String)
        case not([Complex])
        case has([Complex])
        case attributeFlag(String)
        case positional(Positional)
    }

    enum Positional {
        case eq(Int), gt(Int), lt(Int), first, last, even, odd
    }

    struct AttributeTest {
        enum Operation { case exists, equals, includes, dash, prefix, suffix, substring, notEquals }
        let name: String
        let operation: Operation
        let value: String
        let caseInsensitive: Bool

        func matches(_ actual: String?) -> Bool {
            guard let actual else { return operation == .notEquals }
            let lhs = caseInsensitive ? actual.lowercased() : actual
            let rhs = caseInsensitive ? value.lowercased() : value
            switch operation {
            case .exists: return true
            case .equals: return lhs == rhs
            case .notEquals: return lhs != rhs
            case .includes: return lhs.split(whereSeparator: \.isWhitespace).contains { $0 == rhs }
            case .dash: return lhs == rhs || lhs.hasPrefix(rhs + "-")
            case .prefix: return !rhs.isEmpty && lhs.hasPrefix(rhs)
            case .suffix: return !rhs.isEmpty && lhs.hasSuffix(rhs)
            case .substring: return !rhs.isEmpty && lhs.contains(rhs)
            }
        }
    }

    struct Compound {
        var tag: String?
        var id: String?
        var classes: [String] = []
        var attributes: [AttributeTest] = []
        var pseudos: [Pseudo] = []
    }

    struct Complex {
        var parts: [(combinator: Combinator, compound: Compound)] = []

        func applyPositional(to hits: [Int]) -> [Int] {
            guard let last = parts.last else { return hits }
            var result = hits
            for case let .positional(position) in last.compound.pseudos {
                switch position {
                case let .eq(index):
                    let resolved = index < 0 ? result.count + index : index
                    result = result.indices.contains(resolved) ? [result[resolved]] : []
                case let .gt(index): result = Array(result.dropFirst(max(0, index + 1)))
                case let .lt(index): result = Array(result.prefix(max(0, index)))
                case .first: result = Array(result.prefix(1))
                case .last: result = result.last.map { [$0] } ?? []
                case .even: result = result.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
                case .odd: result = result.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
                }
            }
            return result
        }
    }

    struct ParseError: Error {}

    static func nth(_ position: Int, a: Int, b: Int) -> Bool {
        if a == 0 { return position == b }
        let difference = position - b
        return difference % a == 0 && difference / a >= 0
    }

    static func parse(_ selector: String) throws -> [Complex] {
        var parser = Parser(Array(selector.unicodeScalars))
        return try parser.parseGroups()
    }

    private struct Parser {
        let input: [Unicode.Scalar]
        var position = 0

        init(_ input: [Unicode.Scalar]) { self.input = input }

        var atEnd: Bool { position >= input.count }
        var current: Unicode.Scalar? { atEnd ? nil : input[position] }

        mutating func skipSpaces() -> Bool {
            var skipped = false
            while let current, current == " " || current == "\n" || current == "\t" || current == "\r" {
                position += 1
                skipped = true
            }
            return skipped
        }

        mutating func parseGroups(until terminator: Unicode.Scalar? = nil) throws -> [Complex] {
            var groups: [Complex] = []
            var complex = Complex()
            var pendingCombinator: Combinator = .none
            _ = skipSpaces()
            while let character = current {
                if let terminator, character == terminator { break }
                if character == "," {
                    position += 1
                    if !complex.parts.isEmpty { groups.append(complex) }
                    complex = Complex()
                    pendingCombinator = .none
                    _ = skipSpaces()
                    continue
                }
                if character == ">" || character == "+" || character == "~" {
                    position += 1
                    pendingCombinator = character == ">" ? .child : character == "+" ? .adjacent : .sibling
                    _ = skipSpaces()
                    continue
                }
                let compound = try parseCompound()
                complex.parts.append((complex.parts.isEmpty && pendingCombinator == .none ? .none : pendingCombinator, compound))
                pendingCombinator = .none
                if skipSpaces(), let next = current, next != ",", next != ">", next != "+", next != "~", next != terminator {
                    pendingCombinator = .descendant
                }
            }
            if !complex.parts.isEmpty { groups.append(complex) }
            guard !groups.isEmpty else { throw ParseError() }
            return groups
        }

        mutating func identifier() -> String {
            var result = ""
            while let character = current {
                if character == "\\" , position + 1 < input.count {
                    result.unicodeScalars.append(input[position + 1])
                    position += 2
                    continue
                }
                let value = character.value
                let allowed = (48...57).contains(value) || (65...90).contains(value) || (97...122).contains(value)
                    || character == "-" || character == "_" || value > 127
                guard allowed else { break }
                result.unicodeScalars.append(character)
                position += 1
            }
            return result
        }

        mutating func parseCompound() throws -> Compound {
            var compound = Compound()
            if current == "*" {
                compound.tag = "*"
                position += 1
            } else if let character = current, character != ".", character != "#", character != "[", character != ":" {
                let tag = identifier()
                guard !tag.isEmpty else { throw ParseError() }
                compound.tag = tag.lowercased()
            }
            while let character = current {
                switch character {
                case "#":
                    position += 1
                    compound.id = identifier()
                case ".":
                    position += 1
                    compound.classes.append(identifier())
                case "[":
                    position += 1
                    compound.attributes.append(try parseAttribute())
                case ":":
                    position += 1
                    if current == ":" { position += 1 }
                    compound.pseudos.append(try parsePseudo())
                default:
                    return compound
                }
            }
            return compound
        }

        mutating func parseAttribute() throws -> AttributeTest {
            _ = skipSpaces()
            let name = identifier().lowercased()
            _ = skipSpaces()
            var operation: AttributeTest.Operation = .exists
            if let character = current, character != "]" {
                let prefixes: [Unicode.Scalar: AttributeTest.Operation] = [
                    "~": .includes, "|": .dash, "^": .prefix, "$": .suffix, "*": .substring, "!": .notEquals
                ]
                if let found = prefixes[character] {
                    operation = found
                    position += 1
                } else {
                    operation = .equals
                }
                guard current == "=" else { throw ParseError() }
                position += 1
            }
            _ = skipSpaces()
            var value = ""
            if let quote = current, quote == "\"" || quote == "'" {
                position += 1
                while let character = current, character != quote {
                    value.unicodeScalars.append(character)
                    position += 1
                }
                position += 1
            } else {
                while let character = current, character != "]", character != " " {
                    value.unicodeScalars.append(character)
                    position += 1
                }
            }
            _ = skipSpaces()
            var caseInsensitive = false
            if current == "i" || current == "I" {
                caseInsensitive = true
                position += 1
                _ = skipSpaces()
            }
            guard current == "]" else { throw ParseError() }
            position += 1
            return AttributeTest(name: name, operation: operation, value: value, caseInsensitive: caseInsensitive)
        }

        mutating func argument() throws -> String {
            guard current == "(" else { throw ParseError() }
            position += 1
            var depth = 1
            var result = ""
            while let character = current {
                position += 1
                if character == "(" { depth += 1 }
                if character == ")" {
                    depth -= 1
                    if depth == 0 { break }
                }
                result.unicodeScalars.append(character)
            }
            return result.trimmingCharacters(in: .whitespaces)
        }

        mutating func parsePseudo() throws -> Pseudo {
            let name = identifier().lowercased()
            switch name {
            case "first-child": return .nthChild(a: 0, b: 1, fromEnd: false, ofType: false)
            case "last-child": return .nthChild(a: 0, b: 1, fromEnd: true, ofType: false)
            case "first-of-type": return .nthChild(a: 0, b: 1, fromEnd: false, ofType: true)
            case "last-of-type": return .nthChild(a: 0, b: 1, fromEnd: true, ofType: true)
            case "only-child": return .onlyChild
            case "only-of-type": return .onlyOfType
            case "empty": return .empty
            case "root": return .root
            case "header": return .header
            case "checked", "selected", "disabled":
                return .attributeFlag(name)
            case "nth-child", "nth-last-child", "nth-of-type", "nth-last-of-type":
                let (a, b) = try Self.nthArguments(try argument())
                return .nthChild(a: a, b: b, fromEnd: name.contains("last"), ofType: name.contains("type"))
            case "contains":
                var text = try argument()
                if let first = text.first, first == "\"" || first == "'", text.count >= 2, text.last == first {
                    text = String(text.dropFirst().dropLast())
                }
                return .contains(text)
            case "not":
                var inner = Parser(Array(try argument().unicodeScalars))
                return .not(try inner.parseGroups())
            case "has":
                var inner = Parser(Array(try argument().unicodeScalars))
                return .has(try inner.parseGroups())
            case "eq": return .positional(.eq(Int(try argument()) ?? 0))
            case "gt": return .positional(.gt(Int(try argument()) ?? 0))
            case "lt": return .positional(.lt(Int(try argument()) ?? 0))
            case "first": return .positional(.first)
            case "last": return .positional(.last)
            case "even": return .positional(.even)
            case "odd": return .positional(.odd)
            default: throw ParseError()
            }
        }

        static func nthArguments(_ text: String) throws -> (Int, Int) {
            let value = text.lowercased().replacingOccurrences(of: " ", with: "")
            if value == "odd" { return (2, 1) }
            if value == "even" { return (2, 0) }
            if let number = Int(value) { return (0, number) }
            guard let n = value.firstIndex(of: "n") else { throw ParseError() }
            let aText = String(value[..<n])
            let a = aText.isEmpty || aText == "+" ? 1 : aText == "-" ? -1 : (Int(aText) ?? 1)
            let bText = String(value[value.index(after: n)...])
            let b = bText.isEmpty ? 0 : (Int(bText) ?? 0)
            return (a, b)
        }
    }
}
