//
//  DrowsinessWatchApp.swift
//  DrowsinessWatch Watch App
//
//  Apple Watch 向け 居眠り検知 & 振動アラートアプリ。
//

import SwiftUI

@main
struct DrowsinessWatchApp: App {
    // アプリ全体で共有する検知エンジン。
    @StateObject private var detector = DrowsinessDetector()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(detector)
        }
    }
}
