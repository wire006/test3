//
//  SettingsStore.swift
//  DrowsinessWatch Watch App
//
//  ユーザー設定と累積アラート回数を UserDefaults に永続化する。
//  アプリ再起動後も閾値 (心拍低下率 / 静止活動量) や累計発報数を引き継げるようにする。
//

import Foundation
import Combine

/// バックグラウンド実行で使うセッション種別。
/// - off: バックグラウンド実行しない (前面時のみ監視)。
/// - extendedRuntime: WKExtendedRuntimeSession を使う。時計画面から自動復帰しない。
///                    継続時間はカテゴリ判定で概ね数十分〜1 時間。
/// - workout: HKWorkoutSession を使う。継続時間は長いが、手首を上げると
///            自動的にこのアプリが前面復帰する。
enum BackgroundMode: String, CaseIterable, Identifiable {
    case off
    case extendedRuntime
    case workout

    var id: String { rawValue }

    /// UI に表示する短いラベル。
    var displayName: String {
        switch self {
        case .off: return "オフ"
        case .extendedRuntime: return "拡張実行"
        case .workout: return "ワークアウト"
        }
    }

    /// 選択時の補足説明 (UI 下部などで利用可)。
    var summary: String {
        switch self {
        case .off: return "省電力 / 前面のみ監視"
        case .extendedRuntime: return "中電力 / 手首上げで復帰しない"
        case .workout: return "高電力 / 長時間可・手首上げで復帰"
        }
    }
}

final class SettingsStore: ObservableObject {
    private enum Keys {
        static let heartRateDropThreshold = "settings.heartRateDropThreshold"
        static let stillnessActivityThreshold = "settings.stillnessActivityThreshold"
        static let totalAlertCount = "settings.totalAlertCount"
        static let backgroundMode = "settings.backgroundMode"
        // 旧キー (移行用)
        //  - sensitivity          : Double — 心拍低下率と静止閾値を一括調整していた単一感度
        //  - useBackgroundSession : Bool   — WKExtendedRuntimeSession 利用フラグだった
        //  - useWorkoutSession    : Bool   — さらに旧、HKWorkoutSession 利用フラグだった
        static let legacySensitivity = "settings.sensitivity"
        static let legacyUseBackgroundSession = "settings.useBackgroundSession"
        static let legacyUseWorkoutSession = "settings.useWorkoutSession"
        static let drowsyTriggerSeconds = "settings.drowsyTriggerSeconds"
        static let debugHeartRateEnabled = "settings.debugHeartRateEnabled"
        static let debugHeartRate = "settings.debugHeartRate"
    }

    private let defaults: UserDefaults

    /// 心拍低下率の閾値 (0.06 = 6% 〜 0.24 = 24%、既定 0.12 = 12%)。
    /// ベースラインに対して現在の心拍がこの割合以上低下したら眠気シグナルとみなす。
    /// 値を小さくすると敏感、大きくすると鈍感になる。
    @Published var heartRateDropThreshold: Double {
        didSet {
            let clamped = max(0.06, min(0.24, heartRateDropThreshold))
            if abs(clamped - heartRateDropThreshold) > 1e-9 {
                heartRateDropThreshold = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.heartRateDropThreshold)
        }
    }

    /// 静止判定の活動量閾値 (m/s² 単位、0.01 〜 0.30、既定 0.03)。
    /// 加速度 RMS がこの値以下なら静止とみなす。
    /// 値を小さくするとより厳密な静止を要求、大きくすると微動でも発火する。
    @Published var stillnessActivityThreshold: Double {
        didSet {
            let clamped = max(0.01, min(0.30, stillnessActivityThreshold))
            if abs(clamped - stillnessActivityThreshold) > 1e-9 {
                stillnessActivityThreshold = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.stillnessActivityThreshold)
        }
    }

    /// インストール以来の累積発報回数。
    @Published var totalAlertCount: Int {
        didSet { defaults.set(totalAlertCount, forKey: Keys.totalAlertCount) }
    }

    /// バックグラウンド実行の方式。
    @Published var backgroundMode: BackgroundMode {
        didSet { defaults.set(backgroundMode.rawValue, forKey: Keys.backgroundMode) }
    }

    /// 居眠りと判定するまでの連続静止秒数 (1 〜 30 秒)。
    /// 小さいほど反応が速くなる反面、誤検知が増える。
    @Published var drowsyTriggerSeconds: Int {
        didSet {
            let clamped = max(1, min(30, drowsyTriggerSeconds))
            if clamped != drowsyTriggerSeconds {
                drowsyTriggerSeconds = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.drowsyTriggerSeconds)
        }
    }

    /// デバッグモード: 実際の心拍数に関係なく `debugHeartRate` を現在心拍として
    /// 扱う。動作確認や UI テストに使う。基準値は実測ベースで学習し続けるため、
    /// `debugHeartRate` を基準値より低く設定すれば居眠り判定が発火する。
    @Published var debugHeartRateEnabled: Bool {
        didSet { defaults.set(debugHeartRateEnabled, forKey: Keys.debugHeartRateEnabled) }
    }

    /// デバッグモード時に使う擬似心拍数 (50 〜 100 bpm)。
    @Published var debugHeartRate: Int {
        didSet {
            let clamped = max(50, min(100, debugHeartRate))
            if clamped != debugHeartRate {
                debugHeartRate = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.debugHeartRate)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // 初回起動時は既定値を書き込む。
        // 旧単一感度 `settings.sensitivity` が残っていれば、心拍低下率 =
        // 0.12 / sensitivity、静止閾値 = 0.03 * sensitivity にマップして
        // 既存ユーザーの体感を極力維持する。新規インストールは既定値。
        if defaults.object(forKey: Keys.heartRateDropThreshold) == nil {
            let migrated: Double
            if let legacy = defaults.object(forKey: Keys.legacySensitivity) as? Double, legacy > 0 {
                migrated = max(0.06, min(0.24, 0.12 / legacy))
            } else {
                migrated = 0.12
            }
            defaults.set(migrated, forKey: Keys.heartRateDropThreshold)
        }
        if defaults.object(forKey: Keys.stillnessActivityThreshold) == nil {
            let migrated: Double
            if let legacy = defaults.object(forKey: Keys.legacySensitivity) as? Double, legacy > 0 {
                migrated = max(0.01, min(0.30, 0.03 * legacy))
            } else {
                migrated = 0.03
            }
            defaults.set(migrated, forKey: Keys.stillnessActivityThreshold)
        }
        if defaults.object(forKey: Keys.backgroundMode) == nil {
            // 旧キーからの移行ロジック:
            //  1. `useBackgroundSession` (Bool) が存在する場合
            //     - true  → .extendedRuntime
            //     - false → .off
            //  2. それも無ければさらに旧 `useWorkoutSession` (Bool)
            //     - true  → .extendedRuntime (移行後の既定挙動を維持)
            //     - false → .off
            //  3. いずれも無ければ新規インストール → 省電力のため .off。
            //     必要に応じて UI から .extendedRuntime / .workout を選べる。
            let migrated: BackgroundMode
            if let legacyBG = defaults.object(forKey: Keys.legacyUseBackgroundSession) as? Bool {
                migrated = legacyBG ? .extendedRuntime : .off
            } else if let legacyWorkout = defaults.object(forKey: Keys.legacyUseWorkoutSession) as? Bool {
                migrated = legacyWorkout ? .extendedRuntime : .off
            } else {
                migrated = .off
            }
            defaults.set(migrated.rawValue, forKey: Keys.backgroundMode)
        }
        if defaults.object(forKey: Keys.drowsyTriggerSeconds) == nil {
            defaults.set(30, forKey: Keys.drowsyTriggerSeconds)
        }
        if defaults.object(forKey: Keys.debugHeartRate) == nil {
            defaults.set(70, forKey: Keys.debugHeartRate)
        }

        let storedHRDrop = defaults.double(forKey: Keys.heartRateDropThreshold)
        self.heartRateDropThreshold = max(0.06, min(0.24, storedHRDrop == 0 ? 0.12 : storedHRDrop))
        let storedStillness = defaults.double(forKey: Keys.stillnessActivityThreshold)
        self.stillnessActivityThreshold = max(0.01, min(0.30, storedStillness == 0 ? 0.03 : storedStillness))
        self.totalAlertCount = defaults.integer(forKey: Keys.totalAlertCount)
        let raw = defaults.string(forKey: Keys.backgroundMode) ?? BackgroundMode.off.rawValue
        self.backgroundMode = BackgroundMode(rawValue: raw) ?? .off
        let storedTrigger = defaults.integer(forKey: Keys.drowsyTriggerSeconds)
        self.drowsyTriggerSeconds = max(1, min(30, storedTrigger))
        self.debugHeartRateEnabled = defaults.bool(forKey: Keys.debugHeartRateEnabled)
        let storedDebugHR = defaults.integer(forKey: Keys.debugHeartRate)
        self.debugHeartRate = max(50, min(100, storedDebugHR == 0 ? 70 : storedDebugHR))
    }

    /// 累積発報回数をリセットする。
    func resetTotalAlertCount() {
        totalAlertCount = 0
    }
}
