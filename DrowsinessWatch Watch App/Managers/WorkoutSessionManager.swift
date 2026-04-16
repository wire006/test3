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

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

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
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)

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
        // 心拍数は HealthKitManager 側のストリーミングで別途取得する。
    }
}
