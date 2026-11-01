// CaptureEngine.swift — the ink pad itself: a multi-touch surface
// that samples real contact (spec §2.1–2.2, §2.4).
//
// Ergonomics law (one parent arm): no precision taps anywhere; touches
// starting near the screen edges are ignored (home-indicator safety,
// and a parent's holding palm must not poison the print — the geometry
// engine additionally drops outlier clusters). Sampling ends on
// lift-off, on the big Done button, or after 1.4 s.

import UIKit
import SwiftUI

public final class PadControl: ObservableObject {
    public weak var padView: PadUIView?
    public init() {}
    public func finish() { padView?.finishEarly() }
    public func reset() { padView?.begin() }
}

public final class PadUIView: UIView {
    public var onFinish: (([ContactSample], Bool) -> Void)?
    public var onProgress: ((Int) -> Void)?

    private(set) var samples: [ContactSample] = []
    private var startTime: TimeInterval = 0
    private var activeTouchCount = 0
    private var finished = false
    private var maxTimer: Timer?
    private let edgeInset: CGFloat = 26

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PadUIView is programmatic") }

    public func begin() {
        samples = []
        finished = false
        startTime = 0
        activeTouchCount = 0
        maxTimer?.invalidate()
    }

    private func record(_ touches: Set<UITouch>, event: UIEvent?) {
        guard !finished, let event else { return }
        if startTime == 0 {
            startTime = event.timestamp
            maxTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) {
                [weak self] _ in self?.finish(endedByLift: false)
            }
        }
        for touch in touches {
            let all = event.coalescedTouches(for: touch) ?? [touch]
            for t in all {
                let p = t.location(in: self)
                if p.x < edgeInset || p.y < edgeInset ||
                    p.x > bounds.width - edgeInset || p.y > bounds.height - edgeInset {
                    continue
                }
                samples.append(ContactSample(x: Double(p.x), y: Double(p.y),
                                             radius: Double(max(t.majorRadius, 2)),
                                             t: event.timestamp - startTime))
            }
        }
        onProgress?(samples.count)
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeTouchCount += touches.count
        record(touches, event: event)
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        record(touches, event: event)
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        record(touches, event: event)
        activeTouchCount = max(0, activeTouchCount - touches.count)
        if activeTouchCount == 0, !samples.isEmpty {
            finish(endedByLift: true)
        }
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    public func finishEarly() {
        if !samples.isEmpty { finish(endedByLift: false) }
    }

    private func finish(endedByLift: Bool) {
        guard !finished else { return }
        finished = true
        maxTimer?.invalidate()
        onFinish?(samples, endedByLift)
    }
}

public struct PadSurface: UIViewRepresentable {
    public var control: PadControl
    public var onProgress: (Int) -> Void
    public var onFinish: ([ContactSample], Bool) -> Void

    public init(control: PadControl,
                onProgress: @escaping (Int) -> Void,
                onFinish: @escaping ([ContactSample], Bool) -> Void) {
        self.control = control
        self.onProgress = onProgress
        self.onFinish = onFinish
    }

    public func makeUIView(context: Context) -> PadUIView {
        let v = PadUIView()
        v.onProgress = onProgress
        v.onFinish = onFinish
        control.padView = v
        return v
    }

    public func updateUIView(_ uiView: PadUIView, context: Context) {
        uiView.onProgress = onProgress
        uiView.onFinish = onFinish
        control.padView = uiView
    }
}
