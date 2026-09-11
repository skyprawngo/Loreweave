//
//  ThemeAwareBackground.swift
//  Loreweave
//
//  테마에 따라 투명/불투명 배경 자동 전환
//

import SwiftUI
import AppKit

// MARK: - Visual Effect Background

/// 데스크톱 배경을 비추는 vibrancy 효과
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    init(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = KeyWindowTrackingVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// 윈도우의 key 상태를 추적하여 활성/비활성 상태를 올바르게 반영하는 NSVisualEffectView
/// AppKit 에디터가 first responder를 가져가도 윈도우가 key window이면 활성 상태로 표시
class KeyWindowTrackingVisualEffectView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupNotifications()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupNotifications()
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
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateState()
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let keyWindow = notification.object as? NSWindow,
              keyWindow == self.window else { return }
        state = .active
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        guard let resignedWindow = notification.object as? NSWindow,
              resignedWindow == self.window else { return }
        state = .inactive
    }

    private func updateState() {
        if window?.isKeyWindow == true {
            state = .active
        } else {
            state = .inactive
        }
    }
}

// MARK: - Theme Aware Background

/// 테마에 따라 투명/불투명 배경 자동 전환
struct ThemeAwareBackground: View {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    init(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    var body: some View {
        // 앱 시작 시 적용된 테마 기준으로 배경 결정 (런타임 중 변경되지 않음)
        if ThemeManager.shared.isOpaqueTheme {
            // 불투명 테마: 고정 배경색 사용
            OpaqueTheme.background
        } else {
            // 반투명 테마: VisualEffect 사용
            VisualEffectBackground(material: material, blendingMode: blendingMode)
        }
    }
}
