import SwiftUI
import Engine
import AppKit

/// Eye-rest timer control panel embedded in the popover (5.1–5.4).
/// Contains duration inputs, Start/Stop button, status display,
/// and Accessibility permission guidance.
@available(macOS 14.2, *)
public struct EyeRestTimerView: View {

    @State private var manager = BreakTimerManager.shared

    // Local string-backed storage for the text fields (so we can validate).
    @State private var studyMinutesText: String = ""
    @State private var breakMinutesText: String = ""
    @State private var showAccessibilityAlert = false

    public init() {}

    // MARK: - Body

    public var body: some View {
        VStack(spacing: DS.m) {
            // Section header
            HStack {
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.accent)
                Text("Nghỉ mắt")
                    .font(DSFont.label)
                    .foregroundStyle(DS.textPrimary)
                Spacer()
                // 5.3: Status badge — visible even when popover is open
                if manager.phase != .idle {
                    statusBadge
                }
            }

            // 5.1: Duration inputs
            HStack(spacing: DS.s) {
                durationField(
                    label: "Học (phút)",
                    text: $studyMinutesText,
                    placeholder: "25"
                )
                durationField(
                    label: "Nghỉ (phút)",
                    text: $breakMinutesText,
                    placeholder: "1"
                )
            }

            // 5.4: Accessibility degraded-mode notice
            if manager.phase != .idle && !manager.hardLockAvailable {
                HStack(spacing: DS.xs) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(DS.accent)
                        .font(.system(size: 11))
                    Text("Chế độ overlay-only (chưa cấp Accessibility)")
                        .font(DSFont.caption)
                        .foregroundStyle(DS.textSecondary)
                    Spacer()
                    Button("Cấp quyền") {
                        showAccessibilityAlert = true
                    }
                    .font(DSFont.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.accent)
                }
                .padding(DS.xs + 2)
                .background(DS.accent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: DS.radiusS))
            }

            // 5.2: Start / Stop button
            startStopButton
        }
        .padding(DS.m)
        .background(DS.surfaceHi)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusM))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusM)
                .strokeBorder(DS.stroke, lineWidth: DS.borderWidth)
        )
        .onAppear { loadFromManager() }
        .alert("Cấp quyền Accessibility", isPresented: $showAccessibilityAlert) {
            Button("Mở System Settings") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            }
            Button("Đóng", role: .cancel) {}
        } message: {
            Text("Vào System Settings → Privacy & Security → Accessibility, rồi bật SoundsSource. Sau đó nhấn Stop và Start lại để áp dụng.")
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(manager.phase == .breaking ? DS.danger : DS.accent)
                .frame(width: 6, height: 6)
            Text(statusLabel)
                .font(DSFont.caption)
                .foregroundStyle(manager.phase == .breaking ? DS.danger : DS.accent)
                .monospacedDigit()
        }
        .padding(.horizontal, DS.s)
        .padding(.vertical, 3)
        .background((manager.phase == .breaking ? DS.danger : DS.accent).opacity(0.12))
        .clipShape(Capsule())
    }

    private var statusLabel: String {
        let t = max(0, Int(manager.remaining))
        let m = t / 60; let s = t % 60
        let time = String(format: "%02d:%02d", m, s)
        switch manager.phase {
        case .studying: return "📖 \(time)"
        case .warning:  return "⚠️ \(time)"
        case .breaking: return "😌 \(time)"
        case .idle:     return ""
        }
    }

    @ViewBuilder
    private var startStopButton: some View {
        let isRunning = manager.phase != .idle
        let valid = validateInputs()

        Button {
            if isRunning {
                manager.stop()
            } else {
                commitToManager()
                manager.start()
                // 5.4: If Accessibility wasn't granted, show guidance.
                if !manager.hardLockAvailable {
                    showAccessibilityAlert = true
                }
            }
        } label: {
            HStack(spacing: DS.xs) {
                Image(systemName: isRunning ? "stop.circle.fill" : "play.circle.fill")
                Text(isRunning ? "Dừng" : "Bắt đầu")
                    .fontWeight(.bold)
            }
            .font(DSFont.control)
            .foregroundStyle(isRunning ? DS.danger : DS.bg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.s + 2)
            .background(isRunning ? DS.danger.opacity(0.15) : DS.accent)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusM))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusM)
                    .strokeBorder(DS.stroke, lineWidth: DS.borderWidth)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isRunning && !valid)
        .opacity((!isRunning && !valid) ? 0.45 : 1.0)
        .hoverEffectHelper()
    }

    @ViewBuilder
    private func durationField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(DSFont.caption)
                .foregroundStyle(DS.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(DSFont.control)
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.s)
                .padding(.vertical, DS.xs + 2)
                .background(DS.surface)
                .clipShape(RoundedRectangle(cornerRadius: DS.radiusS))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusS)
                        .strokeBorder(DS.stroke, lineWidth: DS.borderWidth)
                )
                .disabled(manager.phase != .idle)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Validation & persistence helpers

    private func validateInputs() -> Bool {
        guard let m = Double(studyMinutesText), m > 0,
              let b = Double(breakMinutesText), b > 0 else { return false }
        return true
    }

    private func commitToManager() {
        if let m = Double(studyMinutesText), m > 0 {
            manager.studyDuration = m * 60
        }
        if let b = Double(breakMinutesText), b > 0 {
            manager.breakDuration = b * 60  // phút → giây
        }
    }

    private func loadFromManager() {
        studyMinutesText = String(format: "%.0f", manager.studyDuration / 60)
        breakMinutesText = String(format: "%.0f", manager.breakDuration / 60)
    }
}
