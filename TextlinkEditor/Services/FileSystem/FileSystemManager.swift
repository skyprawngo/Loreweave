//
//  FileSystemManager.swift
//  TextlinkEditor
//
//  파일 시스템 관리 서비스 (파일/폴더 CRUD 및 감시)
//

import Foundation
import AppKit
import Combine

@Observable
final class FileSystemManager {
    static let shared = FileSystemManager()

    /// 프로젝트 루트 항목
    var projectRoot: FileSystemItem?

    /// 사이드바에서 현재 선택된 항목
    var selectedItem: FileSystemItem?

    /// 파일 시스템 변경 감시자
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var watchedDirectoryHandle: Int32 = -1
    var operationError: String?
    var revision = 0
    private var directoryWatchers: [String: DispatchSourceFileSystemObject] = [:]

    /// 프로젝트 루트 URL
    private(set) var projectRootURL: URL?

    /// 새 파일 생성 시 사용할 디렉토리 (우선순위: 선택된 파일의 부모 디렉토리 > 선택된 폴더 > 루트)
    var targetDirectoryForNewFile: FileSystemItem? {
        guard let selected = selectedItem else {
            return projectRoot
        }

        if selected.isDirectory {
            return selected
        } else {
            // 파일이 선택된 경우 부모 디렉토리 찾기
            return findParent(of: selected) ?? projectRoot
        }
    }

    private init() {}

    // MARK: - 프로젝트 초기화

    /// 프로젝트 열기 및 루트 로드
    func initializeProject(at url: URL) {
        stopWatching()
        projectRootURL = url

        // 프로젝트 루트 항목 생성
        let rootItem = FileSystemItem(url: url, isDirectory: true)
        rootItem.isExpanded = true
        projectRoot = rootItem

        // 루트 자식 로드
        loadChildren(of: rootItem)


        // 파일 감시 시작
        startWatching(at: url)
    }

    /// 프로젝트 닫기 및 리소스 정리
    func closeProject() {
        stopWatching()
        projectRoot = nil
        projectRootURL = nil
    }

    // MARK: - 디렉토리 내용 로드

    /// 프로젝트 루트 로드
    func loadProjectRoot() {
        guard let rootItem = projectRoot else { return }
        loadChildren(of: rootItem)
    }

    /// 특정 항목의 자식 로드 (기존 항목 유지하며 증분 업데이트)
    func loadChildren(of item: FileSystemItem) {
        guard item.isDirectory else { return }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: item.url.standardizedFileURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var newChildren: [FileSystemItem] = []
            let existingChildren = item.children ?? []
            // URL 비교 시 standardizedFileURL.path 사용 (유니코드 정규화 문제 해결)
            let existingByPath = Dictionary(uniqueKeysWithValues: existingChildren.map {
                ($0.url.standardizedFileURL.path, $0)
            })

            for url in contents {
                let standardizedPath = url.standardizedFileURL.path
                // 기존 항목이 있으면 재사용 (상태 유지)
                if let existing = existingByPath[standardizedPath] {
                    newChildren.append(existing)
                } else {
                    // 새 항목만 생성
                    let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
                    let isDirectory = resourceValues.isDirectory ?? false
                    let child = FileSystemItem(url: url, isDirectory: isDirectory, parent: item)
                    newChildren.append(child)
                }
            }

            item.children = newChildren
            item.sortChildren()
            revision += 1
            watchDirectory(item)
        } catch {
            print("Failed to load directory contents: \(error)")
            operationError = error.localizedDescription
        }
    }

    /// 항목 펼치기/접기 토글
    func toggleExpand(_ item: FileSystemItem) {
        guard item.isDirectory else { return }

        // 먼저 UI 상태 즉시 변경 (반응성 향상)
        item.isExpanded.toggle()

        // 펼칠 때만 자식 로드 (접을 때는 기존 데이터 유지)
        if item.isExpanded {
            // 자식이 없거나 비어있으면 로드
            loadChildren(of: item)
        }
    }

    // MARK: - 파일/폴더 생성

    /// 새 폴더 생성
    @discardableResult
    func createFolder(named name: String, in parent: FileSystemItem) -> FileSystemItem? {
        guard parent.isDirectory else { return nil }

        let newURL = parent.url.appendingPathComponent(name)

        do {
            try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: false)
            let newItem = FileSystemItem(url: newURL, isDirectory: true, parent: parent)

            if parent.children == nil {
                parent.children = []
            }
            parent.children?.append(newItem)
            parent.sortChildren()
            revision += 1
            return newItem
        } catch {
            operationError = error.localizedDescription
            return nil
        }
    }

    /// 새 파일 생성
    @discardableResult
    func createFile(named name: String, in parent: FileSystemItem, content: String = "") -> FileSystemItem? {
        guard parent.isDirectory else { return nil }

        let newURL = parent.url.appendingPathComponent(name)

        do {
            try DocumentFileStore.validateName(name)
            try DocumentFileStore.create(content, at: newURL)
            let newItem = FileSystemItem(url: newURL, isDirectory: false, parent: parent)

            if parent.children == nil {
                parent.children = []
            }
            parent.children?.append(newItem)
            parent.sortChildren()
            revision += 1
            return newItem
        } catch {
            operationError = error.localizedDescription
            return nil
        }
    }

    /// 새 파일 생성 다이얼로그 표시
    func showNewFileDialog(in parent: FileSystemItem, completion: @escaping (FileSystemItem?) -> Void) {
        guard let window = NSApp.keyWindow else {
            completion(nil)
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.get("explorer.newFile")
        alert.informativeText = L10n.get("explorer.enterFileName")
        alert.addButton(withTitle: L10n.common.confirm)
        alert.addButton(withTitle: L10n.common.cancel)

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        textField.placeholderString = L10n.get("explorer.fileNamePlaceholder")
        textField.stringValue = "untitled.md"
        alert.accessoryView = textField

        // 다이얼로그 표시 (좌우 화살표 키 네비게이션 활성화)
        alert.beginSheetModalWithArrowNavigation(for: window) { response in
            if response == .alertFirstButtonReturn {
                let name = textField.stringValue.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    let item = self.createFile(named: name, in: parent)
                    completion(item)
                } else {
                    completion(nil)
                }
            } else {
                completion(nil)
            }
        }

        // 텍스트 필드에 포커스 및 확장자 앞까지 선택
        alert.window.makeFirstResponder(textField)
        DispatchQueue.main.async {
            let fileName = textField.stringValue
            let nsFileName = fileName as NSString
            let baseName = nsFileName.deletingPathExtension
            if !baseName.isEmpty && baseName.count < fileName.count {
                // 확장자가 있는 경우: 확장자 앞까지 선택
                textField.currentEditor()?.selectedRange = NSRange(location: 0, length: (baseName as NSString).length)
            } else {
                // 확장자가 없는 경우: 전체 선택
                textField.selectText(nil)
            }
        }
    }

    /// 새 폴더 생성 다이얼로그 표시
    func showNewFolderDialog(in parent: FileSystemItem, completion: @escaping (FileSystemItem?) -> Void) {
        guard let window = NSApp.keyWindow else {
            completion(nil)
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.get("explorer.newFolder")
        alert.informativeText = L10n.get("explorer.enterFolderName")
        alert.addButton(withTitle: L10n.common.confirm)
        alert.addButton(withTitle: L10n.common.cancel)

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        textField.placeholderString = L10n.get("explorer.folderNamePlaceholder")
        textField.stringValue = L10n.get("explorer.newFolderDefault")
        alert.accessoryView = textField

        // 좌우 화살표 키 네비게이션 활성화
        alert.beginSheetModalWithArrowNavigation(for: window) { response in
            if response == .alertFirstButtonReturn {
                let name = textField.stringValue.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    let item = self.createFolder(named: name, in: parent)
                    completion(item)
                } else {
                    completion(nil)
                }
            } else {
                completion(nil)
            }
        }

        // 텍스트 필드에 포커스 및 전체 선택
        alert.window.makeFirstResponder(textField)
        textField.selectText(nil)
    }

    // MARK: - 이름 변경

    /// 항목 이름 변경
    @discardableResult
    func rename(_ item: FileSystemItem, to newName: String) -> Bool {
        let newURL = item.url.deletingLastPathComponent().appendingPathComponent(newName)

        do {
            try DocumentFileStore.validateName(newName)
            EditorTabManager.shared.flushEditor()
            try FileManager.default.moveItem(at: item.url, to: newURL)
            EditorTabManager.shared.relocateTabs(from: item.url, to: newURL)

            // FileSystemItem은 클래스이므로 URL을 직접 변경할 수 없음
            // 부모의 children을 새로고침해야 함
            if let parent = item.parent {
                loadChildren(of: parent)
            }

            return true
        } catch {
            operationError = error.localizedDescription
            return false
        }
    }

    /// 이름 변경 다이얼로그 표시
    func showRenameDialog(for item: FileSystemItem, completion: @escaping (Bool) -> Void) {
        guard let window = NSApp.keyWindow else {
            completion(false)
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.get("explorer.rename")
        alert.informativeText = L10n.get("explorer.enterNewName")
        alert.addButton(withTitle: L10n.common.confirm)
        alert.addButton(withTitle: L10n.common.cancel)

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        textField.stringValue = item.name
        alert.accessoryView = textField

        // 좌우 화살표 키 네비게이션 활성화
        alert.beginSheetModalWithArrowNavigation(for: window) { response in
            if response == .alertFirstButtonReturn {
                let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)
                if !newName.isEmpty && newName != item.name {
                    let success = self.rename(item, to: newName)
                    completion(success)
                } else {
                    completion(false)
                }
            } else {
                completion(false)
            }
        }

        // 텍스트 필드에 포커스 및 확장자 앞까지 선택 (파일인 경우)
        alert.window.makeFirstResponder(textField)
        DispatchQueue.main.async {
            let fileName = textField.stringValue
            if !item.isDirectory {
                let nsFileName = fileName as NSString
                let baseName = nsFileName.deletingPathExtension
                if !baseName.isEmpty && baseName.count < fileName.count {
                    // 확장자가 있는 경우: 확장자 앞까지 선택
                    textField.currentEditor()?.selectedRange = NSRange(location: 0, length: (baseName as NSString).length)
                    return
                }
            }
            // 폴더이거나 확장자가 없는 경우: 전체 선택
            textField.selectText(nil)
        }
    }

    // MARK: - 삭제

    /// 항목 삭제
    @discardableResult
    func delete(_ item: FileSystemItem) -> Bool {
        // macOS 파일 시스템의 유니코드 정규화 (NFD) 문제 해결
        // item.url이 실제 파일 시스템의 URL과 다를 수 있으므로 standardizedFileURL 사용
        let fileURL = item.url.standardizedFileURL

        let manager = EditorTabManager.shared
        let affected = manager.tabs.filter { DocumentFileStore.contains($0.url, in: fileURL) }
        guard manager.prepareToClose(affected) else { return false }

        // 파일이 실제로 존재하는지 확인
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("File does not exist at path: \(fileURL.path)")
            // 부모의 children에서 제거 (UI 정리)
            if let parent = item.parent {
                parent.children?.removeAll { $0.id == item.id }
            }
            return true // 이미 없으므로 성공으로 처리
        }

        do {
            try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
            manager.closeTabsUnder(folderURL: fileURL)

            // 부모의 children에서 제거
            if let parent = item.parent {
                parent.children?.removeAll { $0.id == item.id }
            }

            return true
        } catch {
            operationError = error.localizedDescription
            return false
        }
    }

    /// 삭제 확인 다이얼로그 표시
    func showDeleteConfirmation(for item: FileSystemItem, completion: @escaping (Bool) -> Void) {
        guard let window = NSApp.keyWindow else {
            completion(false)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.get("explorer.deleteConfirmTitle")
        alert.informativeText = String(format: L10n.get("explorer.deleteConfirmMessage"), item.name)
        alert.addButton(withTitle: L10n.common.delete)
        alert.addButton(withTitle: L10n.common.cancel)

        // 좌우 화살표 키 네비게이션 활성화
        alert.beginSheetModalWithArrowNavigation(for: window) { response in
            if response == .alertFirstButtonReturn {
                let success = self.delete(item)
                completion(success)
            } else {
                completion(false)
            }
        }
    }

    /// 다중 항목 삭제 확인 다이얼로그 표시
    func showMultipleDeleteConfirmation(for items: [FileSystemItem], completion: @escaping (Bool) -> Void) {
        guard let window = NSApp.keyWindow else {
            completion(false)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.get("explorer.deleteConfirmTitle")
        alert.informativeText = String(format: L10n.get("explorer.deleteMultipleConfirmMessage"), items.count)
        alert.addButton(withTitle: L10n.common.delete)
        alert.addButton(withTitle: L10n.common.cancel)

        // 좌우 화살표 키 네비게이션 활성화
        alert.beginSheetModalWithArrowNavigation(for: window) { response in
            if response == .alertFirstButtonReturn {
                var allSuccess = true
                for item in items {
                    let success = self.delete(item)
                    if !success {
                        allSuccess = false
                    }
                }
                completion(allSuccess)
            } else {
                completion(false)
            }
        }
    }

    // MARK: - 이동 (드래그 앤 드롭)

    /// 수정된 파일 이동 전 확인 다이얼로그 결과
    enum ModifiedFileMoveResult {
        case saveAndMove
        case cancel
    }

    /// 수정된 파일 이동 전 확인 다이얼로그
    /// 파일이 수정 상태에 있어 이동 불가 - 저장 후 이동 여부 확인
    func showModifiedFileMoveDialog(
        fileName: String,
        completion: @escaping (ModifiedFileMoveResult) -> Void
    ) {
        guard let window = NSApp.keyWindow else {
            completion(.cancel)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.get("explorer.modifiedFileMoveTitle")
        alert.informativeText = L10n.get("explorer.modifiedFileMoveMessage")
        alert.addButton(withTitle: L10n.get("explorer.saveAndMove"))
        alert.addButton(withTitle: L10n.common.cancel)

        // 좌우 화살표 키 네비게이션 활성화
        alert.beginSheetModalWithArrowNavigation(for: window) { response in
            switch response {
            case .alertFirstButtonReturn:
                completion(.saveAndMove)
            default:
                completion(.cancel)
            }
        }
    }

    /// 이름 충돌 다이얼로그 결과
    enum NameConflictResult {
        case rename(String)  // 새 이름으로 이동
        case cancel
    }

    /// 이름 충돌 다이얼로그
    /// 대상 디렉토리에 같은 이름의 파일이 존재할 때 표시
    func showNameConflictDialog(
        fileName: String,
        completion: @escaping (NameConflictResult) -> Void
    ) {
        guard let window = NSApp.keyWindow else {
            completion(.cancel)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.get("explorer.nameConflictTitle")
        alert.informativeText = L10n.get("explorer.nameConflictMessage")
        alert.addButton(withTitle: L10n.common.save)
        alert.addButton(withTitle: L10n.common.cancel)

        // 이름 변경 텍스트 필드
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = fileName
        alert.accessoryView = textField

        // 텍스트 필드에 포커스 및 확장자 앞 이름 선택
        alert.window.makeFirstResponder(textField)

        // 확장자 앞까지 선택 (예: "file.md" -> "file" 선택)
        let nsFileName = fileName as NSString
        let extensionStart = nsFileName.deletingPathExtension.count
        if extensionStart > 0 && extensionStart < fileName.count {
            textField.currentEditor()?.selectedRange = NSRange(location: 0, length: extensionStart)
        } else {
            textField.selectText(nil)
        }

        // 좌우 화살표 키 네비게이션 활성화
        alert.beginSheetModalWithArrowNavigation(for: window) { response in
            switch response {
            case .alertFirstButtonReturn:
                let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)
                if !newName.isEmpty && newName != fileName {
                    completion(.rename(newName))
                } else {
                    completion(.cancel)
                }
            default:
                completion(.cancel)
            }
        }
    }

    /// 대상 디렉토리에 같은 이름의 파일이 있는지 확인
    func fileExists(named name: String, in destination: FileSystemItem) -> Bool {
        let targetURL = destination.url.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: targetURL.path)
    }

    /// 항목 이동
    @discardableResult
    func move(_ item: FileSystemItem, to destination: FileSystemItem) -> Bool {
        return move(item, to: destination, withNewName: nil)
    }

    /// 항목 이동 (새 이름 지정 가능)
    @discardableResult
    func move(_ item: FileSystemItem, to destination: FileSystemItem, withNewName newName: String?) -> Bool {
        guard destination.isDirectory else { return false }

        let targetName = newName ?? item.name
        let newURL = destination.url.appendingPathComponent(targetName)

        // 같은 위치로 이동하는 경우 무시
        if newURL == item.url { return false }

        do {
            try DocumentFileStore.validateName(targetName)
            guard !DocumentFileStore.contains(destination.url, in: item.url) else { throw DocumentFileStore.Failure.invalidName }
            EditorTabManager.shared.flushEditor()
            try FileManager.default.moveItem(at: item.url, to: newURL)
            EditorTabManager.shared.relocateTabs(from: item.url, to: newURL)

            // 이전 부모에서 제거
            if let oldParent = item.parent {
                oldParent.children?.removeAll { $0.id == item.id }
            }

            // 새 부모에 추가 (새로고침으로 처리)
            loadChildren(of: destination)

            return true
        } catch {
            operationError = error.localizedDescription
            return false
        }
    }

    // MARK: - 복사

    /// 항목 복사
    @discardableResult
    func copy(_ item: FileSystemItem, to destination: FileSystemItem) -> Bool {
        guard destination.isDirectory else { return false }

        var newURL = destination.url.appendingPathComponent(item.name)

        // 이름 충돌 처리
        var counter = 1
        while FileManager.default.fileExists(atPath: newURL.path) {
            let baseName = (item.name as NSString).deletingPathExtension
            let ext = (item.name as NSString).pathExtension
            let newName = ext.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(ext)"
            newURL = destination.url.appendingPathComponent(newName)
            counter += 1
        }

        do {
            try FileManager.default.copyItem(at: item.url, to: newURL)
            loadChildren(of: destination)
            return true
        } catch {
            print("Failed to copy item: \(error)")
            return false
        }
    }

    // MARK: - Finder에서 열기

    /// Finder에서 항목 표시
    func revealInFinder(_ item: FileSystemItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// 기본 앱으로 열기
    func openWithDefaultApp(_ item: FileSystemItem) {
        NSWorkspace.shared.open(item.url)
    }

    // MARK: - 파일 감시

    /// 프로젝트 루트 폴더 감시 시작
    private func startWatching(at url: URL) {
        if let root = projectRoot { watchDirectory(root) }
    }

    private func watchDirectory(_ item: FileSystemItem) {
        let path = item.url.path
        guard directoryWatchers[path] == nil else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let owner = projectRootURL
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self, weak item] in
            guard let self, let item, self.projectRootURL == owner else { return }
            self.loadChildren(of: item)
        }
        source.setCancelHandler { close(fd) }
        directoryWatchers[path] = source
        source.resume()
    }

    private func stopWatching() {
        for source in directoryWatchers.values { source.cancel() }
        directoryWatchers.removeAll()
    }

    /// 파일 시스템 변경 처리
    private func handleFileSystemChange() {
        // 루트 새로고침
        if let rootItem = projectRoot {
            loadChildren(of: rootItem)
        }
    }

    /// 프로젝트 루트 수동 새로고침
    func refreshProject() {
        guard let rootItem = projectRoot else { return }
        loadChildren(of: rootItem)


        // 펼쳐진 하위 폴더도 새로고침
        refreshExpandedChildren(of: rootItem)
    }

    /// 펼쳐진 자식 폴더 재귀적 새로고침
    private func refreshExpandedChildren(of item: FileSystemItem) {
        guard let children = item.children else { return }

        for child in children where child.isDirectory && child.isExpanded {
            loadChildren(of: child)
            refreshExpandedChildren(of: child)
        }
    }

    /// 모든 폴더의 하위 항목 개수 로드 (재귀적)
    private func loadChildCountsRecursively(of item: FileSystemItem) {
        guard let children = item.children else { return }

        for child in children where child.isDirectory {
            // 아직 자식이 로드되지 않았으면 로드
            if child.children == nil || child.children?.isEmpty == true {
                loadChildren(of: child)
            }
            // 재귀적으로 하위 폴더도 처리
            loadChildCountsRecursively(of: child)
        }
    }

    // MARK: - 유틸리티

    /// 항목의 부모 디렉토리 찾기
    func findParent(of item: FileSystemItem) -> FileSystemItem? {
        // item.parent가 있으면 사용
        if let parent = item.parent {
            return parent
        }

        // 없으면 URL 기반으로 찾기
        let parentURL = item.url.deletingLastPathComponent()
        return findItem(by: parentURL)
    }

    /// URL로 항목 찾기 (재귀 탐색)
    func findItem(by url: URL) -> FileSystemItem? {
        guard let root = projectRoot else { return nil }

        if root.url == url {
            return root
        }

        return findItemRecursively(in: root, url: url)
    }

    private func findItemRecursively(in parent: FileSystemItem, url: URL) -> FileSystemItem? {
        guard let children = parent.children else { return nil }

        for child in children {
            if child.url == url {
                return child
            }
            if child.isDirectory, let found = findItemRecursively(in: child, url: url) {
                return found
            }
        }
        return nil
    }

    /// 디렉토리 생성 (없으면)
    private func createDirectoryIfNeeded(at url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                print("Failed to create directory: \(error)")
            }
        }
    }

    /// 폴더가 섹션 폴더인지 확인 (어떤 언어의 섹션 이름이든)
    func sectionType(for item: FileSystemItem) -> ProjectSection? {
        return ProjectSection.from(folderName: item.name)
    }

    /// 항목이 프로젝트 루트의 직접 자식인지 확인
    func isRootChild(_ item: FileSystemItem) -> Bool {
        return item.parent?.url == projectRootURL
    }
}
