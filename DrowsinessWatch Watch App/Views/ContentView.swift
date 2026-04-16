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

                heartRateDropThresholdSection

                stillnessThresholdSection

                triggerSecondsSection

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

                backgroundModeSection

                debugHeartRateSection
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
                label: settings.debugHeartRateEnabled ? "心拍 (DEBUG)" : "心拍",
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

    /// 心拍低下率の閾値を調整するセクション。
    /// ベースラインに対してこの割合以上の低下で「心拍低下」とみなす。
    /// 小さいほど敏感 (少しの低下で発火)、大きいほど鈍感。
    private var heartRateDropThresholdSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("心拍低下率: \(String(format: "%.0f%%", settings.heartRateDropThreshold * 100))")
                .font(.caption2)
            Slider(value: $settings.heartRateDropThreshold, in: 0.06...0.24, step: 0.01)
        }
    }

    /// 静止判定の活動量閾値 (加速度 RMS) を調整するセクション。
    /// 加速度 RMS がこの値以下なら「静止」とみなす。
    /// 小さいほど厳密な静止を要求、大きいほど微動でも発火する。
    private var stillnessThresholdSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("静止閾値: \(String(format: "%.2f m/s²", settings.stillnessActivityThreshold))")
                .font(.caption2)
            Slider(value: $settings.stillnessActivityThreshold, in: 0.01...0.30, step: 0.01)
        }
    }

    /// 居眠り判定までの連続秒数を 1 〜 30 秒で調整するセクション。
    private var triggerSecondsSection: some View {
        Stepper(
            value: $settings.drowsyTriggerSeconds,
            in: 1...30,
            step: 1
        ) {
            VStack(alignment: .leading, spacing: 0) {
                Text("判定秒数")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(settings.drowsyTriggerSeconds) 秒")
                    .font(.caption)
                    .monospacedDigit()
            }
        }
    }

    /// バックグラウンド実行方式を選ぶセクション。
    /// 監視中は誤って切り替わらないよう無効化する。
    private var backgroundModeSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Picker(selection: $settings.backgroundMode) {
                ForEach(BackgroundMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            } label: {
                Text("バックグラウンド")
                    .font(.caption2)
            }
            .pickerStyle(.navigationLink)
            .disabled(detector.state != .idle)

            Text(settings.backgroundMode.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// デバッグモードのトグルと擬似心拍数の Stepper。
    /// 実機での発報テストや UI 確認に使う。監視中でも切り替え可能。
    private var debugHeartRateSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $settings.debugHeartRateEnabled) {
                Text("デバッグ心拍")
                    .font(.caption2)
            }

            if settings.debugHeartRateEnabled {
                Stepper(
                    value: $settings.debugHeartRate,
                    in: 50...100,
                    step: 1
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("擬似心拍")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(settings.debugHeartRate) bpm")
                            .font(.caption)
                            .monospacedDigit()
                    }
                }

                Text("実測心拍を無視して上記の値を使用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
