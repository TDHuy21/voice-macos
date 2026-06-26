import SwiftUI
import Observation
import Core
import Engine

@available(macOS 14.2, *)
public struct PopoverContentView: View {
    @State private var enumerator = AudioProcessEnumerator()
    @State private var engineManager = AudioEngineManager.shared
    @State private var store = PresetStore.shared
    
    @State private var selectedPresetName: String = "Flat"
    @State private var showSaveAlert = false
    @State private var newPresetName = ""

    // Poll the audio process list while the popover is open. CoreAudio's process-object
    // list listener only fires when processes are added/removed — not when an already
    // running app STARTS or STOPS producing output (its isRunningOutput flag flips but
    // the object list is unchanged). Polling keeps the list live for play/pause events.
    private let refreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    public init() {}

    // Show every running audio-capable foreground app (Spotify, Chrome, Discord…) even
    // when it's silent, so the user can pre-set EQ; the list updates in realtime as apps
    // open/close. System daemons are excluded (isRegularApp == false). A green dot marks
    // the ones actually producing audio right now (isRunningOutput).
    private var visibleProcesses: [AudioProcess] {
        AudioProcess.visibleRows(
            from: enumerator.processes,
            tappedBundleIDs: Set(engineManager.activeNodes.keys)
        )
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header — serif wordmark (signature detail) + device, then preset row
            VStack(spacing: DS.m) {
                HStack(spacing: DS.s) {
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.accent)
                    Text("SoundsSource")
                        .font(DSFont.wordmark)
                        .foregroundStyle(DS.textPrimary)

                    Spacer(minLength: DS.s)

                    OutputDevicePicker(selection: Bindable(engineManager).selectedDeviceID)
                }

                HStack(spacing: DS.s) {
                    Text("PRESET")
                        .font(DSFont.label)
                        .tracking(0.8)
                        .foregroundStyle(DS.textTertiary)

                    Picker("", selection: $selectedPresetName) {
                        ForEach(store.presets) { preset in
                            Text(preset.name).tag(preset.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(DS.accent)
                    .frame(width: 120)
                    .onChange(of: selectedPresetName) { _, newValue in
                        engineManager.loadPreset(name: newValue)
                    }

                    Spacer()
                }
            }
            .padding(.horizontal, DS.l)
            .padding(.vertical, DS.m)
            .background(DS.surface)

            Rectangle().fill(DS.stroke).frame(height: 1)

            // App List
            ProcessListView(processes: visibleProcesses)

            Rectangle().fill(DS.stroke).frame(height: 1)

            // Footer — Save Preset & Quit
            HStack {
                Button(action: { showSaveAlert = true }) {
                    Label("Save Preset", systemImage: "plus.circle.fill")
                        .font(DSFont.caption)
                        .foregroundStyle(DS.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { NSApp.terminate(nil) }) {
                    Text("Quit")
                        .font(DSFont.caption)
                        .foregroundStyle(DS.danger.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DS.l)
            .padding(.vertical, DS.m)
            .background(DS.surface)
        }
        .frame(width: 360)
        .background(DS.bg)
        .tint(DS.accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSaveAlert) {
            VStack(alignment: .leading, spacing: DS.m) {
                Text("Save Preset")
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundStyle(DS.textPrimary)

                Text("Capture the current EQ, volume and routing for every active app.")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Preset name", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.regular)
                    .tint(DS.accent)

                HStack(spacing: DS.s) {
                    Spacer()
                    Button("Cancel") {
                        showSaveAlert = false
                        newPresetName = ""
                    }
                    .controlSize(.regular)

                    Button("Save") {
                        if !newPresetName.isEmpty {
                            engineManager.saveCurrentStateAsPreset(name: newPresetName)
                            selectedPresetName = newPresetName
                        }
                        showSaveAlert = false
                        newPresetName = ""
                    }
                    .controlSize(.regular)
                    .buttonStyle(.borderedProminent)
                    .tint(DS.accent)
                    .disabled(newPresetName.isEmpty)
                }
            }
            .padding(DS.l)
            .frame(width: 260)
            .background(DS.surface)
        }
        .onReceive(refreshTimer) { _ in
            enumerator.refresh()
        }
        .onAppear {
            enumerator.refresh()
            if let def = store.defaultPreset {
                selectedPresetName = def.name
            }
        }
    }
}
