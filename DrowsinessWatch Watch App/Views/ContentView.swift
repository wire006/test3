//
//  ContentView.swift
//  DrowsinessWatch Watch App
//
//  ホーム画面。監視のオン/オフ、心拍数、活動量、アラート回数を表示する。
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var detector: DrowsinessDetector
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var history: AlertHistoryStore

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                statusBadge

                metricsSection

                Divider()

                sensitivitySection

                primaryActionButton

                HStack(spacing: 6) {
                    NavigationLink(destination: HistoryView(store: history)) {
                        Label("履歴", systemImage: "list.bullet.rectangle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Button(action: { detector.playTestHaptic() }) {
                        Label("振動", systemImage: "waveform")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }

                Toggle(isOn: $settings.useWorkoutSession) {
                    Text("バックグラウンド安定化")
                        .font(.caption2)
                }
                .disabled(detector.state != .idle)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("居眠り防止")
    }

    // MARK: - Subviews

    private var statusBadge: some View {
        Text(detector.state.rawValue)
            .font(.headline)
            .foregroundStyle(statusColor)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(statusColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }

    private var statusColor: Color {
        switch detector.state {
        case .idle: return .gray
        case .monitoring: return .green
        case .drowsy: return .red
        }
    }

    private var metricsSection: some View {
        VStack(spacing: 4) {
            metricRow(
                label: "心拍",
                value: detector.heartRate.map { String(format: "%.0f bpm", $0) } ?? "--"
            )
            metricRow(
                label: "基準",
                value: detector.baselineHeartRate.map { String(format: "%.0f bpm", $0) } ?? "--"
            )
            metricRow(
                label: "活動",
                value: String(format: "%.3f", detector.activityLevel)
            )
            metricRow(
                label: "連続",
                value: "\(detector.consecutiveDrowsySeconds) 秒"
            )
            metricRow(
                label: "今回",
                value: "\(detector.sessionAlertCount) 回"
            )
            metricRow(
                label: "累計",
                value: "\(settings.totalAlertCount) 回"
            )
        }
        .font(.footnote)
    }

    private var sensitivitySection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("感度: \(String(format: "%.1f", settings.sensitivity))")
                .font(.caption2)
            Slider(value: $settings.sensitivity, in: 0.5...2.0, step: 0.1)
        }
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if detector.state == .idle {
            Button(action: { detector.start() }) {
                Label("監視開始", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        } else {
            Button(action: { detector.stop() }) {
                Label("停止", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }
}

#Preview {
    let settings = SettingsStore()
    let history = AlertHistoryStore()
    return NavigationStack {
        ContentView()
            .environmentObject(DrowsinessDetector(settings: settings, history: history))
            .environmentObject(settings)
            .environmentObject(history)
    }
}
