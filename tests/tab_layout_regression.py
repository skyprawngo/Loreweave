#!/usr/bin/env python3
"""Check production tab sizing against fit, compression and active-tab requirements."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
sizing = (root / 'TextlinkEditor/Views/MainEditor/TabBarView.swift').read_text().split('enum TabBarSizing {', 1)[1]
harness = '''
for available: CGFloat in [320, 480, 800] {
    var previous: CGFloat = .greatestFiniteMagnitude
    for count in 2...20 {
        let inactive = TabBarSizing.width(available: available, count: count, selected: false)
        let active = TabBarSizing.width(available: available, count: count, selected: true)
        precondition(active > inactive, "active tab must be wider")
        precondition(inactive <= previous, "adding tabs must not widen inactive tabs")
        precondition(inactive >= 64 && active >= 96, "overflow retains usable targets")
        if inactive > 64 {
            precondition(inactive * CGFloat(count - 1) + active + CGFloat(count - 1) * 4 <= available + 0.01, "tabs must fit before minimum width")
        }
        previous = inactive
    }
}
print("PASS tab compression, selected width, fit and minimum hit targets")
'''
with tempfile.TemporaryDirectory(prefix='lore-tab-layout-') as temporary:
    main = Path(temporary) / 'main.swift'
    main.write_text('import Foundation\nenum TabBarSizing {' + sizing + harness)
    binary = Path(temporary) / 'test'
    subprocess.run(['swiftc', str(main), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
