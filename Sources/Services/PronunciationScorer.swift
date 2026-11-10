import Foundation

/// 跟读评分：目标句与识别结果按词对齐，输出 0–100 分和逐词状态。
enum PronunciationScorer {

    static func score(target: String, transcript: String) -> ReadAloudResult {
        let targetTokens = displayTokens(target)
        let targetKeys = targetTokens.map(normalize)
        let spokenKeys = normalizeTokens(transcript)

        guard !targetTokens.isEmpty else {
            return ReadAloudResult(score: 0, tokens: [], transcript: transcript)
        }
        guard !spokenKeys.isEmpty else {
            let tokens = targetTokens.map { ReadAloudToken(word: $0, status: .missing) }
            return ReadAloudResult(score: 0, tokens: tokens, transcript: transcript)
        }

        // LCS 对齐：命中的目标词下标
        let matched = lcsMatches(targetKeys, spokenKeys)
        var statuses = Array(repeating: TokenStatus.missing, count: targetTokens.count)
        var matchedSpoken = Set<Int>()
        var matchedTarget = Set<Int>()
        for (targetIndex, spokenIndex) in matched {
            statuses[targetIndex] = .correct
            matchedSpoken.insert(spokenIndex)
            matchedTarget.insert(targetIndex)
        }

        // 未命中的词按编辑距离相似度配对，视为「识别偏差」
        let freeTargets = targetTokens.indices.filter { !matchedTarget.contains($0) }
        var freeSpoken = spokenKeys.indices.filter { !matchedSpoken.contains($0) }
        for targetIndex in freeTargets {
            guard !freeSpoken.isEmpty else { break }
            var bestIndex: Int?
            var bestSimilarity = 0.0
            for spokenIndex in freeSpoken {
                let similarity = similarity(targetKeys[targetIndex], spokenKeys[spokenIndex])
                if similarity > bestSimilarity {
                    bestSimilarity = similarity
                    bestIndex = spokenIndex
                }
            }
            if bestSimilarity >= 0.75, let bestIndex,
               let position = freeSpoken.firstIndex(of: bestIndex) {
                statuses[targetIndex] = .misrecognized
                freeSpoken.remove(at: position)
            }
        }

        let correctCount = statuses.reduce(0) { $0 + ($1 == .correct ? 1 : 0) }
        let nearCount = statuses.reduce(0) { $0 + ($1 == .misrecognized ? 1 : 0) }
        let extraCount = freeSpoken.count
        let denominator = max(1, targetTokens.count + extraCount)
        let raw = (Double(correctCount) + 0.6 * Double(nearCount)) / Double(denominator)
        let score = Int((raw * 100).rounded())
        let tokens = zip(targetTokens, statuses).map {
            ReadAloudToken(word: $0.0, status: $0.1)
        }
        return ReadAloudResult(
            score: min(100, max(0, score)),
            tokens: tokens,
            transcript: transcript
        )
    }

    // MARK: - 归一化

    private static func displayTokens(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).compactMap { raw in
            let trimmed = String(raw).trimmingCharacters(in: .punctuationCharacters)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private static func normalizeTokens(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
    }

    static func normalize(_ word: String) -> String {
        let lowered = word.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "")
            .replacingOccurrences(of: "'", with: "")
        let scalars = lowered.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    // MARK: - 对齐

    private static func lcsMatches(_ target: [String], _ spoken: [String]) -> [(Int, Int)] {
        guard !target.isEmpty, !spoken.isEmpty else { return [] }
        var dp = Array(
            repeating: Array(repeating: 0, count: spoken.count + 1),
            count: target.count + 1
        )
        for i in 1...target.count {
            for j in 1...spoken.count {
                if target[i - 1] == spoken[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }
        var matches: [(Int, Int)] = []
        var i = target.count
        var j = spoken.count
        while i > 0, j > 0 {
            if target[i - 1] == spoken[j - 1] {
                matches.append((i - 1, j - 1))
                i -= 1
                j -= 1
            } else if dp[i - 1][j] >= dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return matches.reversed()
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty || !rhs.isEmpty else { return 1 }
        let distance = levenshtein(lhs, rhs)
        return 1 - Double(distance) / Double(max(lhs.count, rhs.count))
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
