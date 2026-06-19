# SoundsSource

A macOS menu bar app for **per-application audio control**. Capture the audio of any running app, then adjust its volume, mute it, apply a 10-band parametric EQ, and route it to any output device — independently of every other app.

Built on CoreAudio process taps (`AudioHardwareCreateProcessTap`) and AVAudioEngine.

> Requires **macOS 14.2+** — process audio tapping uses `CATapDescription` / `AudioHardwareCreateProcessTap`, available only on macOS 14.2 and later.

## Features

- **Per-app capture** — tap the audio output of any individual app (Spotify, browsers, Discord, games…).
- **Per-app volume & mute** — independent volume slider and mute toggle for each captured app.
- **10-band parametric EQ** — per-app equalizer (32 Hz – 16 kHz) with an interactive curve editor.
- **Per-app output routing** — send each app to a different output device (e.g. Spotify → headphones, game → speakers).
- **Presets** — save and restore volume + EQ configurations across apps; set a default applied on launch.
- **Smart process list** — only shows apps currently producing audio. Helper/renderer processes (Chrome, Cốc Cốc, Discord) resolve to their parent app's name and icon.
- **Live device handling** — follows the system default output and migrates active apps when devices are plugged/unplugged.

## Install

Download **SoundsSource.dmg** from the [latest release](https://github.com/songoku-03/voice-macos/releases/latest), open it, and drag the app into **Applications**.

The app is ad-hoc signed (not notarized), so on first launch macOS may block it. To open:

- Right-click the app in Applications → **Open** → **Open**, or
- Remove the quarantine flag:
  ```bash
  xattr -dr com.apple.quarantine /Applications/SoundsSource.app
  ```

On first launch, grant **audio recording permission** when prompted — required to capture process audio.

## Build

```bash
# Build a signed .app bundle (ad-hoc, ready to launch) → build/SoundsSource.app
./scripts/build_app.sh

# Debug bundle
./scripts/build_app.sh --debug

# Package a drag-to-install disk image → build/SoundsSource.dmg
./scripts/build_dmg.sh

# Compile only, no bundle
swift build -c release
```

Launch with `open build/SoundsSource.app`. A waveform icon appears in the menu bar.

### Requirements

- macOS 14.2 or later
- Swift 6 toolchain (Xcode 16+ command line tools)
- Runs **without the sandbox** (required for process audio tapping), with entitlements `com.apple.security.system-audio-capture` and `com.apple.security.temporary-exception.audio-unit-host`
- No Apple Developer account needed for local ad-hoc signing (notarization requires one)

## Usage

1. Click the menu bar icon to open the popover.
2. The list shows every app currently playing audio.
3. Click the **power button** on a row to start capturing that app.
4. Expand the row (chevron) for:
   - **Volume** slider and **mute** toggle
   - **Route to** — output device for that app
   - **EQ** — toggle and edit the 10-band curve
5. **Save Preset** stores the current volume/EQ across all apps; the preset picker (top-left) switches between saved presets.

## Architecture

Three library targets plus the executable, in a strict dependency chain:

```
SoundsSource (executable) → UI → Engine → Core
```

### `Sources/Core/` — low-level audio primitives
- **`AudioProcess`** — value type for a running app with audio output.
- **`AudioProcessEnumerator`** — `@Observable`; lists audio-producing processes via the CoreAudio `'prs#'` property; resolves helper processes to their parent app; refreshes on app launch/terminate and CoreAudio property changes.
- **`ProcessTapManager`** — singleton; creates/destroys process taps (`CATapDescription` + private aggregate device) and feeds captured PCM into ring buffers via a C-style `AudioDeviceIOProc`.
- **`RingBuffer`** — lock-free circular buffer for audio bytes.

### `Sources/Engine/` — AVAudioEngine graph management
- **`AudioEngineManager`** — `@Observable` singleton; owns one engine per output device; manages per-app node lifecycle, device switching, volume/mute/EQ state, and presets.
- **`AppAudioNode`** — wraps an `AVAudioSourceNode` + `AVAudioUnitEQ`; reads from ring buffers and converts sample rate / channel layout when the tap and engine formats differ.
- **`EQController`** — thin wrapper over `AVAudioUnitEQ` (10 parametric bands); handles preset serialization.
- **`PresetStore`** — `@Observable`; persists presets to `UserDefaults` as JSON.
- **`AudioDevice`** — value type (`deviceID`, `name`, `uid`).

### `Sources/UI/` — SwiftUI menu bar popover
- **`PopoverContentView`** — root view (process list + preset picker + output device picker).
- **`ProcessListView` / `AppRowView`** — process list with per-row controls.
- **`AppControlsView`** — per-app volume slider + mute toggle.
- **`EQCurveEditor`** — interactive EQ curve editor.
- **`OutputDevicePicker`** — output device selector.

### `Sources/SoundsSource/` — entry point
- **`main.swift`** — creates `NSApplication` and sets the delegate.
- **`AppDelegate`** — creates the `NSStatusItem`, the `NSPopover`, and initializes `AudioEngineManager.shared`.

## Audio data flow

```
CATapDescription (per app)
    → AudioDeviceIOProc callback → RingBuffer(s)
        → AVAudioSourceNode render block (pulls from RingBuffer)
            → AVAudioUnitEQ (10-band parametric)
                → AVAudioMixerNode (per output engine)
                    → AVAudioOutputNode → physical output device
```

## License

No license file is included. Add one before publishing if you intend others to reuse the code.
