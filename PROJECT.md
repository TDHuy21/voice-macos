# Project: SoundsSource Optimization & Test Suite

## Architecture
SoundsSource is structured into four main layers (targets) managed by Swift Package Manager (`Package.swift`):
1. **Core**: Taps system/process audio streams using `CATapDescription` and `AudioHardwareCreateProcessTap`, handles process enumeration, and maintains real-time circular buffers (`RingBuffer`).
2. **Engine**: Core business logic, managing audio nodes (`AppAudioNode`), audio devices (`AudioDevice`), audio engine managers (`AudioEngineManager`), break timers (`BreakTimerManager`), and task management (`TodoStore`, `TodoScheduler`).
3. **UI**: SwiftUI-based menu bar popover and supporting views.
4. **SoundsSource**: Application entry point (`AppDelegate`, `main.swift`).

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|---|---|---|---|
| M1 | Codebase Audit & Exploration | Run build, check existing tests, identify compilation warnings, and map potential memory leaks / retain cycles. | None | DONE |
| M2 | Memory & Concurrency Optimization | Resolve memory leaks (closures, NotificationCenter observers), fix retain cycles, and comply with Swift 6 strict concurrency checks. | M1 | DONE |
| M3 | Warnings & Code Cleanup | Fix all compiler warnings, remove redundant/unused code, and eliminate performance-impacting logs. | M2 | DONE |
| M4 | Automated Test Suite Development | Develop unit tests for `AppAudioNode`/`AudioEngineManager`, `BreakTimerManager`, and `TodoStore`/`TodoScheduler` (covering boundaries, midnight roll-over, auto-blocking). | M3 | DONE |
| M5 | Adversarial Hardening & Final Audit | Adversarial testing for edge cases, gap verification by Challengers, and final validation by Forensic Auditor. | M4 | DONE |

## Interface Contracts
### `AppAudioNode` ↔ `AudioEngineManager`
- `AppAudioNode` represents a single tapped application node. It interacts with `AudioEngineManager` for audio routing, mixer connections, volume control, and audio engine setup.
- Real-time safety: Audio processing blocks (render blocks) must not block or allocate memory.

### `BreakTimerManager` ↔ UI / App Lifecycle
- `BreakTimerManager` tracks eye rest/break timings. Emits notifications and states observed by the UI.

### `TodoStore` ↔ `TodoScheduler` ↔ UI
- `TodoStore` persists and manages a list of tasks (`TodoItem`).
- `TodoScheduler` schedules tasks, handling automatic blocking when break time starts, midnight roll-overs, and priority-based orderings.

## Code Layout
- `Sources/Core/`: Process tapping and RingBuffer.
- `Sources/Engine/`: Audio engine, break timers, todos.
- `Sources/UI/`: SwiftUI popover content, todo views, timer views.
- `Sources/SoundsSource/`: Menu-bar app delegate.
- `Tests/EngineTests/`: Integration and unit tests.
