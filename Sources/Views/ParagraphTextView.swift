import SwiftUI
import UIKit

/// 段落文本视图：支持点击任意句子开始朗读，长按选中文字后追加「高亮」操作。
/// SwiftUI 的 Text 无法获取点击位置/选区，因此用 UITextView 实现。
struct ParagraphTextView: UIViewRepresentable {
    let paragraph: Paragraph
    let highlightedSentenceID: Int?
    let highlights: [NSRange]
    let fontSize: CGFloat
    let textColor: UIColor
    let onTapSentence: (Int) -> Void
    let onHighlight: (NSRange, String) -> Void
    let onAddVocab: (String, Int, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.dataDetectorTypes = []
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        textView.addGestureRecognizer(tap)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        textView.attributedText = attributedText()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitting.height))
    }

    private func attributedText() -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = fontSize * 0.37

        let attributed = NSMutableAttributedString(
            string: paragraph.text,
            attributes: [
                .font: UIFont.systemFont(ofSize: fontSize),
                .foregroundColor: textColor,
                .paragraphStyle: style
            ]
        )

        let fullRange = NSRange(location: 0, length: (paragraph.text as NSString).length)

        // 用户高亮：黄色
        for nsRange in highlights {
            let clamped = NSIntersectionRange(nsRange, fullRange)
            guard clamped.length > 0 else { continue }
            attributed.addAttribute(
                .backgroundColor,
                value: UIColor.systemYellow.withAlphaComponent(0.4),
                range: clamped
            )
        }

        // 正在朗读的句子：橙色，覆盖用户高亮
        if let highlighted = highlightedSentenceID,
           let span = paragraph.sentenceSpans.first(where: { $0.id == highlighted }) {
            attributed.addAttribute(
                .backgroundColor,
                value: UIColor.systemOrange.withAlphaComponent(0.35),
                range: span.range
            )
        }
        return attributed
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ParagraphTextView

        init(parent: ParagraphTextView) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = gesture.view as? UITextView else { return }
            // 有选区时不拦截（用户在长按选择）
            guard textView.selectedRange.length == 0 else { return }

            let point = gesture.location(in: textView)
            let location = CGPoint(
                x: point.x - textView.textContainerInset.left,
                y: point.y - textView.textContainerInset.top
            )
            guard let position = textView.closestPosition(to: location) else { return }
            let characterIndex = textView.offset(from: textView.beginningOfDocument, to: position)

            let spans = parent.paragraph.sentenceSpans
            let tapped = spans.first(where: { NSLocationInRange(characterIndex, $0.range) })
                ?? spans.last(where: { $0.range.location <= characterIndex })
                ?? spans.first
            if let tapped {
                parent.onTapSentence(tapped.id)
            }
        }

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0 else {
                return UIMenu(children: suggestedActions)
            }
            let selectedText = (textView.text as NSString).substring(with: range)
            let spans = parent.paragraph.sentenceSpans
            let span = spans.first(where: { NSLocationInRange(range.location, $0.range) })
                ?? spans.last(where: { $0.range.location <= range.location })
            let sentenceText = span.map {
                (parent.paragraph.text as NSString).substring(with: $0.range)
            } ?? selectedText

            let vocabAction = UIAction(
                title: "加入生词本",
                image: UIImage(systemName: "character.book.closed")
            ) { [weak self] _ in
                guard let self else { return }
                self.parent.onAddVocab(
                    selectedText.trimmingCharacters(in: .whitespacesAndNewlines),
                    span?.id ?? 0,
                    sentenceText
                )
                textView.selectedRange = NSRange(location: 0, length: 0)
            }
            let highlightAction = UIAction(
                title: "高亮",
                image: UIImage(systemName: "highlighter")
            ) { [weak self] _ in
                guard let self else { return }
                self.parent.onHighlight(range, selectedText)
                textView.selectedRange = NSRange(location: 0, length: 0)
            }
            return UIMenu(children: [vocabAction, highlightAction] + suggestedActions)
        }
    }
}
