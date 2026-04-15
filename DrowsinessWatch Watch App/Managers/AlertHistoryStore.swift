//
//  AlertHistoryStore.swift
//  DrowsinessWatch Watch App
//
//  居眠り検知のたびに発報時刻と心拍数等のスナップショットを保存する。
//  最新 N 件のみ保持するリングバッファ的な挙動で、UserDefaults に永続化する。
//

import Foundation
import Combine

struct AlertRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let triggeredAt: Date
    let heartRate: Double?
    let baselineHeartRate: Double?
    let activityLevel: Double

    init(
        id: UUID = UUID(),
        triggeredAt: Date,
        heartRate: Double?,
        baselineHeartRate: Double?,
        activityLevel: Double
    ) {
        self.id = id
        self.triggeredAt = triggeredAt
        self.heartRate = heartRate
        self.baselineHeartRate = baselineHeartRate
        self.activityLevel = activityLevel
    }
}

final class AlertHistoryStore: ObservableObject {
    private enum Keys {
        static let records = "history.records"
    }

    /// 履歴として保持する最大件数。
    private let maxRecords = 50

    private let defaults: UserDefaults

    @Published private(set) var records: [AlertRecord] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// 新しい発報を記録する。
    func append(_ record: AlertRecord) {
        records.insert(record, at: 0)
        if records.count > maxRecords {
            records.removeLast(records.count - maxRecords)
        }
        save()
    }

    /// 履歴を全削除する。
    func clear() {
        records.removeAll()
        save()
    }

    // MARK: - Private

    private func load() {
        guard let data = defaults.data(forKey: Keys.records) else { return }
        if let decoded = try? JSONDecoder().decode([AlertRecord].self, from: data) {
            records = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Keys.records)
    }
}
