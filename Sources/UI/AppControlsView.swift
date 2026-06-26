import SwiftUI
import CoreAudio
import Engine

@available(macOS 14.2, *)
public struct AppControlsView: View {
    let bundleID: String
    let eqController: EQController

    @State private var volume: Float = 1.0
    @State private var isMuted = false
    @State private var isEQBypassed = false

    public init(bundleID: String, eqController: EQController) {
        self.bundleID = bundleID
        self.eqController = eqController
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.m) {
            // Routing
            HStack(spacing: DS.s) {
                Label {
                    Text("ROUTE TO")
                        .font(DSFont.label)
                        .tracking(0.8)
                        .foregroundStyle(DS.textTertiary)
                } icon: {
                    Image(systemName: "arrow.turn.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DS.accent)
                }

                Spacer()

                OutputDevicePicker(
                    selection: Binding(
                        get: { AudioEngineManager.shared.getAppOutputDevice(bundleID: bundleID) },
                        set: { AudioEngineManager.shared.setAppOutputDevice(bundleID: bundleID, deviceID: $0) }
                    ),
                    includeDefault: true
                )
            }

            // Volume + EQ toggle
            HStack(spacing: DS.m) {
                Button(action: toggleMute) {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(isMuted ? DS.danger : DS.textSecondary)
                        .frame(width: 18, height: 16)
                }
                .buttonStyle(.plain)

                Slider(value: $volume, in: 0.0...2.0)
                    .controlSize(.mini)
                    .tint(DS.accent)
                    .onChange(of: volume) { _, newValue in
                        AudioEngineManager.shared.setVolume(bundleID: bundleID, volume: newValue)
                    }

                Text("\(Int(volume * 100))%")
                    .font(DSFont.mono)
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 34, alignment: .trailing)

                Button(action: toggleEQBypass) {
                    Text(isEQBypassed ? "EQ OFF" : "EQ ON")
                        .font(DSFont.label)
                        .tracking(0.5)
                        .padding(.horizontal, DS.s)
                        .padding(.vertical, DS.xs)
                        .background(isEQBypassed ? DS.stroke : DS.accentDim)
                        .foregroundStyle(isEQBypassed ? DS.textTertiary : DS.accent)
                        .clipShape(RoundedRectangle(cornerRadius: DS.radiusS))
                }
                .buttonStyle(.plain)
            }

            // EQ curve
            if !isEQBypassed {
                EQCurveEditor(
                    eqController: eqController,
                    spectrum: AudioEngineManager.shared.activeNodes[bundleID]?.spectrumTap
                )
                .transition(.opacity)
            }
        }
        .padding(.vertical, DS.s)
        .onAppear {
            self.volume = AudioEngineManager.shared.getVolume(bundleID: bundleID)
            self.isMuted = AudioEngineManager.shared.getMute(bundleID: bundleID)
            self.isEQBypassed = eqController.avAudioUnit.bypass
        }
    }

    private func toggleMute() {
        isMuted.toggle()
        AudioEngineManager.shared.setMute(bundleID: bundleID, muted: isMuted)
    }

    private func toggleEQBypass() {
        withAnimation(.easeInOut(duration: 0.2)) { isEQBypassed.toggle() }
        eqController.setBypass(isEQBypassed)
    }
}
