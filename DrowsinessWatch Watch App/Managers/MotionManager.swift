//
//  MotionManager.swift
//  DrowsinessWatch Watch App
//
//  CoreMotion を用いて腕の動きを監視する。
//  居眠り時は腕の動きが著しく減少するため、
//  加速度のノルムの変動量 (RMS) を活動量の指標として使用する。
//
//  省電力設計メモ:
//   - サンプリングは 10Hz 基本。ユーザー覚醒時 / 低電力時は `updateSampleRate` で
//     さらに 3〜5Hz まで下げる。
//   - サンプルごとに RMS を再計算せず、バッファへ append のみ行う。
//     RMS は検知器の評価タイミングで `snapshotActivity()` により pull する。
//   - これにより 50Hz × RMS 計算 × @Published の放出という旧実装の無駄を排除。
//

import Foundation
import CoreMotion

final class MotionManager {
    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()

    /// サンプル格納用の排他制御。writer は CoreMotion のコールバック、
    /// reader は評価タイマー (main) から sync で呼ぶため両方向からアクセスされる。
    private let bufferQueue = DispatchQueue(label: "com.drowsinesswatch.motion.buffer")
    /// 直近 N 個分の加速度ノルムをためるリングバッファ。
    private var accelerationWindow: [Double] = []

    /// 現在のサンプリングレート (Hz)。省電力のため実行時に書き換え可能。
    private(set) var sampleRateHz: Double = 10.0

    /// 直近 1 秒分のサンプルが入るようウィンドウサイズを決める。
    private var windowSize: Int { max(1, Int(sampleRateHz.rounded())) }

    init() {
        queue.name = "com.drowsinesswatch.motion"
        queue.qualityOfService = .userInitiated
    }

    // MARK: - ライフサイクル

    /// モーション監視を開始する。
    /// - Parameter sampleRateHz: 希望サンプリングレート (既定 10Hz)。
    func start(sampleRateHz: Double = 10.0) {
        guard motionManager.isDeviceMotionAvailable else { return }
        self.sampleRateHz = sampleRateHz
        bufferQueue.async { self.accelerationWindow.removeAll() }

        motionManager.deviceMotionUpdateInterval = 1.0 / sampleRateHz
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
        bufferQueue.async { self.accelerationWindow.removeAll() }
    }

    /// 実行中にサンプリングレートを変更する。
    /// 現状の CMMotionManager は単純に interval を書き換えれば追従する。
    /// バッファも連動してサイズを調整するため捨てる。
    func updateSampleRate(_ rate: Double) {
        let clamped = max(1.0, min(50.0, rate))
        guard abs(clamped - sampleRateHz) > 0.01 else { return }
        sampleRateHz = clamped
        if motionManager.isDeviceMotionActive {
            motionManager.deviceMotionUpdateInterval = 1.0 / clamped
            bufferQueue.async { self.accelerationWindow.removeAll() }
        }
    }

    // MARK: - スナップショット

    /// 現在のバッファから RMS を計算して返す (pull 型)。
    /// 評価タイマーから同期的に呼ぶ想定。
    func snapshotActivity() -> Double {
        bufferQueue.sync {
            guard !accelerationWindow.isEmpty else { return 0.0 }
            let squaredSum = accelerationWindow.reduce(0) { $0 + $1 * $1 }
            return sqrt(squaredSum / Double(accelerationWindow.count))
        }
    }

    // MARK: - Private

    private func handle(motion: CMDeviceMotion) {
        // 重力を除いたユーザー加速度のノルムを計算 (軽量)。
        let a = motion.userAcceleration
        let magnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)

        // バッファ追加のみ。RMS 計算 / 通知は pull 側で行う。
        let cap = windowSize
        bufferQueue.async { [magnitude] in
            self.accelerationWindow.append(magnitude)
            if self.accelerationWindow.count > cap {
                self.accelerationWindow.removeFirst(self.accelerationWindow.count - cap)
            }
        }
    }
}
