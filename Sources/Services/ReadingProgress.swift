import Foundation

enum ReadingProgress {
    private static let prefix = "readingProgress."
    private static let lastBookIDKey = "readingLastBookID"
    private static let lastBookTitleKey = "readingLastBookTitle"
    private static let lastSentenceTextKey = "readingLastSentenceText"

    static var lastBookID: String? {
        UserDefaults.standard.string(forKey: lastBookIDKey)
    }

    static var lastBookTitle: String? {
        UserDefaults.standard.string(forKey: lastBookTitleKey)
    }

    static var lastSentenceText: String? {
        UserDefaults.standard.string(forKey: lastSentenceTextKey)
    }

    /// 记录「上次读到哪本书的哪句话」，供口语页取跟读素材。
    /// 只记录英文句子（双语书里的中文句子不用作英文跟读素材）。
    static func rememberLastRead(bookID: String, bookTitle: String, sentenceText: String?) {
        let defaults = UserDefaults.standard
        defaults.set(bookID, forKey: lastBookIDKey)
        defaults.set(bookTitle, forKey: lastBookTitleKey)
        if let sentenceText, isEnglishSentence(sentenceText) {
            defaults.set(sentenceText, forKey: lastSentenceTextKey)
        }
    }

    /// 至少 3 个拉丁字母且不含中日韩字符
    static func isEnglishSentence(_ text: String) -> Bool {
        var latinCount = 0
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value) {
                return false
            }
            if (65...90).contains(value) || (97...122).contains(value) {
                latinCount += 1
            }
        }
        return latinCount >= 3
    }

    static func lastSentence(for bookID: String) -> Int? {
        let value = UserDefaults.standard.integer(forKey: prefix + bookID)
        return value == 0 ? nil : value
    }

    static func save(_ sentenceIndex: Int, for bookID: String) {
        UserDefaults.standard.set(sentenceIndex, forKey: prefix + bookID)
    }

    static func clear(for bookID: String) {
        UserDefaults.standard.removeObject(forKey: prefix + bookID)
    }
}
