#!/usr/bin/env python3
"""Exercise production chunk I/O and prepared storage without touching user manuscripts."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
harness = r'''
import AppKit
@main struct Checks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("draft.md")
        let text = String(repeating: "한글 😀 e\u{301}\r\n원고\n", count: 4000)
        try text.write(to: file, atomically: true, encoding: .utf8)
        for size in [1, 7, 65536] {
            let read = try await DocumentFileStore.readInChunks(at: file, chunkSize: size)
            precondition(read == text, "split UTF-8 scalar or CRLF corrupted")
        }
        print("PASS UTF-8, emoji, combining characters and CRLF across I/O chunks")
        let cancelled = Task { try await DocumentFileStore.readInChunks(at: file, chunkSize: 1) }
        cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("cancelled read published") } catch is CancellationError {}
        print("PASS cancelled read never publishes partial text")
        let invalid = directory.appendingPathComponent("bad.md")
        try Data([0xff,0xfe,0xff]).write(to: invalid)
        do { _ = try await DocumentFileStore.readInChunks(at: invalid); fatalError("invalid UTF8 accepted") } catch DocumentFileStore.Failure.unreadable {}
        print("PASS invalid UTF-8 fails instead of returning repaired/truncated text")
        var ticks = 0
        let pulse = Task { @MainActor in
            while !Task.isCancelled { ticks += 1; try? await Task.sleep(nanoseconds: 1_000_000) }
        }
        let prepared = try await PreparedManuscript.prepare(text: text, fontName: "Menlo", fontSize: 14,
            lineHeightMultiple: 1, letterSpacing: 0, color: .textColor)
        pulse.cancel()
        precondition(ticks > 1, "font preparation blocked main actor")
        let storage = prepared.takeStorage()!
        precondition(storage.string == text && storage.length == (text as NSString).length)
        precondition(prepared.takeStorage() == nil, "mutable storage reused across views")
        print("PASS font preparation yields main actor and transfers complete storage only once")
        let stopped = Task { try await PreparedManuscript.prepare(text: text, fontName: "Menlo", fontSize: 14,
            lineHeightMultiple: 1, letterSpacing: 0, color: .textColor) }
        stopped.cancel()
        do { _ = try await stopped.value; fatalError("cancelled prepare published") } catch is CancellationError {}
        print("PASS cancelled preparation never publishes stale storage")
        let revised = text + "끝"
        try DocumentFileStore.save(revised, at: file, expected: text)
        let saved = try await DocumentFileStore.readInChunks(at: file)
        precondition(saved == revised)
        print("PASS complete manuscript survives chunk read, preparation and atomic save")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='textlink-chunk-tests-') as directory:
    path=Path(directory)
    (path/'Checks.swift').write_text(harness)
    subprocess.run(['xcrun','swiftc','-O','-parse-as-library',
        str(root/'TextlinkEditor/Services/FileSystem/DocumentFileStore.swift'),
        str(root/'TextlinkEditor/Views/MainEditor/EditorPanel/TextlinkTextView/PreparedManuscript.swift'),
        str(path/'Checks.swift'),'-o',str(path/'test')],check=True)
    subprocess.run([str(path/'test')],check=True)
