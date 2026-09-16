#!/usr/bin/env python3
"""Test the production shortcut matcher with its JSON path redirected to a temp dir.

Only shortcutsFileURL's body is replaced in a temporary source copy. No production
preferences, Application Support files, or manager behavior are replaced.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'TextlinkEditor/Services/Core/KeyboardShortcutManager.swift').read_text()
start = source.index('    private var shortcutsFileURL: URL {')
end = source.index('    private init()', start)
source = source[:start] + '''    private var shortcutsFileURL: URL {
        URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("shortcuts.json")
    }

''' + source[end:]
harness = r'''
import Foundation
import AppKit
import SwiftUI

enum L10n { static func get(_ key: String) -> String { key } }
func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { print("FAIL \(name)"); exit(1) }
    print("PASS \(name)")
}
func event(_ code: UInt16, _ text: String = "", _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                    windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
                    isARepeat: false, keyCode: code)!
}
let manager = KeyboardShortcutManager.shared
expect(manager.action(matching: event(126, "\u{f700}", [.option, .function, .numericPad])) == .moveLineUp, "default option up with system flags")
expect(manager.action(matching: event(125, "\u{f701}", .option)) == .moveLineDown, "default option down")
expect(manager.action(matching: event(126, "\u{f700}", [.option, .shift])) == .duplicateLineUp, "shift selects duplicate")
expect(manager.action(matching: event(126, "\u{f700}", [.option, .control])) == nil, "extra modifier prevents match")
expect(manager.action(matching: event(51, "\u{7f}", .option)) == .deleteWordBackward, "option backspace")
expect(manager.action(matching: event(51, "\u{7f}", .command)) == .deleteToLineStart, "command backspace")
manager.setKey("k", modifiers: [.control, .shift], for: .moveLineUp)
expect(manager.action(matching: event(40, "K", [.control, .shift, .capsLock])) == .moveLineUp, "reassigned uppercase key with caps lock")
expect(manager.action(matching: event(126, "\u{f700}", .option)) == nil, "old binding no longer matches")
manager.toggleEnabled(for: .moveLineUp)
expect(manager.action(matching: event(40, "K", [.control, .shift])) == nil, "disabled binding ignored")
manager.loadShortcuts()
expect(manager.binding(for: .moveLineUp)?.isEnabled == false, "disabled state persisted in temp JSON")
manager.toggleEnabled(for: .moveLineUp)
manager.loadShortcuts()
expect(manager.action(matching: event(40, "K", [.control, .shift])) == .moveLineUp, "custom key reloads from temp JSON")
let special: [(String, UInt16, String)] = [
    ("space", 49, " "), ("escape", 53, "\u{1b}"), ("esc", 53, "\u{1b}"),
    ("home", 115, "\u{f729}"), ("end", 119, "\u{f72b}"),
    ("pageup", 116, "\u{f72c}"), ("pagedown", 121, "\u{f72d}"),
    ("left", 123, "\u{f702}"), ("right", 124, "\u{f703}"),
    ("delete", 51, "\u{7f}"), ("backspace", 51, "\u{7f}"),
    ("enter", 76, "\u{3}"), ("return", 36, "\r"), ("tab", 48, "\t")
]
for (key, code, text) in special {
    manager.setKey(key, modifiers: [.control, .option, .command], for: .moveLineUp)
    expect(manager.action(matching: event(code, text, [.control, .option, .command, .function])) == .moveLineUp,
           "special key \(key)")
}
manager.setKey("esc", modifiers: [.control, .option, .command], for: .moveLineUp)
expect(manager.findConflict(key: "escape", modifiers: [.control, .option, .command], excluding: .moveLineDown)?.action == .moveLineUp,
       "equivalent aliases share conflict detection")
manager.resetToDefault(for: .moveLineUp)
expect(manager.action(matching: event(126, "\u{f700}", .option)) == .moveLineUp, "reset restores default")
expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("shortcuts.json").path), "all persistence uses temp directory")
print("ALL SHORTCUT REGRESSIONS PASSED")
'''
with tempfile.TemporaryDirectory(prefix='lore-shortcut-tests-') as directory:
    directory = Path(directory)
    adapter = directory / 'KeyboardShortcutManager.swift'
    adapter.write_text(source)
    main = directory / 'main.swift'
    main.write_text(harness)
    executable = directory / 'test'
    subprocess.run(['swiftc', str(adapter), str(main), '-o', str(executable)], check=True)
    subprocess.run([str(executable), str(directory)], check=True)
