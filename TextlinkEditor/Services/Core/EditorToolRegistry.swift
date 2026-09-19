import AppKit

/// A tool is declared once. Settings, keyboard routing, and toolbar lists consume
/// this catalog; merely opening the settings never executes a tool.
protocol EditorToolTarget: AnyObject {
    func runTool(_ definition: EditorToolDefinition)
    func toolFormat(_ kind: String)
    func toolAssistant(_ titleKey: String)
    func toolPresent(_ control: String)
    func toolToggleInline()
    func toolAttachSelection()
}

struct EditorToolDefinition: Identifiable {
    enum Category: String { case edit, view, ai }
    enum Impact { case text, presentation, selection, request }
    let id: String
    let titleKey: String
    let category: Category
    let impact: Impact
    var key: String = ""
    var modifiers: NSEvent.ModifierFlags = []
    let operation: (EditorToolTarget) -> Void
}

enum EditorToolRegistry {
    static let didRegister = Notification.Name("editorToolsDidRegister")
    private(set) static var tools: [EditorToolDefinition] = [
        tool("format.bold", "editor.bold", .edit, .text) { $0.toolFormat("bold") },
        tool("format.italic", "editor.italic", .edit, .text) { $0.toolFormat("italic") },
        tool("format.boldItalic", "toolbar.boldItalic", .edit, .text) { $0.toolFormat("boldItalic") },
        tool("format.underline", "editor.underline", .edit, .text) { $0.toolFormat("underline") },
        tool("format.strikethrough", "editor.strikethrough", .edit, .text) { $0.toolFormat("strikethrough") },
        tool("display.markdownPreview", "editor.markdown.toggle", .view, .presentation) { $0.toolPresent("markdownPreview") },
        tool("display.font", "settings.editor.fontName", .view, .presentation) { $0.toolPresent("font") },
        tool("display.fontSize", "editor.fontSize", .view, .presentation) { $0.toolPresent("fontSize") },
        tool("display.lineSpacing", "editor.lineSpacing", .view, .presentation) { $0.toolPresent("lineSpacing") },
        tool("display.letterSpacing", "editor.letterSpacing", .view, .presentation) { $0.toolPresent("letterSpacing") },
        tool("ai.inline", "ai.inline.open", .ai, .selection, key: "i", modifiers: [.command]) { $0.toolToggleInline() },
        tool("ai.attachSelection", "ai.context.attachSelection", .ai, .request) { $0.toolAttachSelection() },
        tool("ai.collaborationComment", "collaboration.commentSelection", .ai, .request) { $0.toolAssistant("collaboration.commentSelection") },
        tool("ai.continueWriting", "ai.continueWriting", .ai, .request, key: "return", modifiers: [.command, .shift]) { $0.toolAssistant("ai.continueWriting") },
        tool("ai.refine", "ai.refineText", .ai, .request, key: "r", modifiers: [.command, .shift]) { $0.toolAssistant("ai.refineText") },
        tool("ai.summarize", "ai.summarize", .ai, .request, key: "u", modifiers: [.command, .shift]) { $0.toolAssistant("ai.summarize") },
        tool("ai.styleConvert", "ai.styleConvert", .ai, .request) { $0.toolAssistant("ai.styleConvert") },
        tool("ai.consistencyCheck", "ai.consistencyCheck", .ai, .request) { $0.toolAssistant("ai.consistencyCheck") }
    ]

    static func tool(_ id: String, _ titleKey: String, _ category: EditorToolDefinition.Category,
                     _ impact: EditorToolDefinition.Impact, key: String = "", modifiers: NSEvent.ModifierFlags = [],
                     operation: @escaping (EditorToolTarget) -> Void) -> EditorToolDefinition {
        EditorToolDefinition(id: id, titleKey: titleKey, category: category, impact: impact,
                             key: key, modifiers: modifiers, operation: operation)
    }

    static func register(_ definition: EditorToolDefinition) {
        precondition(Thread.isMainThread)
        precondition(definition.id.contains(".") && !tools.contains { $0.id == definition.id }, "Duplicate/invalid tool ID")
        tools.append(definition)
        NotificationCenter.default.post(name: didRegister, object: nil)
    }

    static func definition(_ id: String) -> EditorToolDefinition? { tools.first { $0.id == id } }
    @discardableResult static func perform(_ id: String, on target: EditorToolTarget) -> Bool {
        guard let definition = definition(id) else { return false }
        target.runTool(definition)
        return true
    }
}
