//
//  AlertHelper.swift
//  TextlinkEditor
//
//  NSAlert 확장 - 좌우 화살표 키로 버튼 선택 지원
//

import AppKit

/// NSAlert에 좌우 화살표 키 네비게이션을 추가하는 헬퍼
final class AlertHelper {
    /// 좌우 화살표 키로 버튼 간 이동이 가능한 NSAlert 생성
    /// - Returns: 키보드 네비게이션이 활성화된 NSAlert
    static func createAlert() -> NSAlert {
        let alert = NSAlert()
        return alert
    }

    /// NSAlert를 시트로 표시하고 좌우 화살표 키 네비게이션 활성화
    /// - Parameters:
    ///   - alert: 표시할 NSAlert
    ///   - window: 시트를 표시할 윈도우
    ///   - completion: 사용자 응답 처리 클로저
    static func beginSheetModal(
        _ alert: NSAlert,
        for window: NSWindow,
        completionHandler: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        // 키 이벤트 모니터 설정
        var eventMonitor: Any?

        alert.beginSheetModal(for: window) { response in
            // 모니터 해제
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
            }
            completionHandler(response)
        }

        // 좌우 화살표 키 이벤트 모니터 추가
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard alert.window.isVisible else { return event }

            let buttons = alert.buttons
            guard buttons.count > 1 else { return event }

            // 현재 포커스된 버튼 찾기
            guard let focusedView = alert.window.firstResponder as? NSButton,
                  let currentIndex = buttons.firstIndex(of: focusedView) else {
                return event
            }

            switch event.keyCode {
            case 123: // 왼쪽 화살표
                // 다음 버튼으로 이동 (NSAlert에서 버튼 순서는 오른쪽에서 왼쪽)
                let nextIndex = (currentIndex + 1) % buttons.count
                alert.window.makeFirstResponder(buttons[nextIndex])
                return nil

            case 124: // 오른쪽 화살표
                // 이전 버튼으로 이동
                let prevIndex = (currentIndex - 1 + buttons.count) % buttons.count
                alert.window.makeFirstResponder(buttons[prevIndex])
                return nil

            default:
                return event
            }
        }
    }
}

// MARK: - NSAlert Extension

extension NSAlert {
    /// 좌우 화살표 키 네비게이션이 활성화된 시트 모달 표시
    /// - Parameters:
    ///   - window: 시트를 표시할 윈도우
    ///   - completion: 사용자 응답 처리 클로저
    func beginSheetModalWithArrowNavigation(
        for window: NSWindow,
        completionHandler: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        AlertHelper.beginSheetModal(self, for: window, completionHandler: completionHandler)
    }
}
