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
    ///         その際、HKWorkoutSession を作成するには **HKWorkoutType の
    ///         share 権限** が必須。share を要求しないと HKLiveWorkoutBuilder
    ///         が心拍サンプルを収集できず、`didCollectDataOf` が一度も呼ばれない。
    /// - Parameter onAuthorized: 認可完了 (成功/失敗問わず main thread) で呼ばれる。
    ///   主に基準値の履歴シード処理やワークアウトセッション開始をキックするために利用する。
    func requestAuthorization(
        startStreaming: Bool = true,
        onAuthorized: (() -> Void)? = nil
    ) {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async { onAuthorized?() }
            return
        }

        let readTypes: Set<HKObjectType> = [heartRateType]
        // ワークアウトモード (HKWorkoutSession) の利用に必須の share 権限。
        // 他モードでは使われないが、含めても副作用は無い。
        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] success, _ in
            DispatchQueue.main.async {
                self?.isAuthorized = success
                if success && startStreaming {
                    self?.startHeartRateStreaming()
                }
                onAuthorized?()
            }
        }
    }

    /// 直近の心拍サンプルをまとめて取得する。基準値 (baseline) を
    /// アプリ起動直後から確立するためのシード用途で使う。
    /// - Parameters:
    ///   - interval: 何秒前までを遡るか (既定 30 分)。
    ///   - completion: 取得した bpm 値の配列 (古い順) が main thread で返る。
    func fetchRecentHeartRates(
        within interval: TimeInterval = 30 * 60,
        completion: @escaping ([Double]) -> Void
    ) {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async { completion([]) }
            return
        }
        let end = Date()
        let start = end.addingTimeInterval(-interval)
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictEndDate
        )
        let sort = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: true
        )
        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { [weak self] _, samples, _ in
            guard let self,
                  let quantitySamples = samples as? [HKQuantitySample] else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let bpms = quantitySamples.map { $0.quantity.doubleValue(for: self.bpmUnit) }
            DispatchQueue.main.async { completion(bpms) }
        }
        healthStore.execute(query)
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
