// NightstandWalkView.swift — "Nightstand Walk" (spec §7.2): the
// phone sideways on the charger at night becomes a dark, quiet
// scene where her tiny footprints walk across, one by one, under a
// soft clock. This is the honest form of the lock-screen wish —
// the one posture where iOS lets a screen be alive like this.
// Tap anywhere to leave.

import SwiftUI
import UIKit

struct NightstandWalkView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var steps: [UIImage] = []
    @State private var shown: Int = 0
    @State private var fading: Bool = false
    @State private var showHint: Bool = true
    @State private var usingPlaceholders: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { geo in
                // Soft clock, top-left, dim enough to sleep beside.
                VStack {
                    HStack {
                        TimelineView(.everyMinute) { ctx in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ctx.date, format: .dateTime.hour().minute())
                                    .font(.system(size: 44, weight: .thin, design: .rounded))
                                    .foregroundColor(.white.opacity(0.55))
                                Text(ctx.date, format: .dateTime.weekday(.wide).month().day())
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundColor(.white.opacity(0.35))
                            }
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.leading, 36)
                .padding(.top, 30)

                // The walk.
                ForEach(steps.indices, id: \.self) { i in
                    if i < shown {
                        let n = max(steps.count, 1)
                        let t = n == 1 ? 0.5 : Double(i) / Double(n - 1)
                        Image(uiImage: steps[i])
                            .resizable()
                            .scaledToFit()
                            .frame(width: min(170, geo.size.width * 0.20))
                            .scaleEffect(x: i % 2 == 1 ? -1 : 1, y: 1)
                            .rotationEffect(.degrees(i % 2 == 0 ? -9 : 9))
                            .position(x: geo.size.width * (0.10 + 0.80 * t),
                                      y: geo.size.height * 0.60 + (i % 2 == 0 ? -26 : 26))
                            .transition(.opacity.combined(with: .scale(scale: 1.25)))
                    }
                }
                .opacity(fading ? 0 : 1)

                if showHint {
                    VStack {
                        Spacer()
                        if usingPlaceholders {
                            // Honesty on screen: before the first
                            // real print, the walk uses starter
                            // prints — and says so, out loud.
                            Text("These are starter prints — her own footprints will walk here once you've made one.")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundColor(.white.opacity(0.45))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                                .padding(.bottom, 6)
                        }
                        Text("Tap anywhere to close")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.bottom, 16)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .task { await prepare() }
        .task { await runLoop() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func prepare() async {
        let child = store.activeChild
        var images: [UIImage] = []
        if let child {
            let prints = store.prints(for: child.id)
            let feet = prints.filter { $0.kind == .foot }
            let source = feet.isEmpty ? prints : feet
            for record in source.prefix(6) {
                if let img = PrintRenderer.image(for: record, longEdgePx: 640) {
                    images.append(img)
                }
            }
        }
        if images.isEmpty {
            // Before the first real print: gentle placeholders in a
            // warm sand ink, labeled on screen as starter prints —
            // the walk fills with her real prints as the book grows.
            usingPlaceholders = true
            let months = child.map { ageInMonths(birth: $0.birthDate, at: Date()) } ?? 3.5
            let shape = PrintRenderer.silhouetteShape(kind: .foot, ageMonths: months,
                                                      lengthMM: 88,
                                                      mmPerPoint: ScreenMetrics.mmPerPoint)
            for seed: UInt64 in [3, 4] {
                if let img = PrintRenderer.image(shape: shape,
                                                 color: InkColor(hex: "#C9AE7E"),
                                                 material: .paint, seed: seed,
                                                 longEdgePx: 640) {
                    images.append(img)
                }
            }
        }
        steps = images
    }

    private func runLoop() async {
        try? await Task.sleep(for: .seconds(3))
        withAnimation { showHint = false }
        while !Task.isCancelled {
            if steps.isEmpty {
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            // One print at a time stamps in.
            for i in 0..<steps.count {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    shown = i + 1
                }
                try? await Task.sleep(for: .seconds(1.7))
                if Task.isCancelled { return }
            }
            // Linger, then fade and begin again.
            try? await Task.sleep(for: .seconds(4.5))
            withAnimation(.easeInOut(duration: 1.6)) { fading = true }
            try? await Task.sleep(for: .seconds(1.8))
            shown = 0
            withAnimation(.easeInOut(duration: 0.8)) { fading = false }
            try? await Task.sleep(for: .seconds(1.2))
        }
    }
}
