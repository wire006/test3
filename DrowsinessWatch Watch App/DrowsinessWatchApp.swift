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
        }
    }
}
