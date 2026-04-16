//
//  DrowsinessDetector.swift
//  DrowsinessWatch Watch App
//
//  HealthKit の心拍数と CoreMotion の活動量を融合して居眠りを検知する。
//  検知時は HapticManager によって Apple Watch を振動させる。
//
//  検知ロジック概要:
//   - 心拍数の移動平均を「ベースライン」として保持する。
//   - 現在の心拍数がベースラインより一定割合 (既定 12%) 低下、
//     かつ活動量 (加速度 RMS) が閾値以下の状態が
//     連続で一定時間 (既定 30 秒) 続いた場合に「居眠り」と判定する。
//

import Foundation
import Combine
import SwiftUI

/// 検知状態。
enum DetectionState: String {
    case idle = "停止中"
    case monitoring = "監視中"
    case drowsy = "居眠り検知!!"
}

final class DrowsinessDetector: ObservableObject {
    // MARK: - 公開プロパティ

    @Published private(set) var state: DetectionState = .idle
    @Published private(set) var heartRate: Double?
    @Published private(set) var baselineHeartRate: Double?
    @Published private(set) var activityLevel: Double = 0.0
    @Published private(set) var consecutiveDrowsySeconds: Int = 0
    /// 現在のセッションでの発報回数。
    @Published var sessionAlertCount: Int = 0

    // MARK: - 依存コンポーネント

    let settings: SettingsStore
    let history: AlertHistoryStore

    private let healthKit = HealthKitManager()
    private let motion = MotionManager()
    private let haptic = HapticManager()
    private let runtimeSession = ExtendedRuntimeSessionManager()
    private let workout = WorkoutSessionManager()

    // MARK: - 閾値

    /// 心拍数がベースラインから何割下がったら眠気シグナルとみなすか。
    private let heartRateDropRatio: Double = 0.12
    /// 活動量 RMS がこの値以下なら静止とみなす。
    private let stillnessActivityThreshold: Double = 0.03
    // 連続でこの秒数、眠気条件を満たしたら居眠りと判定する。
    // 値は SettingsStore.drowsyTriggerSeconds (1 〜 30 秒) から取得する。

    // MARK: - 内部状態

    private var cancellables = Set<AnyCancellable>()
    private var monitoringTimer: Timer?
    /// ベースライン算出用の直近心拍数の履歴 (最大 120 サンプル ≒ 数分)。
    private var recentHeartRates: [Double] = []
    private let baselineWindow = 120

    // MARK: - イニシャライザ

    init(
        settings: SettingsStore = SettingsStore(),
        history: AlertHistoryStore = AlertHistoryStore()
    ) {
        self.settings = settings
        self.history = history
    }

    // MARK: - ライフサイクル

    /// 監視を開始する。UI の "スタート" ボタンから呼び出す。
    func start() {
        guard state == .idle else { return }

        healthKit.requestAuthorization()
        motion.start()

        // バックグラウンド実行方式をユーザー設定に応じて切り替える。
        //  - .extendedRuntime: 手首上げで自動復帰しないが、継続時間は数十分〜1h 程度。
        //  - .workout        : 長時間稼働可能。ただし手首上げでアプリが自動前面復帰する。
        //  - .off            : 前面時のみ監視。画面消灯・他アプリ表示で停止し得る。
        switch settings.backgroundMode {
        case .off:
            break
        case .extendedRuntime:
            runtimeSession.start()
        case .workout:
            workout.start()
        }

        // HealthKit / Motion の値を自身の @Published にブリッジ。
        healthKit.$currentHeartRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.handleHeartRateUpdate(value)
            }
            .store(in: &cancellables)

        motion.$activityLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.activityLevel = value
            }
            .store(in: &cancellables)

        // 1 秒ごとに居眠り条件を評価する。Timer は main run loop で回るので
        // UI 側の @Published の更新は main thread から安全に行える。
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.evaluateDrowsiness()
        }

        sessionAlertCount = 0
        state = .monitoring
    }

    /// 監視を停止する。
    func stop() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        cancellables.removeAll()
        healthKit.stopHeartRateStreaming()
        motion.stop()
        // 停止時は安全のため両方のセッションを終了する (どちらかが未使用でも no-op)。
        runtimeSession.stop()
        workout.stop()
        recentHeartRates.removeAll()
        consecutiveDrowsySeconds = 0
        state = .idle
    }

    /// 手動で振動テストを行う。
    func playTestHaptic() {
        haptic.playTestTap()
    }

    // MARK: - 検知ロジック

    private func handleHeartRateUpdate(_ value: Double?) {
        guard let value else { return }
        heartRate = value

        recentHeartRates.append(value)
        if recentHeartRates.count > baselineWindow {
            recentHeartRates.removeFirst(recentHeartRates.count - baselineWindow)
        }

        // 最低 20 サンプル集まってからベースラインを確立する。
        if recentHeartRates.count >= 20 {
            let sum = recentHeartRates.reduce(0, +)
            baselineHeartRate = sum / Double(recentHeartRates.count)
        }
    }

    private func evaluateDrowsiness() {
        guard state != .idle else { return }

        // 条件 1: 心拍数がベースラインから一定割合下がっている。
        let heartRateDropDetected: Bool = {
            guard let hr = heartRate, let base = baselineHeartRate else { return false }
            let dynamicRatio = heartRateDropRatio / max(settings.sensitivity, 0.1)
            return hr < base * (1.0 - dynamicRatio)
        }()

        // 条件 2: 腕の動きがほぼ無い。
        let dynamicStillnessThreshold = stillnessActivityThreshold * settings.sensitivity
        let isStill = activityLevel < dynamicStillnessThreshold

        if heartRateDropDetected && isStill {
            consecutiveDrowsySeconds += 1
        } else {
            consecutiveDrowsySeconds = 0
            if state == .drowsy {
                state = .monitoring
            }
        }

        if consecutiveDrowsySeconds >= settings.drowsyTriggerSeconds {
            triggerAlert()
        }
    }

    private func triggerAlert() {
        state = .drowsy
        sessionAlertCount += 1
        settings.totalAlertCount += 1

        history.append(AlertRecord(
            triggeredAt: Date(),
            heartRate: heartRate,
            baselineHeartRate: baselineHeartRate,
            activityLevel: activityLevel
        ))

        haptic.playDrowsinessAlert()
        // 連続検知を一旦リセットして、クールダウン中に誤爆させない。
        consecutiveDrowsySeconds = 0
    }
}
