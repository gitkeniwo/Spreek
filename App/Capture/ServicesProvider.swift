import AppKit

/// Handles the "Speak with Spreek" Services menu item (`NSServices` in Info.plist,
/// `NSMessage = speakWithSpreek`).
@MainActor
final class ServicesProvider: NSObject {
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
    }

    @objc func speakWithSpreek(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string) else {
            error.pointee = "Spreek couldn't read text from the selection." as NSString
            return
        }
        model?.speakServiceText(text)
    }
}
