//
//  HealthKitManager.swift
//  DrowsinessWatch Watch App
//
//  HealthKit を利用して心拍数をリアルタイムに取得する。
//  居眠り時は副交感神経優位となり心拍数が平常時より低下する傾向があるため、
//  直近の心拍数のベースライン比較で眠気のシグナルを検出する。
//

import Foundation
import HealthKit
import Combine

final class HealthKitManager: NSObject, ObservableObject {
    /// 現在の心拍数 (bpm)。未取得時は nil。
    @Published private(set) var currentHeartRate: Double?
    /// HealthKit の利用可否・権限状態。
    @Published private(set) var isAuthorized: Bool = false

    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKAnchoredObjectQuery?
    private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let bpmUnit = HKUnit.count().unitDivided(by: .minute())

    /// 権限をリクエストし、`startStreaming` が true の場合は成功後に
    /// 心拍数ストリーミングも開始する。
    /// - Note: ワークアウトモードでは HKLiveWorkoutBuilder から心拍を拾うため、
    ///         認可のみ取って AnchoredObjectQuery は起動しない運用にする。
    func requestAuthorization(startStreaming: Bool = true) {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let readTypes: Set<HKObjectType> = [heartRateType]
        healthStore.requestAuthorization(toShare: [], read: readTypes) { [weak self] success, _ in
            DispatchQueue.main.async {
                self?.isAuthorized = success
                if success && startStreaming {
                    self?.startHeartRateStreaming()
                }
            }
        }
    }

    /// 心拍数のストリーミング取得を開始する。
    func startHeartRateStreaming() {
        // 直近 0 秒以降の新規サンプルを監視する。
        let predicate = HKQuery.predicateForSamples(
            withStart: Date(),
            end: nil,
            options: .strictStartDate
        )

        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.process(samples: samples)
        }

        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.process(samples: samples)
        }

        healthStore.execute(query)
        heartRateQuery = query
    }

    /// ストリーミングを停止する。
    func stopHeartRateStreaming() {
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
    }

    // MARK: - Private

    private func process(samples: [HKSample]?) {
        guard
            let quantitySamples = samples as? [HKQuantitySample],
            let latest = quantitySamples.last
        else { return }

        let bpm = latest.quantity.doubleValue(for: bpmUnit)
        DispatchQueue.main.async { [weak self] in
            self?.currentHeartRate = bpm
        }
    }
}
