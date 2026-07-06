//
//  DonutDropApp.swift
//  DonutDrop
//
//  Created by sm022284 on 2026/06/12.
//

import SwiftUI
import GoogleMobileAds

@main
struct DonutDropApp: App {
    init() {
        // アプリ起動時にGame Center認証を開始する
        GameCenterManager.shared.authenticatePlayer()
        // AdMob SDKを初期化し、最初の広告をプリロード開始
        MobileAds.shared.start(completionHandler: nil)
        _ = AdManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
