import AppKit

/// AppKit presentation only; commands remain in the workspace/file modules.
extension FileSystemManager {
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

    func revealInFinder(_ item: FileSystemItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func openWithDefaultApp(_ item: FileSystemItem) {
        NSWorkspace.shared.open(item.url)
    }
}
