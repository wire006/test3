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
        playAlertPattern()
    }

    /// テスト用の振動。
    /// `.click` は微弱で体感しにくいため、実際の居眠りアラートと
    /// 同じパターンを再生して強い振動を確認できるようにする。
    /// クールダウン判定はスキップし、何度でも押せるようにする。
    func playTestTap() {
        playAlertPattern()
    }

    // MARK: - Private

    /// 段階的にハプティクスを再生して強く注意を促す。
    /// Taptic Engine 呼び出しは必ずメインスレッドから行う必要がある。
    private func playAlertPattern() {
        DispatchQueue.main.async {
            let device = WKInterfaceDevice.current()
            device.play(.notification)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            WKInterfaceDevice.current().play(.failure)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            WKInterfaceDevice.current().play(.retry)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            WKInterfaceDevice.current().play(.notification)
        }
    }
}
