//
//  LoreEditorView.swift
//  Loreweave
//
//  통합 에디터 뷰 (거터 + 텍스트 뷰 + 스크롤)
//  거터와 텍스트가 같이 스크롤되는 테이블 형태
//

import AppKit

// MARK: - Lore Editor View

/// 통합 에디터 뷰 (거터 + 텍스트 영역)
/// 거터와 텍스트가 동일한 스크롤 뷰 안에서 함께 스크롤
final class LoreEditorView: NSView {
    // MARK: - Subviews

    /// 스크롤 뷰
    private let scrollView: NSScrollView

    /// 클립 뷰
    private let clipView: NSClipView

    /// 콘텐츠 뷰 (거터 + 텍스트를 담는 컨테이너)
    private let contentView: EditorContentView

    /// 텍스트 뷰 (외부 접근용)
    var textView: LoreTextView { contentView.textView }

    /// 거터 뷰 (외부 접근용)
    var gutterView: GutterView { contentView.gutterView }

    // MARK: - Properties

    /// 에디터 상태
    var editorState: EditorState {
        didSet {
            contentView.editorState = editorState
            syncState()
        }
    }

    // MARK: - Initialization

    init(editorState: EditorState) {
        self.editorState = editorState

        // 콘텐츠 뷰 생성
        self.contentView = EditorContentView(editorState: editorState)

        // 스크롤 뷰 설정
        self.scrollView = NSScrollView()
        self.clipView = NSClipView()

        super.init(frame: .zero)

        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        wantsLayer = true

        // 클립 뷰 설정
        clipView.documentView = contentView
        clipView.drawsBackground = false

        // 스크롤 뷰 설정
        scrollView.contentView = clipView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        // 서브뷰 추가
        addSubview(scrollView)

        // 초기 상태 동기화
        syncState()

        // 거터 클릭 처리
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGutterLineClick),
            name: .gutterLineClicked,
            object: contentView.gutterView
        )

        // 문서 구조 변경 처리 (행 추가/삭제)
        contentView.textView.onDocumentStructureChange = { [weak self] in
            self?.documentDidChange()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()

        // 스크롤 뷰가 전체 영역을 차지
        scrollView.frame = bounds

        // 콘텐츠 뷰 크기 업데이트
        updateContentSize()

        // 레이아웃 변경 시 거터/텍스트 뷰 동기화 (Word Wrap 높이 재계산)
        contentView.syncState()
    }

    private func updateContentSize() {
        let lineHeight = contentView.textView.lineHeight
        let lineCount = max(1, editorState.document.lineCount)
        let contentWidth = scrollView.bounds.width

        // Word Wrap 시 동적 높이 사용
        let textViewWidth = contentWidth - contentView.gutterView.gutterWidth - 8 // textLeftPadding
        let contentHeight: CGFloat

        if contentView.textView.wordWrapEnabled && textViewWidth > 0 {
            contentHeight = contentView.textView.totalContentHeight(viewportWidth: textViewWidth) + max(0, scrollView.bounds.height - lineHeight)
        } else {
            contentHeight = CGFloat(lineCount) * lineHeight + max(0, scrollView.bounds.height - lineHeight)
        }

        let newFrame = NSRect(
            x: 0,
            y: 0,
            width: contentWidth,
            height: max(contentHeight, scrollView.bounds.height)
        )

        if contentView.frame != newFrame {
            contentView.frame = newFrame
            contentView.layoutSubviews()
        }
    }

    // MARK: - State Sync

    private func syncState() {
        contentView.syncState()
    }

    /// 외부에서 상태 변경 후 호출
    func refreshState() {
        syncState()
        updateContentSize()
        contentView.needsDisplay = true
    }

    /// 문서 변경 후 호출
    func documentDidChange() {
        refreshState()
    }

    /// 커서 변경 시 거터 업데이트
    func cursorDidChange() {
        contentView.gutterView.currentLine = editorState.selection.cursorLine + 1
        contentView.gutterView.needsDisplay = true
    }

    // MARK: - Gutter Click

    @objc private func handleGutterLineClick(_ notification: Notification) {
        guard let lineNumber = notification.userInfo?["lineNumber"] as? Int else { return }
        let lineIndex = lineNumber - 1

        guard lineIndex >= 0 && lineIndex < editorState.document.lineCount else { return }

        editorState.selection.selectLine(lineIndex, in: editorState.document)
        contentView.textView.needsDisplay = true
    }

    // MARK: - Public Methods

    /// 특정 줄로 스크롤
    func scrollToLine(_ lineIndex: Int) {
        let lineHeight = contentView.textView.lineHeight
        let targetY = CGFloat(lineIndex) * lineHeight - (scrollView.bounds.height - lineHeight) / 2

        clipView.scroll(to: NSPoint(x: 0, y: max(0, targetY)))
        scrollView.reflectScrolledClipView(clipView)
    }

    /// 포커스 설정
    func focus() {
        window?.makeFirstResponder(contentView.textView)
    }
}

// MARK: - Editor Content View

/// 거터 + 텍스트를 담는 컨테이너 뷰
/// 스크롤 뷰의 documentView로 사용
final class EditorContentView: NSView {
    // MARK: - Subviews

    /// 거터 뷰
    let gutterView: GutterView

    /// 텍스트 뷰
    let textView: LoreTextView

    // MARK: - Properties

    /// 에디터 상태
    var editorState: EditorState {
        didSet {
            textView.editorState = editorState
            syncState()
        }
    }

    // MARK: - Initialization

    init(editorState: EditorState) {
        self.editorState = editorState
        self.gutterView = GutterView()
        self.textView = LoreTextView(editorState: editorState)

        super.init(frame: .zero)

        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        wantsLayer = true

        addSubview(gutterView)
        addSubview(textView)

        syncState()
    }

    // MARK: - Flipped Coordinate System

    override var isFlipped: Bool { true }

    // MARK: - Layout

    func layoutSubviews() {
        let gutterWidth = gutterView.gutterWidth

        // 거터: 왼쪽에 고정 너비
        gutterView.frame = NSRect(
            x: 0,
            y: 0,
            width: gutterWidth,
            height: bounds.height
        )

        // 텍스트: 거터 오른쪽에 나머지 영역
        textView.frame = NSRect(
            x: gutterWidth,
            y: 0,
            width: bounds.width - gutterWidth,
            height: bounds.height
        )
    }

    // MARK: - State Sync

    func syncState() {
        let config = editorState.configuration

        // 텍스트 뷰 동기화 먼저 (정확한 lineHeight, baselineOffset 계산)
        textView.syncFromState()

        // 거터 상태 동기화 - 텍스트 뷰와 동일한 lineHeight, baselineOffset 사용
        gutterView.font = config.font
        gutterView.lineHeight = textView.lineHeight  // LineRenderer에서 계산된 값 사용
        gutterView.baselineOffset = textView.baselineOffset  // 동일한 baselineOffset 사용
        gutterView.totalLineCount = editorState.document.lineCount
        gutterView.currentLine = editorState.selection.cursorLine + 1

        // Word Wrap 시 거터에 동적 행 높이 제공자 연결
        // 클로저 내에서 현재 textView.bounds.width를 사용해야 창 크기 변경 시에도 올바르게 동작
        let defaultLineHeight = textView.lineHeight
        if textView.wordWrapEnabled {
            gutterView.rowHeightProvider = { [weak self] lineIndex in
                guard let self = self else { return defaultLineHeight }
                let viewportWidth = self.textView.bounds.width - 8 // textLeftPadding
                guard viewportWidth > 0 else { return defaultLineHeight }
                return self.textView.rowHeight(for: lineIndex, viewportWidth: viewportWidth)
            }
            gutterView.yPositionProvider = { [weak self] lineIndex in
                guard let self = self else { return CGFloat(lineIndex) * defaultLineHeight }
                let viewportWidth = self.textView.bounds.width - 8 // textLeftPadding
                guard viewportWidth > 0 else { return CGFloat(lineIndex) * defaultLineHeight }
                return self.textView.yPosition(for: lineIndex, viewportWidth: viewportWidth)
            }
        } else {
            gutterView.rowHeightProvider = nil
            gutterView.yPositionProvider = nil
        }

        gutterView.needsDisplay = true
        textView.needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 배경
        AppColors.nsTextEditorBackground.setFill()
        dirtyRect.fill()
    }
}
