import SwiftUI
import Engine
import Core

@available(macOS 14.2, *)
public struct AppRowView: View {
    let process: AudioProcess

    @State private var isExpanded = false
    @State private var engineManager = AudioEngineManager.shared

    private var isTapped: Bool {
        engineManager.activeNodes[process.bundleID] != nil
    }

    public init(process: AudioProcess) {
        self.process = process
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Main row header
            HStack(spacing: DS.m) {
                // App icon
                Group {
                    if let icon = process.icon {
                        Image(nsImage: icon)
                            .resizable()
                    } else {
                        Image(systemName: "app.dashed")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(DS.textTertiary)
                            .padding(2)
                    }
                }
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: DS.radiusS))

                // Name + live status
                Text(process.name)
                    .font(DSFont.rowTitle)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)

                if process.isRunningOutput {
                    Circle()
                        .fill(DS.playing)
                        .frame(width: 6, height: 6)
                        .shadow(color: DS.playing.opacity(0.7), radius: 3)
                }

                Spacer(minLength: DS.s)

                // VU meter — only animates when tapped AND producing audio
                VUMeterView(isActive: isTapped && process.isRunningOutput)

                // Capture toggle
                Button(action: toggleTap) {
                    Image(systemName: isTapped ? "power.circle.fill" : "power.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(isTapped ? DS.accent : DS.textTertiary)
                }
                .buttonStyle(.plain)
                .help(isTapped ? "Stop capturing this app" : "Capture this app's audio")

                // Expand chevron
                Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isExpanded.toggle() } }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isTapped ? DS.textSecondary : DS.textTertiary.opacity(0.5))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .disabled(!isTapped)
            }
            .padding(.horizontal, DS.l)
            .padding(.vertical, DS.m)
            .background(isExpanded ? DS.surfaceHi : Color.clear)

            // Expanded controls
            if isExpanded && isTapped {
                if let appNode = engineManager.activeNodes[process.bundleID] {
                    AppControlsView(bundleID: process.bundleID, eqController: appNode.eqController)
                        .padding(.horizontal, DS.l)
                        .padding(.bottom, DS.m)
                        .background(DS.surfaceHi)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            Rectangle().fill(DS.stroke.opacity(0.6)).frame(height: 1)
        }
    }

    private func toggleTap() {
        if isTapped {
            isExpanded = false
            engineManager.stopAppTapping(bundleID: process.bundleID)
        } else {
            engineManager.startAppTapping(bundleID: process.bundleID, pid: process.pid)
        }
    }
}

// Animated VU meter — warm level gradient (green → amber → coral)
struct VUMeterView: View {
    let isActive: Bool
    @State private var levels: [CGFloat] = Array(repeating: 0.1, count: 6)

    private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    private func color(_ idx: Int) -> Color {
        idx > 4 ? DS.danger : (idx > 3 ? DS.warning : DS.playing)
    }

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<6, id: \.self) { idx in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(isActive ? color(idx) : DS.textTertiary.opacity(0.25))
                    .frame(width: 2, height: levels[idx] * 12)
            }
        }
        .frame(width: 22, height: 12)
        .onReceive(timer) { _ in
            guard isActive else {
                levels = Array(repeating: 0.1, count: 6)
                return
            }
            withAnimation(.spring(response: 0.12, dampingFraction: 0.55)) {
                levels = (0..<6).map { _ in CGFloat.random(in: 0.15...1.0) }
            }
        }
    }
}
