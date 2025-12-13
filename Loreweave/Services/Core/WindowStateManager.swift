//
//  WindowStateManager.swift
//  Loreweave
//
//  윈도우 key 상태를 추적하는 매니저
//  NSTextView가 first responder가 되어도 SwiftUI 컨트롤의 활성 상태 유지
//

import SwiftUI
import AppKit
import Observation

/// 윈도우의 key 상태를 추적하여 SwiftUI 컨트롤에 전파
@Observable
final class WindowStateManager {
    static let shared = WindowStateManager()

    /// 현재 앱의 메인 윈도우가 key window인지 여부
    private(set) var isWindowKey: Bool = true

    /// SwiftUI에서 사용할 controlActiveState
    var controlActiveState: ControlActiveState {
        isWindowKey ? .key : .inactive
    }

    private init() {
        setupNotifications()
        updateState()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        // 앱의 윈도우가 key window가 되었을 때
        if let window = notification.object as? NSWindow,
           window.isMainWindow || NSApp.mainWindow == window {
            isWindowKey = true
        }
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        // 앱의 메인 윈도우가 key 상태를 잃었을 때
        if let window = notification.object as? NSWindow,
           window.isMainWindow || NSApp.mainWindow == window {
            // 다른 앱의 윈도우로 포커스가 이동했는지 확인
            DispatchQueue.main.async { [weak self] in
                self?.updateState()
            }
        }
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        isWindowKey = true
    }

    @objc private func applicationDidResignActive(_ notification: Notification) {
        isWindowKey = false
    }

    private func updateState() {
        isWindowKey = NSApp.isActive && (NSApp.keyWindow != nil || NSApp.mainWindow?.isKeyWindow == true)
    }
}

// MARK: - Window Key State View Modifier

/// 윈도우 key 상태를 기반으로 controlActiveState를 설정하는 ViewModifier
/// NSTextView 등 AppKit 컴포넌트가 first responder가 되어도 항상 .key 상태 유지
struct WindowKeyStateModifier: ViewModifier {
    func body(content: Content) -> some View {
        // 항상 .key 상태를 강제하여 AppKit 컴포넌트가 first responder가 되어도
        // SwiftUI 컨트롤이 비활성화되지 않도록 함
        content
            .environment(\.controlActiveState, .key)
    }
}

extension View {
    /// 윈도우 key 상태를 기반으로 컨트롤 활성 상태 설정
    /// NSTextView 등 AppKit 컴포넌트가 first responder가 되어도 활성 상태 유지
    func windowKeyState() -> some View {
        modifier(WindowKeyStateModifier())
    }
}
