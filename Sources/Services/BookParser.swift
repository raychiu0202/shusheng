import Foundation
import NaturalLanguage

enum BookParser {

    static func load(from url: URL, title: String) throws -> BookContent {
        switch url.pathExtension.lowercased() {
        case "epub":
            let sections = try EPUBParser.sections(from: url)
            return build(
                sections: sections.map { (title: $0.title, level: $0.level, paragraphs: $0.paragraphs) },
                firstTitle: title
            )
        case "mobi", "prc", "azw", "azw3":
            let sections = try MOBIParser.sections(from: url)
            return build(
                sections: sections.map { (title: $0.title, level: $0.level, paragraphs: $0.paragraphs) },
                firstTitle: title
            )
        default:
            var encoding = String.Encoding.utf8
            let raw = try String(contentsOf: url, usedEncoding: &encoding)
            return build(sections: textSections(from: raw, firstTitle: title), firstTitle: title)
        }
    }

    // MARK: - TXT 章节切分

    private static let headingPatterns: [NSRegularExpression] = [
        #"(?i)^\s*(chapter|part|book|prologue|epilogue|preface|introduction)\b"#,
        #"^\s*第\s*[0-9零一二三四五六七八九十百千]+\s*[章节回卷篇]"#
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    private static func isChapterHeading(_ line: String) -> Bool {
        guard line.count <= 80 else { return false }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return headingPatterns.contains { $0.firstMatch(in: line, options: [], range: range) != nil }
    }

    private static func textSections(
        from raw: String,
        firstTitle: String
    ) -> [(title: String?, level: Int, paragraphs: [String])] {
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var sections: [(title: String?, level: Int, paragraphs: [String])] = [(firstTitle, 1, [])]
        for line in lines {
            if isChapterHeading(line) {
                sections.append((line, 1, [line]))
            } else {
                sections[sections.count - 1].paragraphs.append(line)
            }
        }
        // 首行就是章节标题时，丢掉空的前置小节
        if sections.count > 1, sections[0].paragraphs.isEmpty {
            sections.removeFirst()
        }
        return sections
    }

    // MARK: - 统一构建

    private static func build(
        sections: [(title: String?, level: Int, paragraphs: [String])],
        firstTitle: String
    ) -> BookContent {
        var paragraphs: [Paragraph] = []
        var sentences: [Sentence] = []
        var chapters: [Chapter] = []

        for section in sections {
            let startParagraph = paragraphs.count
            for line in section.paragraphs {
                let paragraphIndex = paragraphs.count
                var spans: [SentenceSpan] = []
                for range in sentenceRanges(in: line) {
                    let nsRange = NSRange(range, in: line)
                    guard nsRange.location != NSNotFound, nsRange.length > 0 else { continue }
                    let text = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    let sentence = Sentence(id: sentences.count, text: text, paragraphIndex: paragraphIndex)
                    sentences.append(sentence)
                    spans.append(SentenceSpan(id: sentence.id, range: nsRange))
                }
                paragraphs.append(Paragraph(id: paragraphIndex, text: line, sentenceSpans: spans))
            }

            guard paragraphs.count > startParagraph else { continue }
            let trimmedTitle = section.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let chapterTitle: String
            if !trimmedTitle.isEmpty {
                chapterTitle = trimmedTitle
            } else if chapters.isEmpty {
                chapterTitle = firstTitle
            } else {
                chapterTitle = "第 \(chapters.count + 1) 节"
            }
            chapters.append(Chapter(
                id: chapters.count,
                title: chapterTitle,
                level: max(1, section.level),
                paragraphIndex: startParagraph
            ))
        }

        guard !chapters.isEmpty else {
            return BookContent(paragraphs: [], sentences: [], chapters: [])
        }
        if chapters[0].paragraphIndex != 0 {
            var rebuilt: [Chapter] = [Chapter(id: 0, title: firstTitle, level: 1, paragraphIndex: 0)]
            rebuilt.append(contentsOf: chapters.map { Chapter(id: 0, title: $0.title, level: $0.level, paragraphIndex: $0.paragraphIndex) })
            chapters = rebuilt.enumerated().map { Chapter(id: $0.offset, title: $0.element.title, level: $0.element.level, paragraphIndex: $0.element.paragraphIndex) }
        }
        return BookContent(paragraphs: paragraphs, sentences: sentences, chapters: chapters)
    }

    // MARK: - 句子切分

    private static func sentenceRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            ranges.append(range)
            return true
        }
        // 没有识别出句子时（比如单个单词），整段作为一个句子
        if ranges.isEmpty, !text.isEmpty {
            ranges.append(text.startIndex..<text.endIndex)
        }
        return ranges
    }
}
