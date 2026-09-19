#!/usr/bin/env python3
"""Exercise native tab context-menu routing with actual AppKit events."""
from pathlib import Path
import subprocess,tempfile
source=(Path(__file__).resolve().parents[1] / 'TextlinkEditor/Views/MainEditor/TabBarView.swift').read_text()
s=source[source.index('private struct TabContextMenuRegion:'):source.index('/// A native field keeps')].replace('private struct','struct',1)
h='''
setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
window.contentView = root
let background = TabContextMenuRegion.RegionView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
background.actions = [.init(title: "New file", perform: {})]
root.addSubview(background)
let tab = TabContextMenuRegion.RegionView(frame: NSRect(x: 10, y: 0, width: 140, height: 40))
tab.priority = 1
tab.actions = [.init(title: "Rename", perform: {}), .init(title: "Close", perform: {})]
root.addSubview(tab)
window.makeKeyAndOrderFront(nil)
var observed: [[String]] = []
let observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { notification in
    guard let menu = notification.object as? NSMenu else { return }
    observed.append(menu.items.map(\\.title))
    DispatchQueue.main.async { menu.cancelTracking() }
}
func click(_ x: CGFloat, control: Bool = false) {
    let event = NSEvent.mouseEvent(with: control ? .leftMouseDown : .rightMouseDown, location: NSPoint(x: x, y: 20), modifierFlags: control ? .control : [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    app.postEvent(event, atStart: true)
    let until = Date().addingTimeInterval(0.3)
    while Date() < until {
        if let next = app.nextEvent(matching: .any, until: Date().addingTimeInterval(0.01), inMode: .default, dequeue: true) { app.sendEvent(next) }
    }
}
click(30)
click(300)
click(30, control: true)
precondition(observed == [["Rename", "Close"], ["New file"], ["Rename", "Close"]], "actual event routing: \\(observed)")
precondition(tab.hitTest(.zero) == nil, "normal input passes through region")
tab.unregister()
background.unregister()
NotificationCenter.default.removeObserver(observer)
print("PASS native right click tab/background and Control-click routing")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'main.swift';p.write_text('import SwiftUI\n'+s+h)
 subprocess.run(['swiftc',str(p),'-o',d+'/test'],check=True)
 subprocess.run([d+'/test'],check=True,timeout=20)
