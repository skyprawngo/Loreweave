import SwiftUI
import AppKit

struct MarkdownPreviewView: View {
    let source: String
    let fontName: String
    let fontSize: CGFloat
    let lineHeightMultiple: CGFloat
    let letterSpacing: CGFloat
    @State private var parsed: AttributedString?
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.get("editor.markdown.readOnly"))
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing).padding(8)
            if let parsed {
                MarkdownPreviewText(parsed: parsed, fontName: fontName, fontSize: fontSize,
                    lineHeightMultiple: lineHeightMultiple, letterSpacing: letterSpacing)
            } else if let failure {
                Text(failure).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppColors.textEditorBackground)
        .task(id: source) {
            failure = nil
            let worker = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let result = try MarkdownPreviewRenderer.parse(source)
                try Task.checkCancellation()
                return result
            }
            do {
                let value = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled else { return }
                parsed = value
            } catch {
                guard !Task.isCancelled else { return }
                failure = error.localizedDescription
            }
        }
    }
}

private struct MarkdownPreviewText: NSViewRepresentable {
    let parsed: AttributedString
    let fontName: String
    let fontSize: CGFloat
    let lineHeightMultiple: CGFloat
    let letterSpacing: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let text = MarkdownPreviewTextView(usingTextLayoutManager: true)
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        text.textContainerInset = NSSize(width: 16, height: 10)
        text.setAccessibilityLabel(L10n.get("editor.markdown.preview"))
        scroll.documentView = text
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let rendered = MarkdownPreviewRenderer.render(parsed, font: font, color: AppColors.nsEditorText,
            lineHeightMultiple: lineHeightMultiple, letterSpacing: letterSpacing)
        guard text.textStorage?.isEqual(to: rendered) != true else { return }
        let origin = scroll.contentView.bounds.origin
        text.textStorage?.setAttributedString(rendered)
        scroll.contentView.scroll(to: origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

private final class MarkdownPreviewTextView: NSTextView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}
