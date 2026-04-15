//
//  MotionManager.swift
//  DrowsinessWatch Watch App
//
//  CoreMotion を用いて腕の動きを監視する。
//  居眠り時は腕の動きが著しく減少するため、
//  加速度のノルムの変動量 (RMS) を活動量の指標として使用する。
//

import Foundation
import CoreMotion
import Combine

final class MotionManager: ObservableObject {
    /// 直近 1 秒間の加速度変動量 (m/s^2 相当)。値が小さいほど静止に近い。
    @Published private(set) var activityLevel: Double = 0.0

    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()

    /// 直近 N 個分の加速度ノルムをためるリングバッファ。
    private var accelerationWindow: [Double] = []
    private let windowSize = 50  // 50Hz で約 1 秒分。

    init() {
        queue.name = "com.drowsinesswatch.motion"
        queue.qualityOfService = .userInitiated
    }

    /// モーション監視を開始する。
    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0  // 50Hz

        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.handle(motion: motion)
        }
    }

    /// モーション監視を停止する。
    func stop() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        accelerationWindow.removeAll()
    }

    // MARK: - Private

    private func handle(motion: CMDeviceMotion) {
        // 重力を除いたユーザー加速度のノルムを計算。
        let a = motion.userAcceleration
        let magnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)

        accelerationWindow.append(magnitude)
        if accelerationWindow.count > windowSize {
            accelerationWindow.removeFirst(accelerationWindow.count - windowSize)
        }

        // RMS を活動量指標として採用。
        let squaredSum = accelerationWindow.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(squaredSum / Double(accelerationWindow.count))

        DispatchQueue.main.async { [weak self] in
            self?.activityLevel = rms
        }
    }
}
