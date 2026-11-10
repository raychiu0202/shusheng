import SwiftUI

@main
struct EnglishReaderApp: App {
    @StateObject private var marksStore = MarksStore()
    @StateObject private var vocabStore = VocabStore()
    @StateObject private var speakingStore = SpeakingStore()
    @StateObject private var studyStatsStore = StudyStatsStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(marksStore)
                .environmentObject(vocabStore)
                .environmentObject(speakingStore)
                .environmentObject(studyStatsStore)
                .preferredColorScheme(.light)
        }
    }
}
