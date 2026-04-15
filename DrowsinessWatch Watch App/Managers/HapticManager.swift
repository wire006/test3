//
//  HapticManager.swift
//  DrowsinessWatch Watch App
//
//  Apple Watch の Taptic Engine を用いて振動を発生させる。
//  居眠り検知時に段階的に強い振動を連続で再生し、眠気を解消する。
//

import Foundation
import WatchKit

final class HapticManager {
    /// 振動のクールダウン時間 (秒)。短時間に連打しないよう制御する。
    private var lastPlayedAt: Date?
    private let cooldown: TimeInterval = 10.0

    /// 居眠り防止用アラート振動を再生する。
    /// 連続で複数回再生することで、ユーザーを確実に起こす。
    func playDrowsinessAlert() {
        if let last = lastPlayedAt, Date().timeIntervalSince(last) < cooldown {
            return
        }
        lastPlayedAt = Date()

        // 段階的にハプティクスを再生して強く注意を促す。
        let device = WKInterfaceDevice.current()
        device.play(.notification)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            device.play(.failure)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            device.play(.retry)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            device.play(.notification)
        }
    }

    /// テスト用の単発振動。
    func playTestTap() {
        WKInterfaceDevice.current().play(.click)
    }
}
