import SwiftUI
import Core

@available(macOS 14.2, *)
public struct ProcessListView: View {
    let processes: [AudioProcess]
    
    public init(processes: [AudioProcess]) {
        self.processes = processes
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if processes.isEmpty {
                    VStack(spacing: DS.m) {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(DS.textTertiary.opacity(0.6))

                        VStack(spacing: DS.xs) {
                            Text("No audio apps running")
                                .font(DSFont.caption)
                                .foregroundStyle(DS.textSecondary)
                            Text("Open an app like Spotify or Chrome to get started")
                                .font(.system(size: 10))
                                .foregroundStyle(DS.textTertiary)
                        }
                    }
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(processes) { process in
                        AppRowView(process: process)
                    }
                }
            }
        }
        .frame(maxHeight: 280)
    }
}
