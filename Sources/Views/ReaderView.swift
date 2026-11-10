import SwiftUI
import Combine

struct ReaderView: View {
    let book: Book

    @StateObject private var player = SpeechPlayer()
    @EnvironmentObject private var marksStore: MarksStore
    @EnvironmentObject private var vocabStore: VocabStore
    @EnvironmentObject private var statsStore: StudyStatsStore
    @State private var content: BookContent?
    @State private var loadError: String?
    @State private var autoScroll = true
    @State private var startIndex = 0
    @State private var isLeaving = false
    @State private var showTOC = false
    @State private var showMarks = false
    @State private var showSettings = false
    @State private var pendingScrollParagraph: Int?
    @State private var suppressProgressReset = false
    @AppStorage("reader.fontSize") private var fontSize: Double = 19
    @AppStorage("reader.theme") private var themeRaw: String = ReaderTheme.paper.rawValue
    @AppStorage("reader.rate") private var rateValue: Double = 0.55
    @AppStorage("reader.voiceID") private var voiceID: String = ""
    @AppStorage("reader.chineseVoiceID") private var chineseVoiceID: String = ""
    @AppStorage("reader.loopSentence") private var loopSentence = false
    @State private var scrubIndex: Int?
    @State private var sleepDeadline: Date?
    @State private var sleepRemaining = 0
    @State private var vocabToast: String?
    @State private var practiceSentence: PracticeSentence?
    private let sleepTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var theme: ReaderTheme {
        ReaderTheme(rawValue: themeRaw) ?? .paper
    }

    var body: some View {
        Group {
            if let content {
                reader(content)
            } else if let loadError {
                Text(loadError)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ProgressView()
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .background(theme.background.ignoresSafeArea())
        .environment(\.colorScheme, theme.colorScheme)
        .toolbarColorScheme(theme.colorScheme, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showTOC = true
                } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("目录")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showMarks = true
                } label: {
                    Image(systemName: "bookmark")
                }
                .accessibilityLabel("我的标记")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "textformat.size")
                }
                .accessibilityLabel("阅读设置")
            }
        }
        .sheet(isPresented: $showTOC) {
            if let content {
                TOCSheet(
                    chapters: content.chapters,
                    currentChapterID: currentChapterID(in: content)
                ) { chapter in
                    showTOC = false
                    jump(to: chapter, in: content)
                }
            }
        }
        .sheet(isPresented: $showMarks) {
            if let content {
                MarksSheet(
                    marks: marks,
                    chapters: content.chapters,
                    onSelectBookmark: { bookmark in
                        showMarks = false
                        guard bookmark.sentenceIndex < content.sentences.count else { return }
                        jump(
                            toSentence: bookmark.sentenceIndex,
                            paragraph: bookmark.paragraphIndex,
                            in: content
                        )
                    },
                    onSelectHighlight: { highlight in
                        showMarks = false
                        guard highlight.paragraphIndex < content.paragraphs.count else { return }
                        let sentenceID = content.sentences
                            .first(where: { $0.paragraphIndex >= highlight.paragraphIndex })?.id ?? 0
                        jump(toSentence: sentenceID, paragraph: highlight.paragraphIndex, in: content)
                    },
                    onDeleteBookmark: { marksStore.remove(bookmark: $0, bookID: book.id) },
                    onDeleteHighlight: { marksStore.remove(highlight: $0, bookID: book.id) }
                )
            }
        }
        .sheet(item: $practiceSentence) { sentence in
            ReadAloudPracticeView(sentence: sentence)
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet(
                fontSize: $fontSize,
                themeRaw: $themeRaw,
                rate: Binding(
                    get: { player.rate },
                    set: { player.rate = $0 }
                ),
                voiceID: $voiceID,
                chineseVoiceID: $chineseVoiceID,
                onRestart: { restart() }
            )
        }
        .task {
            do {
                let loaded = try BookParser.load(from: book.url, title: book.title)
                content = loaded
                player.rate = Float(rateValue)
                player.voiceIdentifier = voiceID
                player.chineseVoiceIdentifier = chineseVoiceID
                player.isLoopingCurrentSentence = loopSentence
                player.nowPlayingTitle = book.title
                player.chapterTitleProvider = { sentenceIndex in
                    guard sentenceIndex < loaded.sentences.count else { return "" }
                    let paragraph = loaded.sentences[sentenceIndex].paragraphIndex
                    return loaded.chapters.last(where: { $0.paragraphIndex <= paragraph })?.title ?? ""
                }
                let saved = ReadingProgress.lastSentence(for: book.id) ?? 0
                startIndex = min(max(0, saved), max(0, loaded.sentences.count - 1))
                if startIndex < loaded.sentences.count {
                    ReadingProgress.rememberLastRead(
                        bookID: book.id,
                        bookTitle: book.title,
                        sentenceText: loaded.sentences[startIndex].text
                    )
                }
                // 仅用于开发调试：`SIMCTL_CHILD_AUTO_PLAY=1` 启动时自动朗读
                if ProcessInfo.processInfo.environment["AUTO_PLAY"] == "1" {
                    player.play(from: startIndex, in: loaded.sentences)
                }
                // 仅用于开发调试：`SIMCTL_CHILD_AUTO_OPEN_TOC=1` 启动时直接弹出目录
                if ProcessInfo.processInfo.environment["AUTO_OPEN_TOC"] == "1" {
                    showTOC = true
                }
                // 仅用于开发调试：`SIMCTL_CHILD_AUTO_OPEN_MARKS=1` 启动时直接弹出标记面板
                if ProcessInfo.processInfo.environment["AUTO_OPEN_MARKS"] == "1" {
                    showMarks = true
                }
                // 仅用于开发调试：`SIMCTL_CHILD_AUTO_THEME=night` 强制阅读主题
                if let forcedTheme = ProcessInfo.processInfo.environment["AUTO_THEME"],
                   ReaderTheme(rawValue: forcedTheme) != nil {
                    themeRaw = forcedTheme
                }
                // 仅用于开发调试：`SIMCTL_CHILD_AUTO_OPEN_SETTINGS=1` 启动时直接弹出阅读设置
                if ProcessInfo.processInfo.environment["AUTO_OPEN_SETTINGS"] == "1" {
                    showSettings = true
                }
                // 仅用于开发调试：`SIMCTL_CHILD_AUTO_SLEEP=<分钟>` 启动时设置睡眠定时
                if let minutesText = ProcessInfo.processInfo.environment["AUTO_SLEEP"],
                   let minutes = Double(minutesText) {
                    sleepDeadline = Date().addingTimeInterval(minutes * 60)
                    sleepRemaining = Int(minutes * 60)
                }
            } catch {
                loadError = error.localizedDescription
            }
        }
        .onReceive(sleepTick) { now in
            guard let deadline = sleepDeadline else { return }
            let remaining = Int(deadline.timeIntervalSince(now).rounded(.up))
            guard remaining > 0 else {
                sleepDeadline = nil
                sleepRemaining = 0
                if player.isPlaying || player.currentSentenceIndex != nil {
                    // 定时到点：停止播放但保留阅读进度
                    suppressProgressReset = true
                    player.stop()
                }
                return
            }
            sleepRemaining = remaining
        }
        .onChange(of: player.rate) { _, newValue in
            rateValue = Double(newValue)
        }
        .onChange(of: voiceID) { _, newValue in
            player.voiceIdentifier = newValue
        }
        .onChange(of: chineseVoiceID) { _, newValue in
            player.chineseVoiceIdentifier = newValue
        }
        .onChange(of: loopSentence) { _, newValue in
            player.isLoopingCurrentSentence = newValue
        }
        .onDisappear {
            isLeaving = true
            sleepDeadline = nil
            if startIndex > 0 {
                ReadingProgress.save(startIndex, for: book.id)
            }
            player.stop()
        }
        .overlay(alignment: .top) {
            if let vocabToast {
                Text(vocabToast)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.92), in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var marks: BookMarks {
        marksStore.marks(for: book.id)
    }

    private func reader(_ content: BookContent) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(content.paragraphs) { paragraph in
                        ParagraphTextView(
                            paragraph: paragraph,
                            highlightedSentenceID: player.currentSentenceIndex,
                            highlights: marks.highlights
                                .filter { $0.paragraphIndex == paragraph.id }
                                .map { NSRange(location: $0.location, length: $0.length) },
                            fontSize: CGFloat(fontSize),
                            textColor: theme.textColor,
                            onTapSentence: { sentenceID in
                                autoScroll = true
                                startIndex = sentenceID
                                player.play(from: sentenceID, in: content.sentences)
                            },
                            onHighlight: { range, text in
                                marksStore.toggleHighlight(
                                    bookID: book.id,
                                    paragraphIndex: paragraph.id,
                                    location: range.location,
                                    length: range.length,
                                    text: text
                                )
                            },
                            onAddVocab: { word, sentenceID, sentenceText in
                                let paragraphIndex = sentenceID < content.sentences.count
                                    ? content.sentences[sentenceID].paragraphIndex
                                    : paragraph.id
                                let added = vocabStore.add(
                                    word: word,
                                    sentenceText: sentenceText,
                                    bookID: book.id,
                                    bookTitle: book.title,
                                    sentenceIndex: sentenceID,
                                    paragraphIndex: paragraphIndex
                                )
                                showVocabToast(added ? "已加入生词本" : "已在生词本中")
                                if added {
                                    // 后台补一条释义，复习卡直接可用；失败也无妨
                                    Task {
                                        if let entry = try? await DictionaryService.shared.entry(for: word) {
                                            vocabStore.updateDefinition(for: word, definition: entry.summary)
                                        }
                                    }
                                }
                            }
                        )
                        .id(paragraph.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
            .onAppear {
                // 打开书时回到上次朗读位置（不自动播放）。
                // 延迟到首帧布局完成后再滚动，否则 LazyVStack 里的目标行还不存在。
                guard startIndex > 0, startIndex < content.sentences.count else { return }
                let paragraphIndex = content.sentences[startIndex].paragraphIndex
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    proxy.scrollTo(paragraphIndex, anchor: .center)
                }
            }
            .onChange(of: player.currentSentenceIndex) { _, newValue in
                guard let index = newValue else {
                    // 播放结束或手动停止：清空进度，下次从头开始。
                    // 目录跳转触发的停止不能清空（suppressProgressReset）。
                    if suppressProgressReset {
                        suppressProgressReset = false
                    } else if !isLeaving {
                        startIndex = 0
                        ReadingProgress.clear(for: book.id)
                    }
                    return
                }
                guard index < content.sentences.count else { return }
                startIndex = index
                if player.isPlaying {
                    statsStore.record(.sentenceListened)
                }
                ReadingProgress.save(index, for: book.id)
                ReadingProgress.rememberLastRead(
                    bookID: book.id,
                    bookTitle: book.title,
                    sentenceText: content.sentences[index].text
                )
                guard autoScroll else { return }
                let paragraphIndex = content.sentences[index].paragraphIndex
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(paragraphIndex, anchor: .center)
                }
            }
            .onChange(of: pendingScrollParagraph) { _, newValue in
                guard let paragraphIndex = newValue else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(paragraphIndex, anchor: .top)
                }
                pendingScrollParagraph = nil
            }
            .overlay(alignment: .bottom) {
                playerBar(content)
            }
        }
    }

    private func showVocabToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) {
            vocabToast = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeIn(duration: 0.2)) {
                vocabToast = nil
            }
        }
    }

    private func restart() {
        guard let content else { return }
        startIndex = 0
        ReadingProgress.clear(for: book.id)
        if player.isPlaying || player.currentSentenceIndex != nil {
            player.play(from: 0, in: content.sentences)
        } else {
            pendingScrollParagraph = 0
        }
    }

    // MARK: - 目录

    private func currentChapterID(in content: BookContent) -> Int? {
        let sentenceIndex: Int?
        if let current = player.currentSentenceIndex {
            sentenceIndex = current
        } else if startIndex > 0 {
            sentenceIndex = startIndex
        } else {
            sentenceIndex = nil
        }
        guard let sentenceIndex, sentenceIndex < content.sentences.count else {
            return content.chapters.first?.id
        }
        let paragraphIndex = content.sentences[sentenceIndex].paragraphIndex
        return content.chapters.last(where: { $0.paragraphIndex <= paragraphIndex })?.id
            ?? content.chapters.first?.id
    }

    private func jump(to chapter: Chapter, in content: BookContent) {
        let firstSentenceID = content.sentences
            .first(where: { $0.paragraphIndex >= chapter.paragraphIndex })?.id ?? 0
        jump(toSentence: firstSentenceID, paragraph: chapter.paragraphIndex, in: content)
    }

    /// 跳转到指定句子：播放中从该句继续朗读，未播放时只滚动定位（目录/标记面板共用）。
    private func jump(toSentence sentenceID: Int, paragraph paragraphIndex: Int, in content: BookContent) {
        autoScroll = true

        if player.isPlaying {
            player.play(from: sentenceID, in: content.sentences)
        } else {
            if player.currentSentenceIndex != nil {
                suppressProgressReset = true
                player.stop()
            }
            pendingScrollParagraph = paragraphIndex
        }
        startIndex = sentenceID
        ReadingProgress.save(sentenceID, for: book.id)
        if sentenceID < content.sentences.count {
            ReadingProgress.rememberLastRead(
                bookID: book.id,
                bookTitle: book.title,
                sentenceText: content.sentences[sentenceID].text
            )
        }
    }

    private func playerBar(_ content: BookContent) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if let current = displayIndex(in: content) {
                    Text(scrubIndex != nil
                         ? "跳到第 \(current + 1) / \(content.sentences.count) 句"
                         : "第 \(current + 1) / \(content.sentences.count) 句")
                        .font(.caption)
                        .foregroundStyle(scrubIndex != nil ? Color.orange : Color.secondary)
                }
                Spacer()
                practiceButton(content)
                loopButton
                if sleepRemaining > 0 {
                    Label(sleepCountdownText, systemImage: "moon.zzz.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if content.sentences.count > 1 {
                Slider(
                    value: progressBinding,
                    in: 0...Double(content.sentences.count - 1),
                    step: 1
                ) { editing in
                    guard !editing, let target = scrubIndex else { return }
                    scrubIndex = nil
                    guard target >= 0, target < content.sentences.count else { return }
                    jump(
                        toSentence: target,
                        paragraph: content.sentences[target].paragraphIndex,
                        in: content
                    )
                }
                .tint(.orange)
                .accessibilityLabel("朗读进度")
            }
            HStack(spacing: 0) {
                bookmarkButton(content)
                    .frame(maxWidth: .infinity)
                stepButton(backward: true, in: content)
                    .frame(maxWidth: .infinity)
                playButton(content)
                stepButton(backward: false, in: content)
                    .frame(maxWidth: .infinity)
                sleepMenu
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private func displayIndex(in content: BookContent) -> Int? {
        for index in [scrubIndex, player.currentSentenceIndex, startIndex > 0 ? startIndex : nil] {
            if let index, index >= 0, index < content.sentences.count {
                return index
            }
        }
        return nil
    }

    private var progressBinding: Binding<Double> {
        Binding(
            get: { Double(scrubIndex ?? player.currentSentenceIndex ?? startIndex) },
            set: { scrubIndex = Int($0.rounded()) }
        )
    }

    private var loopButton: some View {
        Button {
            loopSentence.toggle()
        } label: {
            Image(systemName: "repeat.1")
                .font(.caption.weight(.semibold))
                .foregroundStyle(loopSentence ? Color.orange : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    loopSentence ? Color.orange.opacity(0.14) : Color.clear,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(loopSentence ? "关闭单句循环" : "单句循环")
    }

    private func practiceButton(_ content: BookContent) -> some View {
        let target = player.currentSentenceIndex ?? startIndex
        let enabled = target >= 0 && target < content.sentences.count

        return Button {
            guard enabled else { return }
            if player.isPlaying || player.currentSentenceIndex != nil {
                // 停朗读但保留进度，跟读页接管音频
                suppressProgressReset = true
                player.stop()
            }
            practiceSentence = PracticeSentence(
                text: content.sentences[target].text,
                bookTitle: book.title
            )
        } label: {
            Image(systemName: "waveform.badge.mic")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("跟读练习")
    }

    private func playButton(_ content: BookContent) -> some View {
        Button {
            autoScroll = true
            player.togglePlayback(sentences: content.sentences, startAt: startIndex)
        } label: {
            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.orange)
        }
        .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
    }

    private func stepButton(backward: Bool, in content: BookContent) -> some View {
        Button {
            let base = player.currentSentenceIndex ?? startIndex
            let target = min(max(0, base + (backward ? -1 : 1)), max(0, content.sentences.count - 1))
            jump(toSentence: target, paragraph: content.sentences[target].paragraphIndex, in: content)
        } label: {
            Image(systemName: backward ? "backward.end.fill" : "forward.end.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel(backward ? "上一句" : "下一句")
    }

    private var sleepMenu: some View {
        Menu {
            ForEach([15, 30, 60], id: \.self) { minutes in
                Button("\(minutes) 分钟后停止") {
                    setSleepTimer(minutes: minutes)
                }
            }
            if sleepDeadline != nil {
                Button("关闭定时", role: .destructive) {
                    setSleepTimer(minutes: nil)
                }
            }
        } label: {
            Image(systemName: sleepDeadline == nil ? "moon.zzz" : "moon.zzz.fill")
                .font(.title3)
                .foregroundStyle(sleepDeadline == nil ? Color.secondary : Color.orange)
        }
        .accessibilityLabel("睡眠定时")
    }

    private func setSleepTimer(minutes: Int?) {
        if let minutes {
            sleepDeadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
            sleepRemaining = minutes * 60
        } else {
            sleepDeadline = nil
            sleepRemaining = 0
        }
    }

    private var sleepCountdownText: String {
        String(format: "%d:%02d 后停止", sleepRemaining / 60, sleepRemaining % 60)
    }

    private func bookmarkButton(_ content: BookContent) -> some View {
        let target = player.currentSentenceIndex ?? startIndex
        let isBookmarked = target >= 0 && target < content.sentences.count
            && marks.bookmarks.contains { $0.sentenceIndex == target }

        return Button {
            guard target >= 0, target < content.sentences.count else { return }
            let sentence = content.sentences[target]
            marksStore.toggleBookmark(
                bookID: book.id,
                sentenceIndex: sentence.id,
                paragraphIndex: sentence.paragraphIndex,
                text: sentence.text
            )
        } label: {
            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                .font(.title3)
                .foregroundStyle(isBookmarked ? .orange : .secondary)
        }
        .accessibilityLabel(isBookmarked ? "取消书签" : "收藏本句")
    }
}
