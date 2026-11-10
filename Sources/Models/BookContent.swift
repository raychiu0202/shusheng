import Foundation

/// 段落内的一个句子片段，range 为段落文本中的 UTF-16 范围
struct SentenceSpan: Identifiable {
    let id: Int          // 全书扁平句子序号
    let range: NSRange
}

struct Paragraph: Identifiable {
    let id: Int          // 段落序号
    let text: String
    let sentenceSpans: [SentenceSpan]
}

struct Sentence: Identifiable {
    let id: Int          // 全书扁平句子序号
    let text: String
    let paragraphIndex: Int
}

struct Chapter: Identifiable {
    let id: Int                 // 目录序号
    let title: String
    let level: Int              // 嵌套层级，1 为顶级
    let paragraphIndex: Int     // 章节起始段落
}

struct BookContent {
    let paragraphs: [Paragraph]
    let sentences: [Sentence]
    let chapters: [Chapter]
}
