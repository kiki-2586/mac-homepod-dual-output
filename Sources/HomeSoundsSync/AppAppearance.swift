import AppKit

/// Public macOS 26 API resolved at runtime so the app can still build with the
/// project's macOS 15 SDK. Older systems use AppKit's visual-effect material.
final class GlassPanel: NSView {
    let content = NSView()
    let usesNativeGlass: Bool

    init(radius: CGFloat = 18) {
        let surface: NSView
        if #available(macOS 26.0, *),
           let glassType = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glass = glassType.init(frame: .zero)
            glass.setValue(radius, forKey: "cornerRadius")
            glass.setValue(content, forKey: "contentView")
            surface = glass
            usesNativeGlass = true
        } else {
            let effect = NSVisualEffectView()
            effect.material = .sidebar
            effect.blendingMode = .withinWindow
            effect.wantsLayer = true
            effect.layer?.cornerRadius = radius
            effect.layer?.masksToBounds = true
            effect.addSubview(content)
            surface = effect
            usesNativeGlass = false
        }
        super.init(frame: .zero)
        addSubview(surface)
        surface.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        if !usesNativeGlass {
            content.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
                content.topAnchor.constraint(equalTo: surface.topAnchor),
                content.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
            ])
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class DeviceCard: NSStackView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 0.5
        refreshColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }
    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.68).cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.42).cgColor
        }
    }
}

private final class FlippedDocument: NSView {
    override var isFlipped: Bool { true }
}

/// Keep short lists at the top; grow the document only when rows need scrolling.
final class DeviceListScrollView: NSScrollView {
    private let stack: NSStackView
    private let document = FlippedDocument()

    init(stack: NSStackView) {
        self.stack = stack
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        documentView = document
        document.addSubview(stack)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let width = contentView.bounds.width
        stack.setFrameSize(NSSize(width: width, height: stack.fittingSize.height))
        stack.layoutSubtreeIfNeeded()
        let height = stack.fittingSize.height
        document.frame = NSRect(x: 0, y: 0, width: width, height: max(height, contentView.bounds.height))
        stack.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }
}
