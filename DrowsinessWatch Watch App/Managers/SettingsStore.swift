//
//  SettingsStore.swift
//  DrowsinessWatch Watch App
//
//  ユーザー設定と累積アラート回数を UserDefaults に永続化する。
//  アプリ再起動後も感度や累計発報数を引き継げるようにする。
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
        static let sensitivity = "settings.sensitivity"
        static let totalAlertCount = "settings.totalAlertCount"
        static let backgroundMode = "settings.backgroundMode"
        // 旧キー (移行用)
        //  - useBackgroundSession: Bool — WKExtendedRuntimeSession 利用フラグだった
        //  - useWorkoutSession    : Bool — さらに旧、HKWorkoutSession 利用フラグだった
        static let legacyUseBackgroundSession = "settings.useBackgroundSession"
        static let legacyUseWorkoutSession = "settings.useWorkoutSession"
        static let drowsyTriggerSeconds = "settings.drowsyTriggerSeconds"
    }

    private let defaults: UserDefaults

    /// 居眠り検知の感度 (0.5 〜 2.0)。
    @Published var sensitivity: Double {
        didSet { defaults.set(sensitivity, forKey: Keys.sensitivity) }
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // 初回起動時は既定値を書き込む。
        if defaults.object(forKey: Keys.sensitivity) == nil {
            defaults.set(1.0, forKey: Keys.sensitivity)
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

        self.sensitivity = defaults.double(forKey: Keys.sensitivity)
        self.totalAlertCount = defaults.integer(forKey: Keys.totalAlertCount)
        let raw = defaults.string(forKey: Keys.backgroundMode) ?? BackgroundMode.off.rawValue
        self.backgroundMode = BackgroundMode(rawValue: raw) ?? .off
        let storedTrigger = defaults.integer(forKey: Keys.drowsyTriggerSeconds)
        self.drowsyTriggerSeconds = max(1, min(30, storedTrigger))
    }

    /// 累積発報回数をリセットする。
    func resetTotalAlertCount() {
        totalAlertCount = 0
    }
}
