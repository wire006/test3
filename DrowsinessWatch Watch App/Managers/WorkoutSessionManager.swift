//
//  WorkoutSessionManager.swift
//  DrowsinessWatch Watch App
//
//  watchOS で長時間バックグラウンド実行を安定させるため、
//  HKWorkoutSession を「other」アクティビティとして開始し、
//  画面ロック中もセンサー取得を継続できるようにする。
//
//  備考:
//   - 本アプリは実際のワークアウトではなく「居眠り監視」を行うが、
//     watchOS で心拍・加速度を継続取得する最もシンプルな方法が
//     HKWorkoutSession の利用であるため採用している。
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
                    self?.delegate?.workoutSessionFailed(error: error)
                    return
                }
                if success {
                    self?.delegate?.workoutSessionDidStart()
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
        session?.end()
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, _ in
                // 結果は保存しない (監視用途のため)。
            }
        }
        session = nil
        builder = nil
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
        // 心拍数は HealthKitManager 側のストリーミングで別途取得するためここでは扱わない。
    }
}
