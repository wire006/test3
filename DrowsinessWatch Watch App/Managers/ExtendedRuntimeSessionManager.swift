//
//  ExtendedRuntimeSessionManager.swift
//  DrowsinessWatch Watch App
//
//  画面ロック中や他アプリ表示中もアプリを動かし続けるために
//  WKExtendedRuntimeSession を利用する。
//
//  なぜ HKWorkoutSession ではなく WKExtendedRuntimeSession を使うか:
//   - HKWorkoutSession はアクティブな間「ワークアウト中」として扱われ、
//     手首を上げたりコンプリケーションをタップした際に
//     時計画面から自動的にこのアプリに復帰してしまう。
//   - WKExtendedRuntimeSession はバックグラウンド実行を確保しつつ
//     UI の自動復帰は発生しないため、「ながら監視」向きに適している。
//
//  セッションの最大継続時間は watchOS のカテゴリ判定に依存する
//  (概ね数十分〜1 時間程度)。willExpire 通知でユーザーに知らせる。
//

import Foundation
import WatchKit

final class ExtendedRuntimeSessionManager: NSObject {
    /// セッションがまもなく切れる旨の通知 (UI 側で振動や再開案内に利用可)。
    var onWillExpire: (() -> Void)?

    private var session: WKExtendedRuntimeSession?

    /// バックグラウンド実行セッションを開始する。
    func start() {
        guard session == nil else { return }
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start()
        session = s
    }

    /// セッションを終了する。
    func stop() {
        session?.invalidate()
        session = nil
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension ExtendedRuntimeSessionManager: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSessionDidStart(
        _ extendedRuntimeSession: WKExtendedRuntimeSession
    ) {
        // 開始時点では特に処理不要。
    }

    func extendedRuntimeSessionWillExpire(
        _ extendedRuntimeSession: WKExtendedRuntimeSession
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.onWillExpire?()
        }
    }

    func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.session = nil
        }
    }
}
