#!/usr/bin/env python3
"""Run production proposal diff/apply code without any account or manuscript writes."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'TextlinkEditor/Services/AI/Revision/ManuscriptRevision.swift').read_text().split('@MainActor')[0]
harness = r'''
enum L10n { static func get(_ value: String) -> String { value } }
func check(_ condition: Bool, _ label: String) { if !condition { fatalError(label) } }
func revision(_ text: String) -> ManuscriptRevision {
    ManuscriptRevision(id: UUID(), relativePath: "draft.md", original: text, selectionLocation: 0, selectionLength: (text as NSString).length)
}
for (old, new) in [("a\nb\nc", "a\nx\nc"), ("a\nb\nc\nd", "a\nx\nc\ny"), ("a", "\na"), ("a\n", "a\n\n"), ("a\nb", "b"), ("", "😀\n한글"), ("a", ""), ("a\n\na", "a\na"), ("a\nb", "a\n\nb")] {
    let r = revision(old), changes = r.changes(proposal: new)
    check(try r.applying(proposal: new, selected: Set(changes.map(\.id)), to: old) == new, "full patch: \(old) → \(new)")
    check(try r.applying(proposal: new, selected: [], to: old) == old, "rejection")
}
let r = revision("a\nb\nc\nd")
check(try r.applying(proposal: "a\nx\nc\ny", selected: [0], to: r.original) == "a\nx\nc\nd", "partial acceptance")
do { _ = try r.applying(proposal: "different", selected: [0], to: "edited"); fatalError("stale accepted") } catch {}
let selected = ManuscriptRevision(id: UUID(), relativePath: "draft.md", original: "앞😀뒤", selectionLocation: 1, selectionLength: 2)
check(try selected.applying(proposal: "한글", selected: [0], to: selected.original) == "앞한글뒤", "UTF16 range")
let invalid = ManuscriptRevision(id: UUID(), relativePath: "a", original: "a", selectionLocation: -1, selectionLength: 100)
do { _ = try invalid.applying(proposal: "b", selected: [0], to: "a"); fatalError("invalid range") } catch {}
let large = revision(Array(repeating: "line", count: 5000).joined(separator: "\n"))
check(large.changes(proposal: "new").count == 1, "bounded large diff")
print("PASS revision partial apply, blank lines, Unicode, stale and invalid guards, bounded diff")
'''
with tempfile.TemporaryDirectory(prefix='lore-revision-') as tmp:
    main = Path(tmp) / 'main.swift'; main.write_text(source + harness)
    subprocess.run(['xcrun','swiftc',str(main),'-o',tmp+'/test'],check=True)
    subprocess.run([tmp+'/test'],check=True)
