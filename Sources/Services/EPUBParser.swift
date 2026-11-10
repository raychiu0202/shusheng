import Foundation
import ZIPFoundation

struct EPUBSection {
    let title: String?
    let level: Int
    let paragraphs: [String]
}

private struct TOCEntry {
    let href: String
    let title: String
    let level: Int
}

private struct ManifestItem {
    let href: String
    let mediaType: String
    let properties: String
}

private struct ExtractedText {
    let paragraphs: [String]
    let headings: [String]
}

/// 解析 EPUB：解压 → META-INF/container.xml → OPF 清单 → 目录（nav.xhtml / toc.ncx）→ spine 各章 XHTML
enum EPUBParser {

    enum EPUBError: LocalizedError {
        case badStructure

        var errorDescription: String? {
            "无法解析该 EPUB 文件（结构不完整或非标准）"
        }
    }

    static func sections(from url: URL) throws -> [EPUBSection] {
        let fm = FileManager.default
        let tempDirectory = fm.temporaryDirectory
            .appendingPathComponent("epub-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDirectory) }

        try fm.unzipItem(at: url, to: tempDirectory)

        let containerURL = tempDirectory.appendingPathComponent("META-INF/container.xml")
        guard let opfPath = containerRootfile(at: containerURL) else { throw EPUBError.badStructure }
        let opfURL = try safeURL(forRelativePath: opfPath, in: tempDirectory)
        let opfDirectory = opfURL.deletingLastPathComponent()

        let package = try OPFPackage.parse(url: opfURL)
        let tocEntries = readTOC(navHref: package.navHref, ncxHref: package.ncxHref, baseDirectory: opfDirectory)

        var tocMap: [String: TOCEntry] = [:]
        for entry in tocEntries {
            let key = normalizedHref(entry.href)
            if tocMap[key] == nil {
                tocMap[key] = entry
            }
        }

        var sections: [EPUBSection] = []
        for href in package.spineHrefs {
            let cleanHref = normalizedHref(href)
            guard let fileURL = try? safeURL(forRelativePath: cleanHref, in: opfDirectory),
                  let data = try? Data(contentsOf: fileURL) else { continue }
            let extracted = extractText(from: data)
            guard !extracted.paragraphs.isEmpty else { continue }

            let toc = tocMap[cleanHref]
            let title = toc?.title ?? extracted.headings.first
            sections.append(EPUBSection(
                title: title,
                level: toc?.level ?? 1,
                paragraphs: extracted.paragraphs
            ))
        }
        guard !sections.isEmpty else { throw EPUBError.badStructure }
        return sections
    }

    // MARK: - 路径处理

    private static func normalizedHref(_ href: String) -> String {
        let withoutFragment = href.components(separatedBy: CharacterSet(charactersIn: "#?")).first ?? href
        let decoded = withoutFragment.removingPercentEncoding ?? withoutFragment
        return (decoded as NSString).standardizingPath
    }

    private static func safeURL(forRelativePath path: String, in base: URL) throws -> URL {
        let url = base.appendingPathComponent(path).standardizedFileURL
        guard url.path.hasPrefix(base.standardizedFileURL.path) else {
            throw EPUBError.badStructure
        }
        return url
    }

    private static func localName(_ elementName: String, _ qName: String?) -> String {
        (qName?.split(separator: ":").last.map(String.init) ?? elementName).lowercased()
    }

    // MARK: - META-INF/container.xml

    private static func containerRootfile(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let delegate = RootfileDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.fullPath
    }

    private final class RootfileDelegate: NSObject, XMLParserDelegate {
        var fullPath: String?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            if localName(elementName, qName) == "rootfile" {
                fullPath = attributeDict["full-path"]
            }
        }
    }

    // MARK: - OPF 清单

    private struct OPFPackage {
        let spineHrefs: [String]
        let navHref: String?
        let ncxHref: String?

        static func parse(url: URL) throws -> OPFPackage {
            guard let data = try? Data(contentsOf: url) else { throw EPUBError.badStructure }
            let delegate = OPFDelegate()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            guard parser.parse(), !delegate.spineIdrefs.isEmpty else { throw EPUBError.badStructure }

            let spineHrefs = delegate.spineIdrefs.compactMap { idref -> String? in
                guard let item = delegate.manifest[idref] else { return nil }
                let mediaType = item.mediaType.lowercased()
                guard mediaType.contains("xhtml") || mediaType.contains("html") else { return nil }
                return item.href
            }
            let navHref = delegate.manifest.values
                .first { $0.properties.split(separator: " ").contains("nav") }?
                .href
            let ncxHref = delegate.manifest.values
                .first { $0.mediaType.lowercased() == "application/x-dtbncx+xml" }?
                .href
            return OPFPackage(spineHrefs: spineHrefs, navHref: navHref, ncxHref: ncxHref)
        }
    }

    private final class OPFDelegate: NSObject, XMLParserDelegate {
        fileprivate var manifest: [String: ManifestItem] = [:]
        var spineIdrefs: [String] = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = localName(elementName, qName)
            if name == "item", let id = attributeDict["id"], let href = attributeDict["href"] {
                manifest[id] = ManifestItem(
                    href: href,
                    mediaType: attributeDict["media-type"] ?? "",
                    properties: attributeDict["properties"] ?? ""
                )
            } else if name == "itemref", let idref = attributeDict["idref"] {
                spineIdrefs.append(idref)
            }
        }
    }

    // MARK: - 目录（EPUB3 nav.xhtml / EPUB2 toc.ncx）

    private static func readTOC(navHref: String?, ncxHref: String?, baseDirectory: URL) -> [TOCEntry] {
        if let navHref,
           let navURL = try? safeURL(forRelativePath: normalizedHref(navHref), in: baseDirectory),
           let data = try? Data(contentsOf: navURL) {
            let delegate = NavTOCDelegate()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            parser.parse()
            if !delegate.entries.isEmpty {
                return delegate.entries
            }
        }
        if let ncxHref,
           let ncxURL = try? safeURL(forRelativePath: normalizedHref(ncxHref), in: baseDirectory),
           let data = try? Data(contentsOf: ncxURL) {
            let delegate = NCXTOCDelegate()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            parser.parse()
            return delegate.entries
        }
        return []
    }

    private final class NavTOCDelegate: NSObject, XMLParserDelegate {
        var entries: [TOCEntry] = []

        private var inTOCNav = false
        private var olDepth = 0
        private var capturingAnchor = false
        private var anchorHref: String?
        private var anchorTitle = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let tag = localName(elementName, qName)
            if tag == "nav" {
                let type = attributeDict["epub:type"] ?? attributeDict["type"] ?? ""
                inTOCNav = type.split(separator: " ").contains("toc")
                return
            }
            guard inTOCNav else { return }
            switch tag {
            case "ol":
                olDepth += 1
            case "a":
                capturingAnchor = true
                anchorHref = attributeDict["href"]
                anchorTitle = ""
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard inTOCNav, capturingAnchor else { return }
            anchorTitle += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let tag = localName(elementName, qName)
            if tag == "nav" {
                inTOCNav = false
                return
            }
            guard inTOCNav else { return }
            switch tag {
            case "a":
                capturingAnchor = false
                let title = anchorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if let href = anchorHref, !title.isEmpty {
                    entries.append(TOCEntry(href: href, title: title, level: max(1, olDepth)))
                }
            case "ol":
                olDepth = max(0, olDepth - 1)
            default:
                break
            }
        }
    }

    private final class NCXTOCDelegate: NSObject, XMLParserDelegate {
        private struct Pending {
            var title: String?
            var href: String?
            var level: Int
        }

        var entries: [TOCEntry] = []

        private var stack: [Pending] = []
        private var capturingLabel = false
        private var labelText = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let tag = localName(elementName, qName)
            switch tag {
            case "navpoint":
                stack.append(Pending(title: nil, href: nil, level: stack.count + 1))
            case "navlabel":
                capturingLabel = true
                labelText = ""
            case "content":
                if !stack.isEmpty, let src = attributeDict["src"] {
                    stack[stack.count - 1].href = src
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard capturingLabel else { return }
            labelText += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let tag = localName(elementName, qName)
            switch tag {
            case "navlabel":
                capturingLabel = false
                let title = labelText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !stack.isEmpty, !title.isEmpty {
                    stack[stack.count - 1].title = title
                }
            case "navpoint":
                guard !stack.isEmpty else { return }
                let pending = stack.removeLast()
                if let href = pending.href, let title = pending.title {
                    entries.append(TOCEntry(href: href, title: title, level: pending.level))
                }
            default:
                break
            }
        }
    }

    // MARK: - XHTML 文本提取

    private static func extractText(from data: Data) -> ExtractedText {
        let extractor = XHTMLTextExtractor()
        let parser = XMLParser(data: data)
        parser.delegate = extractor
        if parser.parse(), !extractor.paragraphs.isEmpty {
            return ExtractedText(paragraphs: extractor.paragraphs, headings: extractor.headings)
        }
        // 兜底：部分 EPUB 的 XHTML 不是严格 XML
        return ExtractedText(paragraphs: fallbackParagraphs(from: data), headings: [])
    }

    private final class XHTMLTextExtractor: NSObject, XMLParserDelegate {
        var paragraphs: [String] = []
        var headings: [String] = []

        private var buffer = ""
        private var skipDepth = 0

        private static let skipTags: Set<String> = ["script", "style", "head", "title", "svg", "math"]
        private static let headingTags: Set<String> = ["h1", "h2", "h3"]
        private static let blockTags: Set<String> = [
            "p", "div", "h1", "h2", "h3", "h4", "h5", "h6",
            "li", "blockquote", "section", "article", "tr", "body", "ul", "ol", "table", "hr"
        ]

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let tag = localName(elementName, qName)
            if Self.skipTags.contains(tag) {
                skipDepth += 1
                return
            }
            guard skipDepth == 0 else { return }
            if tag == "br" {
                buffer += "\n"
            } else if Self.blockTags.contains(tag) {
                flush(heading: false)
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard skipDepth == 0 else { return }
            buffer += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let tag = localName(elementName, qName)
            if Self.skipTags.contains(tag) {
                if skipDepth > 0 { skipDepth -= 1 }
                return
            }
            guard skipDepth == 0 else { return }
            if Self.blockTags.contains(tag) {
                flush(heading: Self.headingTags.contains(tag))
            }
        }

        private func flush(heading: Bool) {
            let text = buffer
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            buffer = ""
            guard !text.isEmpty else { return }
            paragraphs.append(text)
            if heading {
                headings.append(text)
            }
        }
    }

    private static func fallbackParagraphs(from data: Data) -> [String] {
        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        let withoutScripts = html.replacingOccurrences(
            of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        let withBreaks = withoutScripts.replacingOccurrences(
            of: "</?(p|div|h[1-6]|li|blockquote|br)[^>]*>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        let stripped = withBreaks.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        return decodeEntities(stripped)
            .components(separatedBy: "\n")
            .map { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
            .filter { !$0.isEmpty }
    }

    static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, replacement) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        guard let regex = numericEntityRegex else { return result }
        let ns = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return result }
        let output = NSMutableString(string: result)
        for match in matches.reversed() {
            let token = ns.substring(with: match.range(at: 1))
            let value: UInt32?
            if token.hasPrefix("x") || token.hasPrefix("X") {
                value = UInt32(token.dropFirst(), radix: 16)
            } else {
                value = UInt32(token, radix: 10)
            }
            guard let value,
                  let scalar = Unicode.Scalar(value),
                  !(0xD800...0xDFFF).contains(value) else { continue }
            output.replaceCharacters(in: match.range, with: String(Character(scalar)))
        }
        return output as String
    }

    private static let numericEntityRegex = try? NSRegularExpression(
        pattern: "&#(x[0-9A-Fa-f]+|[0-9]+);"
    )

    private static let namedEntities: [(String, String)] = [
        ("&nbsp;", " "),
        ("&amp;", "&"),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&quot;", "\""),
        ("&apos;", "'"),
        ("&mdash;", "—"),
        ("&ndash;", "–"),
        ("&hellip;", "…"),
        ("&lsquo;", "‘"),
        ("&rsquo;", "’"),
        ("&ldquo;", "“"),
        ("&rdquo;", "”"),
        ("&copy;", "©"),
        ("&reg;", "®"),
        ("&trade;", "™"),
        ("&middot;", "·"),
        ("&bull;", "•"),
        ("&deg;", "°")
    ]
}
