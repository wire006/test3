//
//  WorkoutSessionManager.swift
//  DrowsinessWatch Watch App
//
//  HKWorkoutSession を "other" アクティビティとして開始し、
//  画面ロック中・他アプリ利用中もセンサー取得を継続させる。
//
//  特徴 / 注意点:
//   - 継続時間の制限が緩く (ワークアウト相当)、WKExtendedRuntimeSession より長時間動く。
//   - 代償として「ワークアウト中アプリ」扱いになり、時計画面で手首を上げると
//     **自動的にこのアプリが前面復帰** する。長距離運転など常時前面でも構わない
//     用途向け。画面復帰を避けたい場合は WKExtendedRuntimeSession を選ぶこと。
//

import Foundation
import HealthKit

protocol WorkoutSessionManagerDelegate: AnyObject {
    func workoutSessionDidStart()
    func workoutSessionDidEnd()
    func workoutSessionFailed(error: Error)
}

final class WorkoutSessionManager: NSObject {
    weak var delegate: WorkoutSessionManagerDelegate?

    /// ワークアウトセッション経由で心拍サンプルが届いたときに呼ばれるコールバック。
    /// HealthKit 側の AnchoredObjectQuery ストリーミングと重複しないよう、
    /// ワークアウトモードではこちらに一本化する。
    var onHeartRate: ((Double) -> Void)?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let bpmUnit = HKUnit.count().unitDivided(by: .minute())

    /// バックグラウンド実行用のワークアウトセッションを開始する。
    func start() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard session == nil else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .unknown

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            let dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            // `.other` アクティビティではデフォルトで心拍が自動収集されないことが
            // あるため、明示的に enable しておく。これが無いと
            // workoutBuilder(_:didCollectDataOf:) に heartRateType が届かない。
            dataSource.enableCollection(for: heartRateType, predicate: nil)
            builder.dataSource = dataSource

            session.delegate = self
            builder.delegate = self

            let now = Date()
            session.startActivity(with: now)
            builder.beginCollection(withStart: now) { [weak self] success, error in
                if let error {
                    DispatchQueue.main.async {
                        self?.delegate?.workoutSessionFailed(error: error)
                    }
                    return
                }
                if success {
                    DispatchQueue.main.async {
                        self?.delegate?.workoutSessionDidStart()
                    }
                }
            }

            self.session = session
            self.builder = builder
        } catch {
            delegate?.workoutSessionFailed(error: error)
        }
    }

    /// ワークアウトセッションを終了する。
    func stop() {
        guard let session else { return }
        session.end()
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, _ in
                // 監視用途のため結果は保存しない。
            }
        }
        self.session = nil
        self.builder = nil
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutSessionManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        if toState == .ended {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.workoutSessionDidEnd()
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.workoutSessionFailed(error: error)
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // 本アプリではイベントを個別処理しない。
    }

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        // ワークアウトビルダー経由で心拍を受け取ることで、
        // 別途 HKAnchoredObjectQuery を走らせる必要がなくなり電力を節約できる。
        guard collectedTypes.contains(heartRateType) else { return }
        guard let stats = workoutBuilder.statistics(for: heartRateType),
              let quantity = stats.mostRecentQuantity() else { return }
        let bpm = quantity.doubleValue(for: bpmUnit)
        DispatchQueue.main.async { [weak self] in
            self?.onHeartRate?(bpm)
        }
    }
}
