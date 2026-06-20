//
//  DonutDropApp.swift
//  DonutDrop
//
//  Created by sm022284 on 2026/06/12.
//

import SwiftUI

@main
struct DonutDropApp: App {
    init() {
        // アプリ起動時にGame Center認証を開始する
        GameCenterManager.shared.authenticatePlayer()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
