//
//  EditorState.swift
//  Loreweave
//
//  에디터 통합 상태 관리 (코어)
//
//  기능별 확장:
//  - EditorState+Editing.swift    : 텍스트 편집 (삽입, 삭제)
//  - EditorState+Cursor.swift     : 커서 이동 및 선택
//  - EditorState+Clipboard.swift  : 복사, 잘라내기, 붙여넣기
//  - EditorState+LineOps.swift    : 행 단위 작업 (이동, 복제)
//  - EditorState+UndoRedo.swift   : Undo/Redo 처리
//  - UndoTypes.swift              : Undo 관련 타입
//

import Foundation
import AppKit

// MARK: - Editor Configuration

/// 에디터 설정
struct EditorConfiguration {
    var fontSize: CGFloat = 14
    var lineHeightMultiple: CGFloat = 1.5
    var fontName: String = "Menlo"
    var tabWidth: Int = 4
    var insertSpacesForTab: Bool = true
    var wordWrap: Bool = true
    var showLineNumbers: Bool = true
    var highlightCurrentLine: Bool = true
    /// 문자 간격 (0 = 기본값, 양수 = 넓게, 음수 = 좁게)
    var letterSpacing: CGFloat = 0

    /// 실제 행 높이 계산
    var lineHeight: CGFloat {
        fontSize * lineHeightMultiple
    }

    /// 에디터 폰트
    var font: NSFont {
        NSFont(name: fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
}

// MARK: - Editor State

/// 에디터 전체 상태
final class EditorState {
    /// 문서
    let document: TextDocument

    /// 선택 상태
    let selection: TextSelection

    /// 뷰포트 관리자
    let viewport: ViewportManager

    /// 에디터 설정
    var configuration: EditorConfiguration {
        didSet {
            applyConfiguration()
        }
    }

    /// 편집 가능 여부
    var isEditable: Bool = true

    /// 문서 수정 여부
    var isModified: Bool = false

    /// 문서 버전 (변경 감지용)
    private var lastKnownVersion: Int = 0

    /// 외부에서 변경된 줄 번호들 (1-indexed)
    /// AI가 파일을 수정했을 때 해당 줄들이 여기에 저장됨
    var externallyModifiedLines: Set<Int> = []

    // MARK: - Undo/Redo Properties

    /// Undo 스택
    var undoStack: [UndoAction] = []

    /// Redo 스택
    var redoStack: [UndoAction] = []

    /// 최대 히스토리 개수
    let maxUndoHistoryCount = 1000

    /// 현재 그룹화 중인 텍스트 입력 (연속 타이핑 그룹화용)
    var pendingTextGroup: PendingTextGroup?

    /// Undo 가능 여부
    var canUndo: Bool { !undoStack.isEmpty || pendingTextGroup != nil }

    /// Redo 가능 여부
    var canRedo: Bool { !redoStack.isEmpty }

    /// Undo 스택 크기 (디버깅용)
    var undoCount: Int { undoStack.count }

    /// Redo 스택 크기 (디버깅용)
    var redoCount: Int { redoStack.count }

    // MARK: - Initialization

    init(
        text: String = "",
        configuration: EditorConfiguration = EditorConfiguration()
    ) {
        self.document = TextDocument(text: text)
        self.selection = TextSelection()
        self.viewport = ViewportManager()
        self.configuration = configuration

        applyConfiguration()
    }

    // MARK: - Configuration

    private func applyConfiguration() {
        viewport.updateLineHeight(configuration.lineHeight)
    }

    /// 폰트 크기 변경
    func setFontSize(_ size: CGFloat) {
        configuration.fontSize = size
    }

    /// 줄 높이 배수 변경
    func setLineHeightMultiple(_ multiple: CGFloat) {
        configuration.lineHeightMultiple = multiple
    }

    /// 폰트 이름 변경
    func setFontName(_ name: String) {
        configuration.fontName = name
    }

    /// 문자 간격 변경
    func setLetterSpacing(_ spacing: CGFloat) {
        configuration.letterSpacing = spacing
    }

    // MARK: - Document Operations

    /// 텍스트 로드
    func loadText(_ text: String) {
        document.loadText(text)
        viewport.updateLineCount(document.lineCount)
        selection.moveCursor(to: .zero)
        isModified = false
        lastKnownVersion = document.version
        clearUndoHistory()
    }

    /// 텍스트 추출
    func getText() -> String {
        document.getText()
    }

    /// 문서 변경 여부 확인 및 업데이트
    func checkModification() {
        if document.version != lastKnownVersion {
            isModified = true
            lastKnownVersion = document.version
        }
    }
}
