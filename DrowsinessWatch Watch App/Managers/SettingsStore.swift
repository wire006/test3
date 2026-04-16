//
//  SettingsStore.swift
//  DrowsinessWatch Watch App
//
//  ユーザー設定と累積アラート回数を UserDefaults に永続化する。
//  アプリ再起動後も感度や累計発報数を引き継げるようにする。
//

import Foundation
import Combine

final class SettingsStore: ObservableObject {
    private enum Keys {
        static let sensitivity = "settings.sensitivity"
        static let totalAlertCount = "settings.totalAlertCount"
        // 旧 "settings.useWorkoutSession" は HKWorkoutSession 利用フラグだったが、
        // 時計画面からの自動復帰回避のため Extended Runtime Session に移行。
        // 既存インストールの値を引き継げるよう、互換キーとして読み込みも行う。
        static let useBackgroundSession = "settings.useBackgroundSession"
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

    /// WKExtendedRuntimeSession を利用してバックグラウンド実行を安定化するか。
    @Published var useBackgroundSession: Bool {
        didSet { defaults.set(useBackgroundSession, forKey: Keys.useBackgroundSession) }
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
        if defaults.object(forKey: Keys.useBackgroundSession) == nil {
            // 旧キーから移行、無ければ既定 true。
            let legacy = defaults.object(forKey: Keys.legacyUseWorkoutSession) as? Bool ?? true
            defaults.set(legacy, forKey: Keys.useBackgroundSession)
        }
        if defaults.object(forKey: Keys.drowsyTriggerSeconds) == nil {
            defaults.set(30, forKey: Keys.drowsyTriggerSeconds)
        }

        self.sensitivity = defaults.double(forKey: Keys.sensitivity)
        self.totalAlertCount = defaults.integer(forKey: Keys.totalAlertCount)
        self.useBackgroundSession = defaults.bool(forKey: Keys.useBackgroundSession)
        let storedTrigger = defaults.integer(forKey: Keys.drowsyTriggerSeconds)
        self.drowsyTriggerSeconds = max(1, min(30, storedTrigger))
    }

    /// 累積発報回数をリセットする。
    func resetTotalAlertCount() {
        totalAlertCount = 0
    }
}
