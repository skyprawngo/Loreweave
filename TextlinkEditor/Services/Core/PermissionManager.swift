//
//  PermissionManager.swift
//  TextlinkEditor
//
//  권한 관리 서비스 - 앱에서 필요한 모든 권한을 중앙 관리
//

import Foundation
import AppKit

/// 승인된 디렉토리 정보
struct AuthorizedDirectory: Identifiable, Codable, Equatable {
    let id: UUID
    let path: String
    let bookmarkData: Data
    let addedAt: Date

    var url: URL? {
        URL(fileURLWithPath: path)
    }

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

/// 앱에서 요청하는 권한 종류
enum PermissionType: String, CaseIterable, Identifiable {
    case documentsAccess = "documentsAccess"

    var id: String { rawValue }

    /// 권한 제목
    var title: String {
        switch self {
        case .documentsAccess:
            return L10n.get("permission.documentsAccess.title")
        }
    }

    /// 권한 설명
    var description: String {
        switch self {
        case .documentsAccess:
            return L10n.get("permission.documentsAccess.description")
        }
    }

    /// 권한 아이콘
    var iconName: String {
        switch self {
        case .documentsAccess:
            return "folder.badge.plus"
        }
    }

    /// UserDefaults 키
    var bookmarkKey: String {
        switch self {
        case .documentsAccess:
            return "documentsDirectoryBookmark"
        }
    }
}

@Observable
final class PermissionManager {
    static let shared = PermissionManager()

    private let authorizedDirectoriesKey = "authorizedDirectories"

    /// 권한 요청이 완료되었는지 여부
    var hasCompletedPermissionSetup: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedPermissionSetup") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedPermissionSetup") }
    }

    /// 각 권한별 승인 상태
    private(set) var permissionStatus: [PermissionType: Bool] = [:]

    /// 승인된 디렉토리 목록
    private(set) var authorizedDirectories: [AuthorizedDirectory] = []

    private init() {
        loadPermissionStatus()
        loadAuthorizedDirectories()
        migrateDocumentsAccessToAuthorizedDirectories()
    }

    // MARK: - Permission Status

    /// 모든 권한 상태 로드
    private func loadPermissionStatus() {
        for permission in PermissionType.allCases {
            permissionStatus[permission] = hasValidBookmark(for: permission)
        }
    }

    /// 특정 권한이 승인되었는지 확인
    func isGranted(_ permission: PermissionType) -> Bool {
        return permissionStatus[permission] ?? false
    }

    /// 모든 필수 권한이 승인되었는지 확인
    var allPermissionsGranted: Bool {
        PermissionType.allCases.allSatisfy { isGranted($0) }
    }

    // MARK: - Bookmark Management

    /// Bookmark이 유효한지 확인
    private func hasValidBookmark(for permission: PermissionType) -> Bool {
        guard let bookmarkData = UserDefaults.standard.data(forKey: permission.bookmarkKey) else {
            return false
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // Bookmark이 오래된 경우 - 재요청 필요
                return false
            }

            // 접근 테스트
            guard url.startAccessingSecurityScopedResource() else {
                return false
            }
            url.stopAccessingSecurityScopedResource()

            return true
        } catch {
            return false
        }
    }

    /// Security-Scoped Bookmark 저장
    private func saveBookmark(for url: URL, permission: PermissionType) -> Bool {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: permission.bookmarkKey)
            permissionStatus[permission] = true
            return true
        } catch {
            print("Failed to save bookmark for \(permission): \(error)")
            return false
        }
    }

    // MARK: - Permission Requests

    /// Documents 폴더 접근 권한 요청
    func requestDocumentsAccess() -> Bool {
        let panel = NSOpenPanel()
        panel.title = L10n.get("permission.documentsAccess.panelTitle")
        panel.message = L10n.get("permission.documentsAccess.panelMessage")
        panel.prompt = L10n.get("permission.documentsAccess.grant")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false

        // Documents 폴더로 기본 위치 설정
        let documentsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        panel.directoryURL = documentsURL

        if panel.runModal() == .OK, let selectedURL = panel.url {
            let success = saveBookmark(for: selectedURL, permission: .documentsAccess)
            if success {
                // authorizedDirectories에도 추가
                addToAuthorizedDirectoriesIfNeeded(url: selectedURL)
            }
            return success
        }

        return false
    }

    /// URL을 authorizedDirectories에 추가 (중복 확인)
    private func addToAuthorizedDirectoriesIfNeeded(url: URL) {
        // 이미 추가된 디렉토리인지 확인
        if authorizedDirectories.contains(where: { $0.path == url.path }) {
            return
        }

        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            let directory = AuthorizedDirectory(
                id: UUID(),
                path: url.path,
                bookmarkData: bookmarkData,
                addedAt: Date()
            )

            authorizedDirectories.insert(directory, at: 0)
            saveAuthorizedDirectories()
        } catch {
            print("Failed to add directory to authorized list: \(error)")
        }
    }

    /// 권한 타입에 따른 권한 요청
    func requestPermission(_ permission: PermissionType) -> Bool {
        switch permission {
        case .documentsAccess:
            return requestDocumentsAccess()
        }
    }

    // MARK: - Access Management

    /// 저장된 Bookmark URL 가져오기 (접근 시작 포함)
    func getBookmarkedURL(for permission: PermissionType) -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: permission.bookmarkKey) else {
            return nil
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // 재요청 필요 - nil 반환
                permissionStatus[permission] = false
                return nil
            }

            // 접근 시작
            guard url.startAccessingSecurityScopedResource() else {
                return nil
            }

            return url
        } catch {
            return nil
        }
    }

    /// 접근 종료
    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    /// 권한 설정 완료 처리
    func completePermissionSetup() {
        hasCompletedPermissionSetup = true
    }

    /// 권한 설정 리셋 (디버그/테스트용)
    func resetPermissions() {
        for permission in PermissionType.allCases {
            UserDefaults.standard.removeObject(forKey: permission.bookmarkKey)
            permissionStatus[permission] = false
        }
        hasCompletedPermissionSetup = false
    }

    // MARK: - Multiple Directory Management

    /// 기존 documentsAccess 권한을 authorizedDirectories로 마이그레이션
    private func migrateDocumentsAccessToAuthorizedDirectories() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: PermissionType.documentsAccess.bookmarkKey) else {
            return
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale { return }

            // 이미 authorizedDirectories에 있는지 확인
            if authorizedDirectories.contains(where: { $0.path == url.path }) {
                return
            }

            // authorizedDirectories에 추가
            let directory = AuthorizedDirectory(
                id: UUID(),
                path: url.path,
                bookmarkData: bookmarkData,
                addedAt: Date()
            )

            authorizedDirectories.insert(directory, at: 0)
            saveAuthorizedDirectories()
        } catch {
            print("Failed to migrate documentsAccess: \(error)")
        }
    }

    /// 승인된 디렉토리 목록 로드
    private func loadAuthorizedDirectories() {
        guard let data = UserDefaults.standard.data(forKey: authorizedDirectoriesKey),
              let directories = try? JSONDecoder().decode([AuthorizedDirectory].self, from: data) else {
            authorizedDirectories = []
            return
        }

        // 유효한 디렉토리만 필터링
        authorizedDirectories = directories.filter { directory in
            isValidBookmark(directory.bookmarkData)
        }

        // 유효하지 않은 디렉토리가 제거된 경우 저장
        if authorizedDirectories.count != directories.count {
            saveAuthorizedDirectories()
        }
    }

    /// 승인된 디렉토리 목록 저장
    private func saveAuthorizedDirectories() {
        guard let data = try? JSONEncoder().encode(authorizedDirectories) else { return }
        UserDefaults.standard.set(data, forKey: authorizedDirectoriesKey)
    }

    /// Bookmark 데이터가 유효한지 확인
    private func isValidBookmark(_ bookmarkData: Data) -> Bool {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale { return false }

            guard url.startAccessingSecurityScopedResource() else { return false }
            url.stopAccessingSecurityScopedResource()

            return true
        } catch {
            return false
        }
    }

    /// 새 디렉토리 권한 추가 요청
    @discardableResult
    func addDirectoryAccess() -> AuthorizedDirectory? {
        let panel = NSOpenPanel()
        panel.title = L10n.get("permission.addDirectory.panelTitle")
        panel.message = L10n.get("permission.addDirectory.panelMessage")
        panel.prompt = L10n.get("permission.addDirectory.grant")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return nil
        }

        // 이미 추가된 디렉토리인지 확인
        if authorizedDirectories.contains(where: { $0.path == selectedURL.path }) {
            return nil
        }

        do {
            let bookmarkData = try selectedURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            let directory = AuthorizedDirectory(
                id: UUID(),
                path: selectedURL.path,
                bookmarkData: bookmarkData,
                addedAt: Date()
            )

            authorizedDirectories.append(directory)
            saveAuthorizedDirectories()

            return directory
        } catch {
            print("Failed to create bookmark for directory: \(error)")
            return nil
        }
    }

    /// 디렉토리 권한 제거
    func removeDirectoryAccess(_ directory: AuthorizedDirectory) {
        authorizedDirectories.removeAll { $0.id == directory.id }
        saveAuthorizedDirectories()
    }

    /// 디렉토리 권한 제거 (ID로)
    func removeDirectoryAccess(id: UUID) {
        authorizedDirectories.removeAll { $0.id == id }
        saveAuthorizedDirectories()
    }

    /// 특정 디렉토리에 대한 접근 URL 가져오기
    func getAccessibleURL(for directory: AuthorizedDirectory) -> URL? {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: directory.bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // 오래된 bookmark - 목록에서 제거
                removeDirectoryAccess(directory)
                return nil
            }

            guard url.startAccessingSecurityScopedResource() else {
                return nil
            }

            return url
        } catch {
            return nil
        }
    }

    /// 경로가 승인된 디렉토리 내에 있는지 확인
    func isPathAuthorized(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)

        // authorizedDirectories에서 확인 (documentsAccess도 여기에 포함됨)
        for directory in authorizedDirectories {
            if url.path.hasPrefix(directory.path) {
                return true
            }
        }

        return false
    }

    /// 모든 승인된 디렉토리 권한 초기화
    func clearAllDirectoryAccess() {
        authorizedDirectories = []
        saveAuthorizedDirectories()
    }
}
