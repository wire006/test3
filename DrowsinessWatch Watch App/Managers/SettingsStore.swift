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
        static let useWorkoutSession = "settings.useWorkoutSession"
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

    /// HKWorkoutSession を利用してバックグラウンド実行を安定化するか。
    @Published var useWorkoutSession: Bool {
        didSet { defaults.set(useWorkoutSession, forKey: Keys.useWorkoutSession) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // 初回起動時は既定値を書き込む。
        if defaults.object(forKey: Keys.sensitivity) == nil {
            defaults.set(1.0, forKey: Keys.sensitivity)
        }
        if defaults.object(forKey: Keys.useWorkoutSession) == nil {
            defaults.set(true, forKey: Keys.useWorkoutSession)
        }

        self.sensitivity = defaults.double(forKey: Keys.sensitivity)
        self.totalAlertCount = defaults.integer(forKey: Keys.totalAlertCount)
        self.useWorkoutSession = defaults.bool(forKey: Keys.useWorkoutSession)
    }

    /// 累積発報回数をリセットする。
    func resetTotalAlertCount() {
        totalAlertCount = 0
    }
}
