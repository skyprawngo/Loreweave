#!/usr/bin/env python3
"""Bound native edit indexing while retaining exact Unicode/Undo line positions."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
# Reuse the native test's production sources and minimal theme/command doubles.
setup = (root / 'tests/native_editor_regression.py').read_text().split("\nharness = r'''", 1)[0]
exec(compile(setup, __file__, 'exec'))
harness = r'''
setbuf(stdout, nil)
let app = NSApplication.shared
let view = NativeManuscriptTextView()
func reference(_ text: String) -> [Int] {
    let s = text as NSString
    var starts = [0], offset = 0
    while offset < s.length {
        let next = NSMaxRange(s.lineRange(for: NSRange(location: offset, length: 0)))
        if next < s.length { starts.append(next) }
        else if let scalar = UnicodeScalar(s.character(at: s.length - 1)), CharacterSet.newlines.contains(scalar) { starts.append(next) }
        offset = next
    }
    return starts
}
var seed: UInt64 = 12345
func random(_ bound: Int) -> Int {
    seed = seed &* 6364136223846793005 &+ 1
    return Int(seed >> 32) % bound
}
view.load("alpha\r\nbeta\n한😀e\u{301}\u{2028}tail\r")
let inserts = ["", "x", "\r", "\n", "\r\n", "한😀", "\u{2028}", "a\nb\n"]
for step in 0..<1000 {
    let old = view.string as NSString
    var range = NSRange(location: random(old.length + 1), length: 0)
    if range.location < old.length {
        range = old.rangeOfComposedCharacterSequences(for: NSRange(location: range.location, length: min(random(5), old.length - range.location)))
    }
    view.replace(range, with: inserts[random(inserts.count)])
    view.rebuildLineIndex()
    precondition(view.lineStarts == reference(view.string), "incremental index mismatch at \(step)")
    if step % 3 == 0 {
        view.undo(nil)
        view.rebuildLineIndex()
        precondition(view.lineStarts == reference(view.string), "Undo index mismatch")
    }
}
print("PASS 1000 differential Unicode/CRLF edits and Undo")
let text = String(repeating: "한글 😀 paragraph with words\n", count: 100000)
let prepared = try! PreparedManuscript.build(text: text, styleKey: "fixture", attributes: [.font: NSFont.systemFont(ofSize: 14)])
view.load(text, prepared: prepared)
precondition(view.lastIndexedUTF16Count == 0 && view.lineStarts.count == 100001)
print("PASS prepared manuscript transfers line index without main-thread scan")
var timings: [Double] = []
for row in stride(from: 0, to: 100000, by: 1000) {
    let start = CFAbsoluteTimeGetCurrent()
    view.replace(NSRange(location: view.lineStarts[row] + 1, length: 0), with: "z")
    view.rebuildLineIndex()
    timings.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
    precondition(view.lastIndexedUTF16Count < 200, "ordinary edit scanned manuscript")
}
timings.sort()
precondition(view.lineStarts == reference(view.string))
print("TIME 100000-line local edits p95 \(timings[95]) ms, max \(timings.last!) ms")
print("PASS each edit scans fewer than 200 UTF16 units")
view.setSelectedRange(NSRange(location: view.lineStarts[50000], length: 0))
view.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
view.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
view.insertText("한", replacementRange: NSRange(location: NSNotFound, length: 0))
view.rebuildLineIndex()
precondition(view.lineStarts == reference(view.string))
print("PASS large-document IME index")
'''
with tempfile.TemporaryDirectory(prefix='textlink-isolation-') as directory:
    directory = Path(directory)
    main = directory/'main.swift'; main.write_text(prefix + harness)
    executable = directory/'test'
    subprocess.run(['swiftc','-O',*map(str,sources),str(main),'-o',str(executable)],check=True)
    subprocess.run([str(executable)],check=True)
