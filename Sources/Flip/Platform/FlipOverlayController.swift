import AppKit
import QuartzCore

@MainActor
protocol FlipOverlayControlling: AnyObject {
    var currentFrame: CGRect? { get }
    var onFlipBack: (@MainActor () -> Void)? { get set }
    func presentOccupying(
        frame: CGRect,
        frontSnapshot: NSImage,
        destinationURL: URL,
        reducesMotion: Bool,
        onFinished: @escaping @MainActor () -> Void
    )
    func restore(
        reducesMotion: Bool,
        onFinished: @escaping @MainActor (CGRect) -> Void
    )
    func dismissImmediately()
}

@MainActor
final class FlipOverlayController: NSObject, FlipOverlayControlling, NSWindowDelegate {
    var onFlipBack: (@MainActor () -> Void)?

    private var window: FlipOccupancyWindow?
    private var cardView: FlipCardHostView?
    private var notionHost: FlipNotionHost?
    private var onFinishedOccupying: (@MainActor () -> Void)?
    private var onFinishedRestore: (@MainActor (CGRect) -> Void)?

    var currentFrame: CGRect? {
        window?.frame
    }

    func presentOccupying(
        frame: CGRect,
        frontSnapshot: NSImage,
        destinationURL: URL,
        reducesMotion: Bool,
        onFinished: @escaping @MainActor () -> Void
    ) {
        dismissImmediately()
        onFinishedOccupying = onFinished
        let window = FlipOverlayPolicy.makeWindow(frame: frame)
        window.delegate = self
        window.animationBehavior = .none
        let host = FlipNotionHost()
        host.load(destinationURL)
        let card = FlipCardHostView(frame: NSRect(origin: .zero, size: frame.size))
        card.autoresizingMask = [.width, .height]
        card.onFlipBack = { [weak self] in
            self?.onFlipBack?()
        }
        card.frontImage = frontSnapshot
        card.installBackContent(host.webView)
        window.contentView = card
        self.window = window
        cardView = card
        notionHost = host
        window.makeKeyAndOrderFront(nil)
        card.flipToBack(
            duration: FlipMotionPolicy.duration(reducesMotion: reducesMotion),
            useCardFlip: FlipMotionPolicy.shouldUseCardFlip(reducesMotion: reducesMotion)
        ) { [weak self] in
            self?.onFinishedOccupying?()
            self?.onFinishedOccupying = nil
        }
    }

    func restore(
        reducesMotion: Bool,
        onFinished: @escaping @MainActor (CGRect) -> Void
    ) {
        guard let window, let cardView else {
            onFinished(.zero)
            dismissImmediately()
            return
        }
        onFinishedRestore = onFinished
        let frame = window.frame
        cardView.flipToFront(
            duration: FlipMotionPolicy.duration(reducesMotion: reducesMotion),
            useCardFlip: FlipMotionPolicy.shouldUseCardFlip(reducesMotion: reducesMotion)
        ) { [weak self] in
            self?.onFinishedRestore?(frame)
            self?.onFinishedRestore = nil
            self?.dismissImmediately()
        }
    }

    func dismissImmediately() {
        window?.delegate = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        cardView = nil
        notionHost = nil
        onFinishedOccupying = nil
        onFinishedRestore = nil
    }
}

@MainActor
final class FlipCardHostView: NSView {
    var onFlipBack: (@MainActor () -> Void)?

    private let sceneLayer = CALayer()
    private let frontLayer = CALayer()
    private let backLayer = CALayer()
    private let chrome = FlipOccupancyChromeView()
    private let backContent = NSView()
    private var completion: (@MainActor () -> Void)?

    var frontImage: NSImage? {
        didSet {
            frontLayer.contents = frontImage
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        sceneLayer.masksToBounds = true
        var perspective = CATransform3DIdentity
        perspective.m34 = -FlipMotionPolicy.perspective
        sceneLayer.sublayerTransform = perspective
        frontLayer.isDoubleSided = false
        backLayer.isDoubleSided = false
        backLayer.transform = CATransform3DMakeRotation(CGFloat.pi, 0, 1, 0)
        layer?.addSublayer(sceneLayer)
        sceneLayer.addSublayer(backLayer)
        sceneLayer.addSublayer(frontLayer)
        backContent.wantsLayer = true
        chrome.onFlipBack = { [weak self] in
            self?.onFlipBack?()
        }
        addSubview(backContent)
        backContent.addSubview(chrome)
        backContent.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func installBackContent(_ webView: NSView) {
        webView.translatesAutoresizingMaskIntoConstraints = false
        chrome.translatesAutoresizingMaskIntoConstraints = false
        backContent.addSubview(webView, positioned: .below, relativeTo: chrome)
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: backContent.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: backContent.trailingAnchor),
            chrome.topAnchor.constraint(equalTo: backContent.topAnchor),
            chrome.heightAnchor.constraint(equalToConstant: FlipOverlayPolicy.chromeHeight),
            webView.leadingAnchor.constraint(equalTo: backContent.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: backContent.trailingAnchor),
            webView.topAnchor.constraint(equalTo: chrome.bottomAnchor),
            webView.bottomAnchor.constraint(equalTo: backContent.bottomAnchor),
        ])
    }

    override func layout() {
        super.layout()
        let bounds = layer?.bounds ?? self.bounds
        sceneLayer.frame = bounds
        frontLayer.frame = sceneLayer.bounds
        backLayer.frame = sceneLayer.bounds
        backContent.frame = self.bounds
    }

    func flipToBack(
        duration: TimeInterval,
        useCardFlip: Bool,
        completion: @escaping @MainActor () -> Void
    ) {
        animate(
            to: CATransform3DMakeRotation(CGFloat.pi, 0, 1, 0),
            duration: duration,
            useCardFlip: useCardFlip,
            revealBack: true,
            completion: completion
        )
    }

    func flipToFront(
        duration: TimeInterval,
        useCardFlip: Bool,
        completion: @escaping @MainActor () -> Void
    ) {
        animate(
            to: CATransform3DIdentity,
            duration: duration,
            useCardFlip: useCardFlip,
            revealBack: false,
            completion: completion
        )
    }

    private func animate(
        to transform: CATransform3D,
        duration: TimeInterval,
        useCardFlip: Bool,
        revealBack: Bool,
        completion: @escaping @MainActor () -> Void
    ) {
        self.completion = completion
        if !useCardFlip {
            backContent.isHidden = !revealBack
            sceneLayer.transform = transform
            completion()
            self.completion = nil
            return
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(
            CAMediaTimingFunction(name: .easeInEaseOut)
        )
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.backContent.isHidden = !revealBack
                let finished = self.completion
                self.completion = nil
                finished?()
            }
        }
        sceneLayer.transform = transform
        CATransaction.commit()
        let halfDuration = duration / 2
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(halfDuration))
            self?.backContent.isHidden = !revealBack
        }
    }
}

@MainActor
final class FlipOccupancyChromeView: NSView {
    var onFlipBack: (@MainActor () -> Void)?

    private let button = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        button.title = "Flip back"
        button.bezelStyle = .flexiblePush
        button.target = self
        button.action = #selector(flipBack)
        button.setButtonType(.momentaryPushIn)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    @objc private func flipBack() {
        onFlipBack?()
    }
}
