import CoreTransferable
import SpreekCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Library sentences dragged inside the dashboard (declared in Info.plist).
    static let spreekSentenceIDs = UTType(exportedAs: "nl.spreek.sentence-ids")
}

/// Drag payload: the persistent IDs of one row or the whole multi-selection.
struct SentenceDrag: Codable, Transferable {
    let ids: [PersistentIdentifier]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .spreekSentenceIDs)
    }

    /// The sentences that still exist.
    @MainActor
    func sentences(in context: ModelContext) -> [Sentence] {
        ids.compactMap { context.model(for: $0) as? Sentence }.filter { !$0.isDeleted }
    }
}

/// What a sidebar drop does.
enum SentenceDropAction {
    case move(Folder?)
    case tag(Tag)
}

extension AppModel {
    /// Applies a sidebar drop. A folder's language wins over each sentence's detected one.
    @discardableResult
    func handleDrop(_ drags: [SentenceDrag], _ action: SentenceDropAction) -> Bool {
        let sentences = drags.flatMap { $0.sentences(in: library.context) }
        guard !sentences.isEmpty else { return false }
        switch action {
        case .move(let folder): library.move(sentences, to: folder)
        case .tag(let tag): library.addTag(tag, to: sentences)
        }
        return true
    }
}

extension View {
    /// Accepts dragged sentences; `isTargeted` drives the hover highlight.
    func sentenceDropDestination(
        _ model: AppModel, action: @escaping () -> SentenceDropAction, isTargeted: Binding<Bool>
    ) -> some View {
        dropDestination(for: SentenceDrag.self) { drags, _ in
            model.handleDrop(drags, action())
        } isTargeted: { isTargeted.wrappedValue = $0 }
    }
}

/// Drop-target highlight: accent tint fill + accent ring.
struct DropHighlight: ViewModifier {
    let isActive: Bool
    var cornerRadius: CGFloat = 9

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(Color.accentColor.opacity(isActive ? 0.18 : 0)))
            .overlay(shape.strokeBorder(Color.accentColor.opacity(isActive ? 1 : 0), lineWidth: 2))
            .animation(.easeOut(duration: 0.12), value: isActive)
    }
}

/// Drag preview: the row's badge and text, plus a count badge when dragging several.
struct SentenceDragPreview: View {
    let sentence: Sentence
    let count: Int
    var badgeStyle: LanguageBadge.Style = .code

    var body: some View {
        HStack(spacing: 8) {
            LanguageBadge(language: sentence.effectiveLanguage, style: badgeStyle, size: .s)
            Text(sentence.text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.fg)
                .lineLimit(1)
                .frame(maxWidth: 240, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Color.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.separator, lineWidth: Metrics.hairline))
        .overlay(alignment: .topTrailing) {
            if count > 1 {
                Text("\(count)")
                    .font(.spreekRounded(size: 11, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Capsule().fill(Color.accentColor))
                    .offset(x: 8, y: -8)
            }
        }
        .padding(10)
    }
}
