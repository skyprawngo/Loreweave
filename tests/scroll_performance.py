#!/usr/bin/env python3
"""Render the actual AppKit/Core Text views at 1K/10K/100K lines; no accounts or manuscripts."""
import ast
from pathlib import Path
import subprocess
import tempfile
import sys
root = Path(__file__).resolve().parents[1]
module = ast.parse((root / 'tests/text_engine_regression.py').read_text())
harness = next(ast.literal_eval(n.value) for n in module.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'harness' for t in n.targets))
prefix = harness[:harness.index('let menuView')]
bench = r'''
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 700, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
for count in [1000, 10000, 100000] {
    let state = EditorState(text: (0..<count).map { "\($0) 한글 원고와 emoji 😀 " + String(repeating: "word ", count: $0 % 23) }.joined(separator: "\n"))
    let view = LoreTextView(editorState: state)
    let start = CFAbsoluteTimeGetCurrent()
    let height = view.totalContentHeight(viewportWidth: 792)
    let layoutMS = (CFAbsoluteTimeGetCurrent() - start) * 1000
    view.frame = NSRect(x: 0, y: 0, width: 800, height: height)
    var times: [Double] = []
    for step in 0..<120 {
        let y = max(0, height - 2000 + CGFloat(step % 60) * 20)
        let rect = CGRect(x: 0, y: y, width: 800, height: 600)
        let begin = CFAbsoluteTimeGetCurrent()
        view.draw(rect)
        times.append((CFAbsoluteTimeGetCurrent() - begin) * 1000)
    }
    times.sort()
    print("BENCH lines=\(count) initial_layout_ms=\(layoutMS) draw_p50_ms=\(times[60]) draw_p95_ms=\(times[114])")
    precondition(times[114] < 50, "offscreen rendering exceeded 50ms budget")
}
'''
engine = root / 'Loreweave/Services/Editor/TextEngine'
sources = [engine / name for name in ['TextDocument.swift', 'TextSelection.swift', 'ViewportManager.swift', 'EditorState.swift', 'EditorCommand.swift']]
sources += sorted((engine / 'EditorState').glob('*.swift'))
sources += [root / 'Loreweave/Views/MainEditor/EditorPanel/LoreTextView' / name for name in ['LineRenderer.swift', 'LoreTextView.swift', 'LoreEditorView.swift', 'GutterView.swift']]
with tempfile.TemporaryDirectory(prefix='lore-scroll-bench-') as directory:
    if '--baseline' in sys.argv:
        baseline = []
        for source in sources:
            path = Path(directory) / source.name
            path.write_bytes(subprocess.check_output(['git', 'show', 'HEAD:' + str(source.relative_to(root))], cwd=root))
            baseline.append(path)
        sources = baseline
        bench = bench.replace('    precondition(times[114] < 50, "offscreen rendering exceeded 50ms budget")', '')
    main = Path(directory) / 'main.swift'
    main.write_text(prefix + bench)
    executable = Path(directory) / 'bench'
    subprocess.run(['swiftc', '-O', *map(str, sources), str(main), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
