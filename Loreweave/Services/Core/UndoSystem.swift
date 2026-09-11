//
//  UndoSystem.swift
//  Loreweave
//
//  표준화된 Undo/Redo 시스템
//  모든 텍스트 입력 영역에서 동일한 인터페이스로 사용 가능
//
//  주요 기능:
//  - 연속 타이핑 그룹화 (동일 타입 문자를 하나의 Undo 단위로)
//  - 문자 타입 경계 감지 (한글, 영문, 일본어 등 구분)
//  - 작업 영역별 독립 히스토리
//

import Foundation

// MARK: - Work Area (작업 영역 식별)

/// 앱 내 작업 영역 식별자
/// 새로운 텍스트 입력 영역이 추가될 때 여기에 케이스 추가
enum WorkArea: String, Hashable {
    case editor = "editor"
    case aiChat = "aiChat"
    // 추후 확장 예시:
    // case settings = "settings"
    // case notepad = "notepad"
}

// MARK: - Text Character Type (문자 타입)

/// 문자 종류 (그룹화 경계 판단용)
///
/// 연속 타이핑 시 같은 타입의 문자는 하나의 Undo 단위로 그룹화됨.
/// 타입이 바뀌면 새 그룹이 시작됨.
enum TextCharType: Equatable {
    /// 영문/숫자
    case alphanumeric
    /// 한글
    case korean
    /// 일본어 히라가나
    case hiragana
    /// 일본어 카타카나
    case katakana
    /// 일본어 한자 (CJK 통합 한자)
    case kanji
    /// 중국어 간체/번체
    case chinese
    /// 공백
    case whitespace
    /// 줄바꿈
    case newline
    /// 특수문자/구두점
    case punctuation
    /// 기타
    case other

    /// 문자로부터 타입 결정
    static func from(_ char: Character) -> TextCharType {
        if char.isNewline {
            return .newline
        }
        if char.isWhitespace {
            return .whitespace
        }
        if char.isPunctuation || char.isSymbol {
            return .punctuation
        }

        // 유니코드 스칼라로 범위 확인
        guard let scalar = char.unicodeScalars.first else {
            return .other
        }

        let value = scalar.value

        // 한글 범위
        if (0xAC00...0xD7AF).contains(value) ||  // 한글 음절
           (0x1100...0x11FF).contains(value) ||  // 한글 자모
           (0x3130...0x318F).contains(value) {   // 호환용 한글 자모
            return .korean
        }

        // 일본어 히라가나
        if (0x3040...0x309F).contains(value) {
            return .hiragana
        }

        // 일본어 카타카나
        if (0x30A0...0x30FF).contains(value) ||
           (0x31F0...0x31FF).contains(value) {  // 카타카나 확장
            return .katakana
        }

        // CJK 통합 한자 (일본어 한자 + 중국어)
        if (0x4E00...0x9FFF).contains(value) ||   // CJK 통합 한자
           (0x3400...0x4DBF).contains(value) ||   // CJK 통합 한자 확장 A
           (0x20000...0x2A6DF).contains(value) {  // CJK 통합 한자 확장 B
            return .kanji
        }

        // 영문/숫자
        if char.isLetter || char.isNumber {
            return .alphanumeric
        }

        return .other
    }

    /// 같은 그룹으로 묶을 수 있는지 확인
    func canGroupWith(_ other: TextCharType) -> Bool {
        // 줄바꿈, 공백, 구두점은 항상 그룹 경계
        if self == .newline || other == .newline { return false }
        if self == .whitespace || other == .whitespace { return false }
        if self == .punctuation || other == .punctuation { return false }

        // 같은 타입끼리만 그룹화
        return self == other
    }
}

// MARK: - Text Undo Action (텍스트 Undo 액션)

/// 텍스트 편집 Undo 액션 타입
enum TextUndoAction {
    /// 텍스트 대체 (삽입, 삭제, 대체 모두 처리 가능)
    case replaceText(
        range: NSRange,
        oldText: String,
        newText: String,
        oldSelectedRange: NSRange,
        newSelectedRange: NSRange
    )
}

// MARK: - Text Pending Group (연속 타이핑 그룹)

/// 연속 타이핑 그룹화를 위한 대기 중인 텍스트 그룹
struct TextPendingGroup {
    /// 시작 위치
    let startLocation: Int
    /// 현재 끝 위치
    var endLocation: Int
    /// 누적된 텍스트
    var insertedText: String
    /// 마지막 문자 타입 (그룹화 판단용)
    var lastCharacterType: TextCharType
    /// 그룹 시작 전 선택 범위
    let originalSelectedRange: NSRange
}

// MARK: - Text Undo History (텍스트 Undo 히스토리)

/// 텍스트 입력 영역의 Undo/Redo 히스토리 관리
/// 연속 타이핑 그룹화, 문자 타입 경계 감지 포함
final class TextUndoHistory {
    /// 작업 영역 식별자
    let workArea: WorkArea

    /// Undo 스택
    private var undoStack: [TextUndoAction] = []

    /// Redo 스택
    private var redoStack: [TextUndoAction] = []

    /// 최대 히스토리 크기
    private let maxHistorySize: Int

    /// 현재 그룹화 중인 텍스트 입력
    private var pendingTextGroup: TextPendingGroup?

    /// 텍스트 적용 클로저
    private let applyText: (String, NSRange, NSRange) -> Void

    /// Undo 가능 여부
    var canUndo: Bool { !undoStack.isEmpty || pendingTextGroup != nil }

    /// Redo 가능 여부
    var canRedo: Bool { !redoStack.isEmpty }

    /// 현재 Undo 스택 크기
    var undoCount: Int { undoStack.count }

    /// 현재 Redo 스택 크기
    var redoCount: Int { redoStack.count }

    /// 초기화
    /// - Parameters:
    ///   - workArea: 작업 영역 식별자
    ///   - maxHistorySize: 최대 히스토리 크기 (기본 1000)
    ///   - applyText: 텍스트 적용 클로저 (text, range, newSelectedRange)
    init(
        workArea: WorkArea,
        maxHistorySize: Int = 1000,
        applyText: @escaping (String, NSRange, NSRange) -> Void
    ) {
        self.workArea = workArea
        self.maxHistorySize = maxHistorySize
        self.applyText = applyText
    }

    // MARK: - Text Input Grouping

    /// 텍스트 입력을 그룹에 추가 (연속 타이핑 그룹화)
    /// - Parameters:
    ///   - text: 입력된 텍스트
    ///   - location: 입력 위치
    ///   - originalSelectedRange: 입력 전 선택 범위
    func addTextInput(_ text: String, at location: Int, originalSelectedRange: NSRange) {
        guard let firstChar = text.first else { return }
        let charType = TextCharType.from(firstChar)

        // 기존 그룹이 있고, 같은 타입이며, 연속된 위치라면 그룹에 추가
        if var group = pendingTextGroup,
           group.lastCharacterType.canGroupWith(charType),
           group.endLocation == location {
            group.insertedText += text
            group.endLocation = location + text.count
            group.lastCharacterType = TextCharType.from(text.last ?? firstChar)
            pendingTextGroup = group
        } else {
            // 기존 그룹 커밋 후 새 그룹 시작
            commitPendingTextGroup()

            pendingTextGroup = TextPendingGroup(
                startLocation: location,
                endLocation: location + text.count,
                insertedText: text,
                lastCharacterType: TextCharType.from(text.last ?? firstChar),
                originalSelectedRange: originalSelectedRange
            )
        }

        redoStack.removeAll()
    }

    /// 삭제 작업 기록
    /// - Parameters:
    ///   - range: 삭제된 범위
    ///   - deletedText: 삭제된 텍스트
    ///   - newSelectedRange: 삭제 후 선택 범위
    func recordDeletion(range: NSRange, deletedText: String, newSelectedRange: NSRange) {
        // 대기 중인 그룹 커밋
        commitPendingTextGroup()

        let action = TextUndoAction.replaceText(
            range: NSRange(location: range.location, length: 0),  // 삭제 후 범위
            oldText: deletedText,
            newText: "",
            oldSelectedRange: range,
            newSelectedRange: newSelectedRange
        )
        pushAction(action)
    }

    /// 대체 작업 기록
    /// - Parameters:
    ///   - range: 대체된 범위
    ///   - oldText: 이전 텍스트
    ///   - newText: 새 텍스트
    ///   - newSelectedRange: 대체 후 선택 범위
    func recordReplacement(range: NSRange, oldText: String, newText: String, newSelectedRange: NSRange) {
        // 대기 중인 그룹 커밋
        commitPendingTextGroup()

        let action = TextUndoAction.replaceText(
            range: NSRange(location: range.location, length: newText.count),
            oldText: oldText,
            newText: newText,
            oldSelectedRange: range,
            newSelectedRange: newSelectedRange
        )
        pushAction(action)
    }

    /// 대기 중인 텍스트 그룹을 Undo 스택에 커밋
    func commitPendingTextGroup() {
        guard let group = pendingTextGroup else { return }

        let action = TextUndoAction.replaceText(
            range: NSRange(location: group.startLocation, length: group.insertedText.count),
            oldText: "",
            newText: group.insertedText,
            oldSelectedRange: group.originalSelectedRange,
            newSelectedRange: NSRange(location: group.endLocation, length: 0)
        )

        undoStack.append(action)
        pendingTextGroup = nil

        trimStackIfNeeded()

        #if DEBUG
        print("[TextUndoHistory:\(workArea.rawValue)] 그룹 커밋: \(group.insertedText.count)자")
        #endif
    }

    // MARK: - Undo/Redo

    /// Undo 실행
    @discardableResult
    func undo() -> Bool {
        // 대기 중인 그룹이 있으면 먼저 커밋
        commitPendingTextGroup()

        guard let action = undoStack.popLast() else {
            #if DEBUG
            print("[TextUndoHistory:\(workArea.rawValue)] Undo 실패: 스택이 비어있음")
            #endif
            return false
        }

        applyUndoAction(action, isRedo: false)

        #if DEBUG
        print("[TextUndoHistory:\(workArea.rawValue)] Undo 실행")
        #endif

        return true
    }

    /// Redo 실행
    @discardableResult
    func redo() -> Bool {
        // 대기 중인 그룹이 있으면 먼저 커밋
        commitPendingTextGroup()

        guard let action = redoStack.popLast() else {
            #if DEBUG
            print("[TextUndoHistory:\(workArea.rawValue)] Redo 실패: 스택이 비어있음")
            #endif
            return false
        }

        applyUndoAction(action, isRedo: true)

        #if DEBUG
        print("[TextUndoHistory:\(workArea.rawValue)] Redo 실행")
        #endif

        return true
    }

    /// 히스토리 전체 클리어
    func clear() {
        pendingTextGroup = nil
        undoStack.removeAll()
        redoStack.removeAll()

        #if DEBUG
        print("[TextUndoHistory:\(workArea.rawValue)] 히스토리 클리어")
        #endif
    }

    // MARK: - Private

    private func pushAction(_ action: TextUndoAction) {
        undoStack.append(action)
        redoStack.removeAll()
        trimStackIfNeeded()
    }

    private func trimStackIfNeeded() {
        while undoStack.count > maxHistorySize {
            undoStack.removeFirst()
        }
    }

    private func applyUndoAction(_ action: TextUndoAction, isRedo: Bool) {
        switch action {
        case .replaceText(let range, let oldText, let newText, let oldSelectedRange, let newSelectedRange):
            #if DEBUG
            print("[TextUndoHistory] applyUndoAction isRedo=\(isRedo)")
            print("  range=\(range), oldText='\(oldText)', newText='\(newText)'")
            print("  oldSelectedRange=\(oldSelectedRange), newSelectedRange=\(newSelectedRange)")
            #endif

            if isRedo {
                // Redo: 원래 작업을 다시 실행
                // - 삽입 작업: oldText="" → newText="입력텍스트" (텍스트 삽입)
                // - 삭제 작업: oldText="삭제텍스트" → newText="" (텍스트 삭제)
                let deleteRange = NSRange(location: range.location, length: oldText.count)
                applyText(newText, deleteRange, newSelectedRange)

                #if DEBUG
                print("  [Redo] deleteRange=\(deleteRange), inserting '\(newText)'")
                #endif

                // 원래 액션을 Undo 스택에 다시 추가 (역액션 아님!)
                undoStack.append(action)
            } else {
                // Undo: newText를 삭제하고 oldText를 복원
                let deleteRange = NSRange(location: range.location, length: newText.count)
                applyText(oldText, deleteRange, oldSelectedRange)

                #if DEBUG
                print("  [Undo] deleteRange=\(deleteRange), inserting '\(oldText)'")
                #endif

                // 원래 액션을 Redo 스택에 추가 (역액션 아님!)
                redoStack.append(action)
            }
        }
    }
}

// MARK: - Text Undo History Manager (중앙 관리자)

/// 앱 전체의 텍스트 Undo 히스토리를 중앙에서 관리
final class TextUndoHistoryManager {
    static let shared = TextUndoHistoryManager()

    /// 작업 영역별 히스토리 저장소
    private var histories: [WorkArea: TextUndoHistory] = [:]

    /// 현재 포커스된 작업 영역
    private(set) var focusedArea: WorkArea?

    private init() {}

    // MARK: - History Management

    /// 작업 영역에 대한 TextUndoHistory 생성 및 등록
    /// - Parameters:
    ///   - workArea: 작업 영역
    ///   - maxHistorySize: 최대 히스토리 크기
    ///   - applyText: 텍스트 적용 클로저
    /// - Returns: 생성된 TextUndoHistory
    @discardableResult
    func createHistory(
        for workArea: WorkArea,
        maxHistorySize: Int = 1000,
        applyText: @escaping (String, NSRange, NSRange) -> Void
    ) -> TextUndoHistory {
        let history = TextUndoHistory(
            workArea: workArea,
            maxHistorySize: maxHistorySize,
            applyText: applyText
        )
        histories[workArea] = history

        #if DEBUG
        print("[TextUndoHistoryManager] 히스토리 생성: \(workArea.rawValue)")
        #endif

        return history
    }

    /// 작업 영역의 TextUndoHistory 가져오기
    func getHistory(for workArea: WorkArea) -> TextUndoHistory? {
        histories[workArea]
    }

    /// 작업 영역의 히스토리 제거
    func removeHistory(for workArea: WorkArea) {
        histories.removeValue(forKey: workArea)

        #if DEBUG
        print("[TextUndoHistoryManager] 히스토리 제거: \(workArea.rawValue)")
        #endif
    }

    // MARK: - Focus Management

    /// 포커스된 작업 영역 설정
    func setFocusedArea(_ area: WorkArea?) {
        // 이전 영역의 대기 그룹 커밋
        if let previousArea = focusedArea, previousArea != area {
            histories[previousArea]?.commitPendingTextGroup()
        }

        focusedArea = area

        #if DEBUG
        if let area = area {
            print("[TextUndoHistoryManager] 포커스 변경: \(area.rawValue)")
        } else {
            print("[TextUndoHistoryManager] 포커스 해제")
        }
        #endif
    }

    /// 현재 포커스된 영역의 히스토리
    var focusedHistory: TextUndoHistory? {
        guard let area = focusedArea else { return nil }
        return histories[area]
    }

    /// 현재 포커스된 영역에서 Undo 가능 여부
    var canUndo: Bool {
        focusedHistory?.canUndo ?? false
    }

    /// 현재 포커스된 영역에서 Redo 가능 여부
    var canRedo: Bool {
        focusedHistory?.canRedo ?? false
    }

    /// 현재 포커스된 영역에서 Undo 실행
    @discardableResult
    func undo() -> Bool {
        focusedHistory?.undo() ?? false
    }

    /// 현재 포커스된 영역에서 Redo 실행
    @discardableResult
    func redo() -> Bool {
        focusedHistory?.redo() ?? false
    }

    // MARK: - Convenience

    /// 모든 히스토리 클리어
    func clearAllHistories() {
        histories.values.forEach { $0.clear() }
        histories.removeAll()

        #if DEBUG
        print("[TextUndoHistoryManager] 모든 히스토리 클리어")
        #endif
    }

    /// 등록된 작업 영역 목록
    var registeredAreas: [WorkArea] {
        Array(histories.keys)
    }
}

// MARK: - Protocol for Undo Capable Views

/// Undo 기능을 지원하는 뷰 프로토콜
protocol TextUndoCapable: AnyObject {
    var textUndoHistory: TextUndoHistory? { get }
    func applyUndoText(_ text: String, in range: NSRange, selectRange: NSRange)
}

// MARK: - Generic Undo Support (제네릭 Undo - 비텍스트 용)

/// Undo 가능한 작업 단위 (제네릭 버전 - 비텍스트 용)
/// 제네릭을 사용하여 다양한 타입의 상태를 저장 가능
struct GenericUndoAction<State> {
    /// 작업 설명 (디버깅/UI 표시용)
    let description: String

    /// 작업 시점의 타임스탬프
    let timestamp: Date

    /// Undo 시 복원할 상태
    let undoState: State

    /// Redo 시 복원할 상태
    let redoState: State

    init(description: String, undoState: State, redoState: State) {
        self.description = description
        self.timestamp = Date()
        self.undoState = undoState
        self.redoState = redoState
    }
}

/// 특정 작업 영역의 Undo/Redo 히스토리 관리 (제네릭 버전 - 비텍스트 용)
/// 제네릭 State를 사용하여 다양한 상태 타입 지원
final class GenericUndoHistory<State> {
    /// 작업 영역 식별자
    let workArea: WorkArea

    /// Undo 스택
    private var undoStack: [GenericUndoAction<State>] = []

    /// Redo 스택
    private var redoStack: [GenericUndoAction<State>] = []

    /// 최대 히스토리 크기 (메모리 관리)
    private let maxHistorySize: Int

    /// 상태 복원 클로저
    private let restoreState: (State) -> Void

    /// Undo 가능 여부
    var canUndo: Bool { !undoStack.isEmpty }

    /// Redo 가능 여부
    var canRedo: Bool { !redoStack.isEmpty }

    /// 현재 Undo 스택 크기
    var undoCount: Int { undoStack.count }

    /// 현재 Redo 스택 크기
    var redoCount: Int { redoStack.count }

    init(workArea: WorkArea, maxHistorySize: Int = 100, restoreState: @escaping (State) -> Void) {
        self.workArea = workArea
        self.maxHistorySize = maxHistorySize
        self.restoreState = restoreState
    }

    // MARK: - Public API

    /// 새로운 작업 등록
    func registerAction(description: String, undoState: State, redoState: State) {
        let action = GenericUndoAction(description: description, undoState: undoState, redoState: redoState)
        undoStack.append(action)
        redoStack.removeAll()

        if undoStack.count > maxHistorySize {
            undoStack.removeFirst(undoStack.count - maxHistorySize)
        }

        #if DEBUG
        print("[GenericUndoHistory:\(workArea.rawValue)] 작업 등록: \(description), 스택 크기: \(undoStack.count)")
        #endif
    }

    /// Undo 실행
    @discardableResult
    func undo() -> Bool {
        guard let action = undoStack.popLast() else {
            return false
        }
        restoreState(action.undoState)
        redoStack.append(action)
        return true
    }

    /// Redo 실행
    @discardableResult
    func redo() -> Bool {
        guard let action = redoStack.popLast() else {
            return false
        }
        restoreState(action.redoState)
        undoStack.append(action)
        return true
    }

    /// 히스토리 전체 클리어
    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    /// 마지막 Undo 작업 설명 가져오기
    var lastUndoDescription: String? {
        undoStack.last?.description
    }

    /// 마지막 Redo 작업 설명 가져오기
    var lastRedoDescription: String? {
        redoStack.last?.description
    }
}

/// GenericUndoHistory를 GenericUndoCapable로 확장
protocol GenericUndoCapable {
    var canUndo: Bool { get }
    var canRedo: Bool { get }
    func performUndo() -> Bool
    func performRedo() -> Bool
    func clearHistory()
}

extension GenericUndoHistory: GenericUndoCapable {
    func performUndo() -> Bool {
        undo()
    }

    func performRedo() -> Bool {
        redo()
    }

    func clearHistory() {
        clear()
    }
}
