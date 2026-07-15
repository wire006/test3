//
//  DrowsinessWatchApp.swift
//  DrowsinessWatch Watch App
//
//  Apple Watch 向け 居眠り検知 & 振動アラートアプリ。
//

import SwiftUI

@main
struct DrowsinessWatchApp: App {
    // 設定と履歴はアプリ起動時に一度だけ生成し、
    // 検知エンジン・UI から共有参照する。
    @StateObject private var settings = SettingsStore()
    @StateObject private var history = AlertHistoryStore()
    @StateObject private var detector: DrowsinessDetector

    // アプリのフォアグラウンド/バックグラウンド状態を監視し、
    // 残留ワークアウトセッションによる勝手な起動を防ぐ。
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let settings = SettingsStore()
        let history = AlertHistoryStore()
        _settings = StateObject(wrappedValue: settings)
        _history = StateObject(wrappedValue: history)
        _detector = StateObject(wrappedValue: DrowsinessDetector(
            settings: settings,
            history: history
        ))
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
            }
            .environmentObject(detector)
            .environmentObject(settings)
            .environmentObject(history)
            .onAppear {
                // 起動直後: 前回の強制終了などで残ったワークアウトセッションを
                // 回収して終了する。これをしないと、アプリを閉じても手首上げで
                // 勝手に前面復帰・起動してしまう。
                detector.cleanupOrphanedSessions()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // フォアグラウンド復帰時にも念のため残留セッションを掃除する。
            // (監視中は cleanupOrphanedSessions が no-op になるので影響なし)
            if newPhase == .active {
                detector.cleanupOrphanedSessions()
            }
        }
    }
}
