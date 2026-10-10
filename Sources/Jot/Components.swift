import AppKit
import QuartzCore

/// Let AppKit own window controls, spacing, materials and full-screen behavior.
func configureWindowChrome(_ window: NSWindow, identifier: String) {
    if #available(macOS 26.0, *) {
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier(identifier))
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .none
    }
}

enum Palette {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let darkMode = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = darkMode ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }
    static let backdrop = adaptive(0xF3F3F5, 0x1C1C1E)
    static let paper = adaptive(0xFFFFFF, 0x242426)
    static let sidebar = adaptive(0xECECEE, 0x29292C)
    static let ink = adaptive(0x1D1D1F, 0xF5F5F7)
    static let muted = adaptive(0x5C5C61, 0xB7B7BD)
    static let accent = adaptive(0x303034, 0xE4E4E8)
    static let onAccent = adaptive(0xFFFFFF, 0x242426)
    static let selected = adaptive(0xE2E2E6, 0x36363A)
    static let line = adaptive(0xDEDEE2, 0x3C3C40)
}

func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = Palette.ink) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.lineBreakMode = .byTruncatingTail
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return field
}

func symbol(_ name: String, size: CGFloat = 14) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: size, weight: .regular))
}

func button(_ title: String, symbol name: String? = nil, target: AnyObject?, action: Selector, primary: Bool = false) -> NSButton {
    let result = FeedbackButton(title: title, target: target, action: action)
    result.primary = primary
    result.font = .systemFont(ofSize: 12, weight: primary ? .medium : .regular)
    result.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
    result.imageScaling = .scaleProportionallyDown
    result.alignment = .center
    result.imageHugsTitle = true
    if let name = name { result.image = symbol(name) }
    result.contentTintColor = primary ? Palette.onAccent : Palette.ink
    result.translatesAutoresizingMaskIntoConstraints = false
    result.heightAnchor.constraint(equalToConstant: 34).isActive = true
    if title.isEmpty { result.widthAnchor.constraint(equalToConstant: 34).isActive = true }
    result.setAccessibilityLabel(title)
    return result
}

/// Keep NSButton's native tracking/actions, with visible, interruptible state feedback.
final class FeedbackButton: NSButton {
    var primary = false { didSet { updateFeedback(animated: false) } }
    var compact = false { didSet { invalidateIntrinsicContentSize(); updateFeedback(animated: false) } }
    private var hovered = false
    private var pressed = false
    private var keyboardFocused = false
    private var lastLayoutSize: NSSize = .zero
    private var pointerTracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = FeedbackButtonCell()
        setButtonType(.momentaryPushIn)
        isBordered = false
        wantsLayer = true
        focusRingType = .exterior
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        updateFeedback(animated: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }

    // The custom background fills our bounds; native symbol-dependent insets
    // would make equal Auto Layout heights render as different button sizes.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override var intrinsicContentSize: NSSize {
        if compact { return NSSize(width: 28, height: 28) }
        let size = super.intrinsicContentSize
        return NSSize(width: title.isEmpty ? 34 : size.width + 26, height: 34)
    }
    override var isEnabled: Bool {
        didSet {
            if !isEnabled { hovered = false; pressed = false }
            updateFeedback(animated: window != nil)
            window?.invalidateCursorRects(for: self)
        }
    }
    override func updateTrackingAreas() {
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
        addTrackingArea(area); pointerTracking = area
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { if isEnabled { hovered = true; updateFeedback(animated: true) } }
    override func mouseExited(with event: NSEvent) { hovered = false; updateFeedback(animated: true) }
    override func resetCursorRects() { if isEnabled { addCursorRect(bounds, cursor: .pointingHand) } }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        setPressed(true)
        super.mouseDown(with: event)
        if let window { hovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) }
        setPressed(false)
    }
    override func highlight(_ flag: Bool) { super.highlight(flag); setPressed(flag) }
    fileprivate func setPressed(_ value: Bool) {
        guard pressed != value else { return }
        pressed = value && isEnabled; updateFeedback(animated: true)
    }
    override func becomeFirstResponder() -> Bool { let result = super.becomeFirstResponder(); keyboardFocused = result; updateFeedback(animated: true); return result }
    override func resignFirstResponder() -> Bool { let result = super.resignFirstResponder(); if result { keyboardFocused = false }; updateFeedback(animated: true); return result }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: primary ? 17 : (compact ? 6 : 10), yRadius: primary ? 17 : (compact ? 6 : 10)).fill() }
    override var focusRingMaskBounds: NSRect { bounds }
    override func layout() {
        super.layout()
        if lastLayoutSize != bounds.size { lastLayoutSize = bounds.size; updateFeedback(animated: false) }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateFeedback(animated: false) }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); hovered = false; pressed = false; updateFeedback(animated: false) }
    @objc private func accessibilityChanged() { updateFeedback(animated: false) }

    private func updateFeedback(animated: Bool) {
        applyControlFeedback(self, primary: primary, cornerRadius: compact ? 6 : 10, hovered: hovered, pressed: pressed, keyboardFocused: keyboardFocused, animated: animated)
    }
}

/// Shared layer treatment keeps buttons and native popup controls visually consistent.
private func applyControlFeedback(_ control: NSButton, primary: Bool = false, cornerRadius: CGFloat = 10, hovered: Bool, pressed: Bool, keyboardFocused: Bool, animated: Bool) {
        guard let layer = control.layer else { return }
        let isEnabled = control.isEnabled
        let bounds = control.bounds
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let activePress = pressed && isEnabled
        let activeHover = hovered && isEnabled
        let background: NSColor
        if primary {
            background = activePress ? Palette.adaptive(0x1D1D21, 0xC5C5CE) : (activeHover ? Palette.adaptive(0x48484F, 0xF5F5F8) : Palette.accent)
        } else {
            background = activePress ? Palette.adaptive(0xD3D3DC, 0x55555E) : (activeHover ? Palette.adaptive(0xE6E6ED, 0x45454D) : Palette.adaptive(0xFAFAFC, 0x323237))
        }
        let focused = keyboardFocused && isEnabled
        let outline = focused ? NSColor.keyboardFocusIndicatorColor : (primary ? background : Palette.adaptive(activeHover ? 0x9A9AA5 : 0xC9C9D1, activeHover ? 0x858591 : 0x62626D))
        let scale: CGFloat = activePress && !reduceMotion ? 0.96 : 1
        var transform = CATransform3DMakeScale(scale, scale, 1)
        transform.m41 = (0.5 - layer.anchorPoint.x) * bounds.width * (1 - scale)
        transform.m42 = (0.5 - layer.anchorPoint.y) * bounds.height * (1 - scale)
        let duration = reduceMotion ? 0.08 : (activePress ? 0.08 : (activeHover ? 0.14 : 0.18))
        let previous = layer.presentation() ?? layer
        let oldBackground = previous.backgroundColor
        let oldBorder = previous.borderColor
        let oldTransform = previous.transform
        var resolvedBackground: CGColor!
        var resolvedBorder: CGColor!
        control.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolvedBackground = background.cgColor; resolvedBorder = outline.cgColor
            control.contentTintColor = primary ? Palette.onAccent : Palette.ink
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.backgroundColor = resolvedBackground; layer.borderColor = resolvedBorder
        layer.borderWidth = focused ? 2 : 1; layer.cornerRadius = primary ? 17 : cornerRadius
        layer.opacity = isEnabled ? 1 : 0.4; layer.transform = transform
        CATransaction.commit()
        guard animated, control.window != nil else { layer.removeAllAnimations(); return }
        func animate(_ key: String, from: Any?, to: Any) {
            let animation = CABasicAnimation(keyPath: key)
            animation.fromValue = from; animation.toValue = to; animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            layer.add(animation, forKey: "feedback.\(key)")
        }
        animate("backgroundColor", from: oldBackground, to: resolvedBackground as Any)
        animate("borderColor", from: oldBorder, to: resolvedBorder as Any)
        if !reduceMotion { animate("transform", from: NSValue(caTransform3D: oldTransform), to: NSValue(caTransform3D: transform)) }
        else { layer.removeAnimation(forKey: "feedback.transform") }
}

private final class FeedbackButtonCell: NSButtonCell {
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let inset: CGFloat = title.isEmpty || imagePosition == .imageOnly ? 0 : 10
        super.drawInterior(withFrame: cellFrame.insetBy(dx: inset, dy: 0), in: controlView)
    }
    override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {
        super.highlight(flag, withFrame: cellFrame, in: controlView)
        (controlView as? FeedbackButton)?.setPressed(flag)
    }
}

/// Retains NSPopUpButton's selection, menu tracking and accessibility semantics.
final class FeedbackPopUpButton: NSPopUpButton {
    private var hovered = false
    fileprivate var menuIsOpen = false
    private var keyboardFocused = false
    private var pointerTracking: NSTrackingArea?
    private var lastLayoutSize: NSSize = .zero

    override init(frame buttonFrame: NSRect, pullsDown flag: Bool) {
        super.init(frame: buttonFrame, pullsDown: flag)
        cell = FeedbackPopUpButtonCell(textCell: "", pullsDown: flag)
        isBordered = false; wantsLayer = true; focusRingType = .exterior
        font = .systemFont(ofSize: 12)
        menu?.font = .systemFont(ofSize: 13)
        NotificationCenter.default.addObserver(self, selector: #selector(menuTrackingChanged(_:)), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuTrackingChanged(_:)), name: NSMenu.didEndTrackingNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        updateFeedback(animated: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    override var intrinsicContentSize: NSSize { NSSize(width: max(150, super.intrinsicContentSize.width + 40), height: 34) }
    override var isEnabled: Bool {
        didSet {
            if !isEnabled { hovered = false; menuIsOpen = false }
            updateFeedback(animated: window != nil); window?.invalidateCursorRects(for: self)
        }
    }
    override func updateTrackingAreas() {
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); pointerTracking = area; super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { if isEnabled { hovered = true; updateFeedback(animated: true) } }
    override func mouseExited(with event: NSEvent) { hovered = false; updateFeedback(animated: true) }
    override func resetCursorRects() { if isEnabled { addCursorRect(bounds, cursor: .pointingHand) } }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        menuIsOpen = true; updateFeedback(animated: true)
        super.mouseDown(with: event)
        menuIsOpen = false
        if let window { hovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) }
        updateFeedback(animated: true)
    }
    @objc private func menuTrackingChanged(_ notification: Notification) {
        guard let tracked = notification.object as? NSMenu, tracked === menu else { return }
        menuIsOpen = notification.name == NSMenu.didBeginTrackingNotification
        if !menuIsOpen, let window { hovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) }
        updateFeedback(animated: true)
    }
    override func becomeFirstResponder() -> Bool { let result = super.becomeFirstResponder(); keyboardFocused = result; updateFeedback(animated: true); return result }
    override func resignFirstResponder() -> Bool { let result = super.resignFirstResponder(); if result { keyboardFocused = false }; updateFeedback(animated: true); return result }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill() }
    override var focusRingMaskBounds: NSRect { bounds }
    override func layout() {
        super.layout(); menu?.minimumWidth = bounds.width
        if lastLayoutSize != bounds.size { lastLayoutSize = bounds.size; updateFeedback(animated: false) }
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); hovered = false; menuIsOpen = false; updateFeedback(animated: false) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateFeedback(animated: false) }
    @objc private func accessibilityChanged() { updateFeedback(animated: false) }
    private func updateFeedback(animated: Bool) {
        applyControlFeedback(self, hovered: hovered, pressed: menuIsOpen, keyboardFocused: keyboardFocused, animated: animated)
        needsDisplay = true
    }
}

private final class FeedbackPopUpButtonCell: NSPopUpButtonCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard let control = controlView as? FeedbackPopUpButton else { return }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 12), .foregroundColor: Palette.ink, .paragraphStyle: paragraph]
        let text = (selectedItem?.title ?? title) as NSString
        let textHeight = text.size(withAttributes: attributes).height
        text.draw(in: NSRect(x: cellFrame.minX + 36, y: cellFrame.midY - textHeight / 2, width: max(0, cellFrame.width - 66), height: textHeight), withAttributes: attributes)
        func drawSymbol(_ image: NSImage?, x: CGFloat, width: CGFloat) {
            guard let image = image?.withSymbolConfiguration(.init(paletteColors: [Palette.ink])), image.size.width > 0, image.size.height > 0 else { return }
            let scale = min(width / image.size.width, 14 / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: NSRect(x: x + (width - size.width) / 2, y: cellFrame.midY - size.height / 2, width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        drawSymbol(selectedItem?.image, x: cellFrame.minX + 12, width: 16)
        drawSymbol(symbol(control.menuIsOpen ? "chevron.up" : "chevron.down", size: 10), x: cellFrame.maxX - 25, width: 12)
    }
}

final class SurfaceView: NSView {
    var color: NSColor
    init(_ color: NSColor, cornerRadius: CGFloat = 0) {
        self.color = color
        super.init(frame: .zero)
        if cornerRadius > 0 {
            wantsLayer = true
            layer?.cornerRadius = cornerRadius
            layer?.masksToBounds = true
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) { color.setFill(); bounds.fill() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

/// Keep controls in the native glass content layer; editing content stays opaque.
func glassPanel(content: NSView, cornerRadius: CGFloat = 24, tint: NSColor? = nil) -> NSView {
    if #available(macOS 26.0, *) {
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = cornerRadius
        glass.tintColor = tint
        glass.contentView = content
        if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
        return glass
    }
    let effect: NSView
    if let tint {
        effect = SurfaceView(tint, cornerRadius: cornerRadius)
    } else {
        let material = NSVisualEffectView()
        material.material = .headerView
        material.blendingMode = .withinWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = cornerRadius
        material.layer?.masksToBounds = true
        effect = material
    }
    content.translatesAutoresizingMaskIntoConstraints = false
    effect.addSubview(content)
    NSLayoutConstraint.activate([
        content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
        content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
        content.topAnchor.constraint(equalTo: effect.topAnchor),
        content.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
    ])
    return effect
}

/// An explicit glass surface keeps button chrome stable inside native stacks.
func controlCapsule(_ control: NSButton, primary: Bool = false) -> NSView {
    if let button = control as? FeedbackButton {
        button.primary = primary
        return button
    }
    control.isBordered = false
    control.contentTintColor = primary ? Palette.onAccent : Palette.ink
    let capsule = glassPanel(content: control, cornerRadius: 17, tint: primary ? Palette.accent : nil)
    capsule.translatesAutoresizingMaskIntoConstraints = false
    capsule.heightAnchor.constraint(equalToConstant: 34).isActive = true
    return capsule
}

/// The dot-and-j monogram in Resources/icon.svg, drawn natively at any size.
final class LogoView: NSView {
    var badge: Bool
    init(badge: Bool = true) { self.badge = badge; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        if badge {
            Palette.accent.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: bounds.width * 0.25, yRadius: bounds.width * 0.25).fill()
        }
        let scale = min(bounds.width, bounds.height) / 64
        let origin = NSPoint(x: bounds.midX - 32 * scale, y: bounds.midY + 32 * scale)
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: origin.x + x * scale, y: origin.y - y * scale)
        }
        let color = badge ? Palette.onAccent : Palette.accent
        color.setFill()
        let dot = point(36, 20)
        NSBezierPath(ovalIn: NSRect(x: dot.x, y: dot.y, width: 8 * scale, height: 8 * scale)).fill()
        color.setStroke()
        let stroke = NSBezierPath()
        stroke.lineWidth = 7 * scale
        stroke.lineCapStyle = .round
        stroke.move(to: point(37.5, 28))
        stroke.line(to: point(34.5, 41.5))
        stroke.curve(to: point(20, 43), controlPoint1: point(33, 48.5), controlPoint2: point(23, 50))
        stroke.stroke()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

/// The rounded input surface owns focus chrome; the field editor keeps native text behavior.
final class TextInputSurface: NSView {
    private weak var field: NSTextField?
    private var focused = false
    private let showsRestingBorder: Bool
    init(field: NSTextField, showsRestingBorder: Bool = true) {
        self.field = field; self.showsRestingBorder = showsRestingBorder
        field.focusRingType = .none; field.cell?.focusRingType = .none
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = 10
        for name in [NSWindow.didUpdateNotification, NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowUpdated(_:)), name: name, object: nil)
        }
        updateBorder(animated: false)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshFocus() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateBorder(animated: false) }
    override func mouseDown(with event: NSEvent) { if let field { window?.makeFirstResponder(field); field.selectText(nil) } }
    @objc private func windowUpdated(_ notification: Notification) {
        guard let changed = notification.object as? NSWindow, changed === window else { return }
        refreshFocus()
    }
    private func refreshFocus() {
        let active = window?.isKeyWindow == true && field != nil && (window?.firstResponder === field || (field?.currentEditor() != nil && window?.firstResponder === field?.currentEditor()))
        guard active != focused else { return }
        focused = active; updateBorder(animated: true)
    }
    private func updateBorder(animated: Bool) {
        guard let layer else { return }
        let previous = (layer.presentation() ?? layer).borderColor
        let color = focused ? Palette.adaptive(0x73737E, 0xAEAEB9) : Palette.line
        CATransaction.begin(); CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = Palette.paper.cgColor; layer.borderColor = color.cgColor
        }
        layer.borderWidth = focused ? 1.5 : (showsRestingBorder ? 0.75 : 0)
        CATransaction.commit()
        if animated {
            let animation = CABasicAnimation(keyPath: "borderColor")
            animation.fromValue = previous; animation.toValue = layer.borderColor
            animation.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.08 : 0.14
            layer.add(animation, forKey: "inputFocus")
        }
    }
}
