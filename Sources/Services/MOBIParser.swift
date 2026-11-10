import Foundation

/// 解析 MOBI / PRC（PalmDOC 压缩，无 DRM）。
/// 不支持 HUFF/CDIC 压缩与 AZW3/KF8。
enum MOBIParser {

    enum MOBIError: LocalizedError {
        case badStructure
        case drmProtected
        case unsupportedCompression
        case kf8Unsupported

        var errorDescription: String? {
            switch self {
            case .badStructure:
                return "无法解析该 MOBI 文件（结构不完整或格式不受支持）"
            case .drmProtected:
                return "这本书带 DRM 版权保护，无法解析"
            case .unsupportedCompression:
                return "暂不支持该 MOBI 的压缩方式（HUFF/CDIC）"
            case .kf8Unsupported:
                return "暂不支持 AZW3/KF8 格式，请转换成 MOBI 后再导入"
            }
        }
    }

    static func sections(from url: URL) throws -> [EPUBSection] {
        let data = try Data(contentsOf: url)
        let html = try extractHTML(from: data)
        let lines = taggedLines(from: html)
        let sections = buildSections(from: lines)
        guard !sections.isEmpty else { throw MOBIError.badStructure }
        return sections
    }

    // MARK: - PDB / PalmDOC / MOBI 头

    private static func extractHTML(from data: Data) throws -> String {
        guard data.count >= 78 else { throw MOBIError.badStructure }
        let type = String(data: data[60..<64], encoding: .ascii) ?? ""
        guard type == "BOOK" || type == "TEXt" else { throw MOBIError.badStructure }

        let recordCount = Int(be16(data, 76))
        let tableEnd = 78 + recordCount * 8
        guard recordCount > 1, data.count >= tableEnd else { throw MOBIError.badStructure }

        var offsets: [Int] = []
        offsets.reserveCapacity(recordCount + 1)
        for i in 0..<recordCount {
            let offset = Int(be32(data, 78 + i * 8))
            guard offset >= tableEnd, offset <= data.count else { throw MOBIError.badStructure }
            offsets.append(offset)
        }
        offsets.append(data.count)

        let rec0 = offsets[0]
        guard rec0 + 16 <= data.count else { throw MOBIError.badStructure }
        let compression = be16(data, rec0)
        let textLength = Int(be32(data, rec0 + 4))
        let textRecordCount = Int(be16(data, rec0 + 8))
        let recordSize = max(1, Int(be16(data, rec0 + 10)))
        let encryption = be16(data, rec0 + 12)
        guard encryption == 0 else { throw MOBIError.drmProtected }

        var encoding: String.Encoding = .windowsCP1252
        let mobiStart = rec0 + 16
        if data.count >= mobiStart + 24,
           String(data: data[mobiStart..<mobiStart + 4], encoding: .ascii) == "MOBI" {
            let codePage = be32(data, mobiStart + 12)
            let version = be32(data, mobiStart + 20)
            if version >= 8 && textLength == 0 { throw MOBIError.kf8Unsupported }
            if codePage == 65001 { encoding = .utf8 }
        }

        guard compression == 1 || compression == 2 else { throw MOBIError.unsupportedCompression }

        let available = recordCount - 1
        let count = min(max(0, textRecordCount), available)
        guard count > 0 else { throw MOBIError.badStructure }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(textLength > 0 ? textLength : 4096 * count)
        for i in 1...count {
            let start = offsets[i]
            let end = offsets[i + 1]
            guard end > start, end <= data.count else { continue }
            let record = data.subdata(in: start..<end)
            let text: [UInt8]
            if compression == 2 {
                text = palmdocDecompress(record)
            } else {
                text = [UInt8](record)
            }
            // 每条记录尾部可能带 trailing entries（记录边界填充/多字节重叠数据），
            // 正文长度由 PalmDOC 头的 recordSize 声明，超出部分必须丢弃，否则正文会出现乱码。
            if text.count > recordSize {
                bytes.append(contentsOf: text[0..<recordSize])
            } else {
                bytes.append(contentsOf: text)
            }
        }
        if textLength > 0, bytes.count > textLength {
            bytes.removeLast(bytes.count - textLength)
        }
        let html = String(bytes: bytes, encoding: encoding)
            ?? String(bytes: bytes, encoding: .utf8)
            ?? String(bytes: bytes, encoding: .isoLatin1)
            ?? ""
        guard !html.isEmpty else { throw MOBIError.badStructure }
        return html
    }

    // MARK: - PalmDOC (LZ77) 解压

    private static func palmdocDecompress(_ record: Data) -> [UInt8] {
        let input = [UInt8](record)
        var output: [UInt8] = []
        output.reserveCapacity(input.count * 4)
        var i = 0
        while i < input.count {
            let b = input[i]
            if b == 0 {
                output.append(0)
                i += 1
            } else if b <= 8 {
                // 0x01–0x08：后面跟着 b 个原样字节
                let start = i + 1
                let end = min(input.count, start + Int(b))
                if start < end { output.append(contentsOf: input[start..<end]) }
                i = end
            } else if b <= 0x7F {
                output.append(b)
                i += 1
            } else if b <= 0xBF {
                // 0x80–0xBF：两字节表示「回溯距离 + 长度」
                guard i + 1 < input.count else { break }
                let pair = (Int(b) << 8) | Int(input[i + 1])
                let distance = (pair >> 3) & 0x07FF
                let length = (pair & 0x07) + 3
                i += 2
                guard distance > 0, distance <= output.count else { continue }
                let start = output.count - distance
                for k in 0..<length {
                    output.append(output[start + k])
                }
            } else {
                // 0xC0–0xFF：空格 + (b ^ 0x80)
                output.append(0x20)
                output.append(b ^ 0x80)
                i += 1
            }
        }
        return output
    }

    // MARK: - HTML → 带标题标注的行

    private struct Line {
        let text: String
        let headingLevel: Int?
    }

    private static func taggedLines(from html: String) -> [Line] {
        var source = html
        if source.hasPrefix("\u{FEFF}") { source.removeFirst() }
        // 整段丢弃 script / style / head / title
        source = source.replacingOccurrences(
            of: "(?is)<(script|style|head|title)[^>]*>.*?</\\1>",
            with: " ",
            options: .regularExpression
        )

        guard let tagRegex = try? NSRegularExpression(pattern: "<[^>]*>") else { return [] }
        let ns = source as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        var lines: [Line] = []
        var buffer = ""
        var currentHeading: Int?
        var skipDepth = 0
        var cursor = 0

        func flush() {
            let decoded = EPUBParser.decodeEntities(buffer)
            buffer = ""
            let parts = decoded
                .components(separatedBy: .newlines)
                .map { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
            for part in parts where !part.isEmpty {
                lines.append(Line(text: part, headingLevel: currentHeading))
            }
        }

        tagRegex.enumerateMatches(in: source, options: [], range: fullRange) { match, _, _ in
            guard let match else { return }
            if match.range.location > cursor, skipDepth == 0 {
                buffer += ns.substring(with: NSRange(
                    location: cursor,
                    length: match.range.location - cursor
                ))
            }
            cursor = match.range.location + match.range.length

            let (name, closing) = tagName(ns.substring(with: match.range))
            if name == "script" || name == "style" || name == "title" {
                if closing {
                    skipDepth = max(0, skipDepth - 1)
                } else {
                    skipDepth += 1
                }
                return
            }
            guard skipDepth == 0 else { return }

            switch name {
            case "br":
                buffer += "\n"
            case "mbp:pagebreak":
                flush()
            case "h1", "h2", "h3":
                if closing {
                    flush()
                    currentHeading = nil
                } else {
                    flush()
                    currentHeading = Int(name.suffix(1)) ?? 1
                }
            default:
                if Self.blockTags.contains(name) {
                    flush()
                }
            }
        }

        if cursor < ns.length, skipDepth == 0 {
            buffer += ns.substring(from: cursor)
        }
        flush()
        return lines
    }

    private static let blockTags: Set<String> = [
        "p", "div", "li", "ul", "ol", "blockquote", "section", "article",
        "table", "tr", "td", "th", "body", "hr", "pre", "h4", "h5", "h6"
    ]

    private static func tagName(_ token: String) -> (name: String, closing: Bool) {
        var s = token
        if s.hasPrefix("<") { s.removeFirst() }
        if s.hasSuffix(">") { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        var closing = false
        if s.hasPrefix("/") {
            closing = true
            s.removeFirst()
        }
        let name = s
            .split(whereSeparator: { $0.isWhitespace || $0 == "/" })
            .first
            .map(String.init)?
            .lowercased() ?? ""
        return (name, closing)
    }

    private static func buildSections(from lines: [Line]) -> [EPUBSection] {
        var sections: [EPUBSection] = []
        var paragraphs: [String] = []
        var title: String?
        var level = 1

        func flushSection() {
            guard !paragraphs.isEmpty else { return }
            sections.append(EPUBSection(title: title, level: level, paragraphs: paragraphs))
            paragraphs = []
            title = nil
            level = 1
        }

        for line in lines {
            if let headingLevel = line.headingLevel {
                flushSection()
                title = line.text
                level = headingLevel
                paragraphs = [line.text]
            } else {
                paragraphs.append(line.text)
            }
        }
        flushSection()
        return sections
    }

    // MARK: - 字节读取

    private static func be16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    private static func be32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }
}
