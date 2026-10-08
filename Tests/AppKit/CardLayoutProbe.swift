// Run with bash scripts/check-card-layout.sh; uses isolated, offscreen AppKit views.
let application = NSApplication.shared
let canvas = WorkbenchCanvas(frame: NSRect(x: 0, y: 0, width: 2800, height: 1800))
let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
scroll.documentView = canvas
scroll.allowsMagnification = true
let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = scroll
func descendants(_ view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants($0) }
}
func settle() {
    window.contentView!.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.002))
    window.contentView!.layoutSubtreeIfNeeded()
}
func event(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [],
                      timestamp: 0, windowNumber: window.windowNumber, context: nil,
                      eventNumber: 0, clickCount: 1, pressure: 1)!
}
let content = String(repeating: "拖动保持换行。 Mixed text with a long line of content.\n", count: 60)
for scale in [0.35, 0.7, 1.0, 1.5, 2.0] {
    scroll.magnification = scale
    let item = BoardItem(title: "拖动回归", text: content, x: 40, y: 40)
    let card = BoardCardView(item: item, url: nil)
    canvas.addSubview(card)
    card.onSelect = { _ in canvas.addSubview(card, positioned: .above, relativeTo: nil) }
    let text = descendants(card).compactMap { $0 as? NSTextView }.first!
    let handles = descendants(card).compactMap { $0 as? CardHandle }
    let header = handles.first { !$0.resize }!
    let grip = handles.first { $0.resize }!
    func checkWidth() {
        let width = text.enclosingScrollView!.contentView.bounds.width
        precondition(abs(text.frame.width - width) < 0.01, "Preview width drift at zoom \(scale): \(text.frame.width) vs \(width)")
        precondition(text.string == content, "Moving must preserve content")
    }
    settle(); checkWidth()
    let start = NSPoint(x: 80, y: 60)
    header.mouseDown(with: event(.leftMouseDown, at: start))
    for step in 1...80 {
        header.mouseDragged(with: event(.leftMouseDragged, at: NSPoint(x: start.x + Double(step) * 1.37, y: start.y + Double(step) * 0.71)))
        settle(); checkWidth()
        precondition(card.frame.size == NSSize(width: item.width, height: item.height), "Dragging must preserve card size")
    }
    header.mouseUp(with: event(.leftMouseUp, at: start))
    let origin = card.frame.origin
    let resizeStart = NSPoint(x: card.frame.maxX, y: card.frame.maxY)
    grip.mouseDown(with: event(.leftMouseDown, at: resizeStart))
    grip.mouseDragged(with: event(.leftMouseDragged, at: NSPoint(x: resizeStart.x + 100, y: resizeStart.y + 80)))
    grip.mouseUp(with: event(.leftMouseUp, at: resizeStart))
    settle(); checkWidth()
    precondition(abs(card.frame.width - item.width - 100) < 0.01 && abs(card.frame.height - item.height - 80) < 0.01)
    precondition(card.frame.origin == origin, "Resizing must preserve card origin")
    card.removeFromSuperview()
}
print("PASS: preview wrapping, content, drag size and resize handle at 35%, 70%, 100%, 150%, 200%")
