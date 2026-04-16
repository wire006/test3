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
//  省電力設計:
//   - モーションは MotionManager 側で 10Hz 基本、pull 型スナップショット化済。
//   - 評価間隔とモーションサンプルレートを「覚醒度」に応じて適応的に変更する。
//     はっきり覚醒している (HR が base 以上、活動量も十分) 場合は 10 秒おき、
//     居眠り圏内が近づいたら 1 秒おきまで細かく見る。
//   - バッテリー残量が 20% を下回ったら、さらに間引き方向に寄せる。
//   - ワークアウトモードではワークアウトビルダー経由で心拍を受け取り、
//     HKAnchoredObjectQuery の重複ストリーミングを止める。
//

import Foundation
import Combine
import SwiftUI
import WatchKit

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
    private var currentEvaluationInterval: TimeInterval = 1.0
    /// 眠気条件 (HR 低下 + 静止) が連続で満たされ始めた時刻。
    /// 評価間隔が可変になったため、秒数は「経過時間」から逆算する。
    private var drowsyConditionStartedAt: Date?
    /// ベースライン算出用の直近心拍数の履歴 (最大 120 サンプル ≒ 数分)。
    private var recentHeartRates: [Double] = []
    private let baselineWindow = 120
    /// 基準値を確定するために必要な最低サンプル数。
    /// 少なくするほど基準値が早く出るが、ノイズに引っ張られやすくなる。
    /// 履歴シード (`seedBaselineFromHistory`) と併用して、
    /// 実質 **監視開始直後〜数秒以内** に基準値が出るようにしている。
    private let minSamplesForBaseline = 3

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

        // 省電力のため motion は 10Hz 基本。後段の adaptCadence() で動的に変更する。
        motion.start(sampleRateHz: 10.0)

        // バッテリー残量を参照するため有効化。
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true

        // バックグラウンド実行方式をユーザー設定に応じて切り替える。
        //  - .extendedRuntime: 手首上げで自動復帰しないが、継続時間は数十分〜1h 程度。
        //  - .workout        : 長時間稼働可能。ただし手首上げでアプリが自動前面復帰する。
        //                      心拍はワークアウトビルダー経由で受ける。
        //  - .off            : 前面時のみ監視。画面消灯・他アプリ表示で停止し得る。
        switch settings.backgroundMode {
        case .off:
            // 通常どおり HealthKit ストリーミングで心拍取得。
            healthKit.requestAuthorization(startStreaming: true) { [weak self] in
                self?.seedBaselineFromHistory()
            }
            bindHealthKitHeartRateStream()
        case .extendedRuntime:
            healthKit.requestAuthorization(startStreaming: true) { [weak self] in
                self?.seedBaselineFromHistory()
            }
            bindHealthKitHeartRateStream()
            runtimeSession.start()
        case .workout:
            // ワークアウトセッション経由で心拍を受ける。認可のみ取って
            // AnchoredObjectQuery は起動しない (重複防止)。
            //
            // 注意: HKWorkoutSession の開始は **必ず認可完了後** に行う。
            // 認可前に start() を呼ぶと share 権限が確定しておらず、
            // HKLiveWorkoutBuilder が心拍サンプルを収集しない
            // (didCollectDataOf が一度も呼ばれない) ケースが発生する。
            workout.onHeartRate = { [weak self] bpm in
                self?.handleHeartRateUpdate(bpm)
            }
            healthKit.requestAuthorization(startStreaming: false) { [weak self] in
                guard let self else { return }
                self.seedBaselineFromHistory()
                self.workout.start()
            }
        }

        // 初期評価間隔で Timer をスケジュール。以後 adaptCadence() で張り替える。
        scheduleEvaluationTimer(interval: 1.0)

        // デバッグ心拍設定の変更を監視。
        bindDebugHeartRate()

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
        workout.onHeartRate = nil
        // 停止時は安全のため両方のセッションを終了する (どちらかが未使用でも no-op)。
        runtimeSession.stop()
        workout.stop()
        recentHeartRates.removeAll()
        drowsyConditionStartedAt = nil
        consecutiveDrowsySeconds = 0
        state = .idle
    }

    /// 手動で振動テストを行う。
    func playTestHaptic() {
        haptic.playTestTap()
    }

    // MARK: - バインディング

    private func bindHealthKitHeartRateStream() {
        healthKit.$currentHeartRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.handleHeartRateUpdate(value)
            }
            .store(in: &cancellables)
    }

    // MARK: - 検知ロジック

    private func handleHeartRateUpdate(_ value: Double?) {
        guard let value else { return }

        // 基準値は常に実測値から学習させる (デバッグモード時も維持)。
        // これにより、デバッグ HR を基準値より低く設定すれば居眠り判定を発火できる。
        recentHeartRates.append(value)
        if recentHeartRates.count > baselineWindow {
            recentHeartRates.removeFirst(recentHeartRates.count - baselineWindow)
        }
        if recentHeartRates.count >= minSamplesForBaseline {
            let sum = recentHeartRates.reduce(0, +)
            baselineHeartRate = sum / Double(recentHeartRates.count)
        }

        // 現在心拍はデバッグモード時は設定値で上書きし、判定ロジックに
        // 擬似心拍を供給する。
        if settings.debugHeartRateEnabled {
            heartRate = Double(settings.debugHeartRate)
        } else {
            heartRate = value
        }
    }

    /// デバッグモードのトグル / 擬似心拍の変更を監視し、
    /// `heartRate` を即座に反映する。
    private func bindDebugHeartRate() {
        Publishers.CombineLatest(
            settings.$debugHeartRateEnabled,
            settings.$debugHeartRate
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] enabled, bpm in
            guard let self else { return }
            if enabled {
                self.heartRate = Double(bpm)
            }
            // オフにした瞬間は、次の実測サンプル到着までは最後の値を維持。
        }
        .store(in: &cancellables)
    }

    /// 監視開始直後に、過去 30 分の心拍履歴から基準値を即座に立てる。
    /// HealthKit 認可が完了した後に呼ぶ想定。
    private func seedBaselineFromHistory() {
        healthKit.fetchRecentHeartRates(within: 30 * 60) { [weak self] bpms in
            guard let self, !bpms.isEmpty else { return }

            // ストリーミングで既に到着した最新サンプルを壊さないよう先頭に挿入する。
            // ウィンドウ内に収まるよう総数を baselineWindow に制限。
            let combined = (bpms + self.recentHeartRates).suffix(self.baselineWindow)
            self.recentHeartRates = Array(combined)

            if self.recentHeartRates.count >= self.minSamplesForBaseline {
                let sum = self.recentHeartRates.reduce(0, +)
                self.baselineHeartRate = sum / Double(self.recentHeartRates.count)
            }
        }
    }

    private func evaluateDrowsiness() {
        guard state != .idle else { return }

        // 活動量は毎回 pull する。Published で 10Hz 放出するより軽い。
        activityLevel = motion.snapshotActivity()

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
            if drowsyConditionStartedAt == nil {
                drowsyConditionStartedAt = Date()
            }
            let elapsed = Int(Date().timeIntervalSince(drowsyConditionStartedAt ?? Date()))
            consecutiveDrowsySeconds = elapsed
            if elapsed >= settings.drowsyTriggerSeconds {
                triggerAlert()
            }
        } else {
            drowsyConditionStartedAt = nil
            consecutiveDrowsySeconds = 0
            if state == .drowsy {
                state = .monitoring
            }
        }

        // 次回以降のサンプリング / 評価間隔を覚醒度とバッテリーから決める。
        adaptCadence()
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
        drowsyConditionStartedAt = nil
        consecutiveDrowsySeconds = 0
    }

    // MARK: - 省電力: 適応ケイデンス

    /// 評価タイマーを指定間隔で張り替える (既存と同じ間隔なら何もしない)。
    private func scheduleEvaluationTimer(interval: TimeInterval) {
        guard abs(currentEvaluationInterval - interval) > 0.01 || monitoringTimer == nil else { return }
        monitoringTimer?.invalidate()
        currentEvaluationInterval = interval
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.evaluateDrowsiness()
        }
    }

    /// 現在の覚醒度 + バッテリー残量から、次のサンプリング/評価パラメータを決める。
    private func adaptCadence() {
        let profile = desiredProfile()
        scheduleEvaluationTimer(interval: profile.evaluationInterval)
        motion.updateSampleRate(profile.motionSampleRateHz)
    }

    /// 目標ケイデンス (評価間隔 / モーション Hz) を算出する。
    ///
    /// ざっくり:
    ///  - はっきり覚醒 (HR >= base * 1.05 かつ活動あり)    → 10s / 3Hz
    ///  - 平常 (HR >= base)                                → 5s  / 5Hz
    ///  - やや低下 (HR >= base * 0.95)                     → 2s  / 10Hz
    ///  - 居眠り圏 or 判定中                              → 1s  / 10Hz
    ///  - 上記をバッテリー < 20% でさらに 2 倍間引き (motion は下限 3Hz)。
    private func desiredProfile() -> (evaluationInterval: TimeInterval, motionSampleRateHz: Double) {
        let batteryLow = isBatteryLow()

        // 居眠り検知中は最細で回す (発報後の離脱検知も兼ねる)。
        if state == .drowsy {
            return applyBattery(base: (1.0, 10.0), batteryLow: batteryLow)
        }

        guard let hr = heartRate else {
            // まだ心拍が取れない初期段階は中庸。
            return applyBattery(base: (2.0, 10.0), batteryLow: batteryLow)
        }

        let base = baselineHeartRate
        let hrRatio = base.map { hr / $0 } ?? 1.0
        let isActive = activityLevel > stillnessActivityThreshold * 2

        let chosen: (TimeInterval, Double)
        switch (hrRatio, isActive) {
        case let (r, active) where r >= 1.05 && active:
            chosen = (10.0, 3.0)   // はっきり覚醒
        case let (r, _) where r >= 1.0:
            chosen = (5.0, 5.0)    // 平常
        case let (r, _) where r >= 0.95:
            chosen = (2.0, 10.0)   // やや低下
        default:
            chosen = (1.0, 10.0)   // 居眠り圏
        }
        return applyBattery(base: chosen, batteryLow: batteryLow)
    }

    /// バッテリー低下時の追加間引き。
    private func applyBattery(
        base: (TimeInterval, Double),
        batteryLow: Bool
    ) -> (evaluationInterval: TimeInterval, motionSampleRateHz: Double) {
        guard batteryLow else { return (base.0, base.1) }
        let interval = min(30.0, base.0 * 2.0)
        let motionHz = max(3.0, base.1 / 2.0)
        return (interval, motionHz)
    }

    private func isBatteryLow() -> Bool {
        let level = WKInterfaceDevice.current().batteryLevel
        // -1 は取得不能。その場合は低下とみなさない。
        return level >= 0 && level < 0.2
    }
}
