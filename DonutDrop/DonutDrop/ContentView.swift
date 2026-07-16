import SwiftUI
import AppTrackingTransparency
import GoogleMobileAds

struct ContentView: View {
    var body: some View {
        GameWebView()
            .ignoresSafeArea()
            .statusBar(hidden: true)
            .background(Color(red: 10/255, green: 0/255, blue: 21/255))
            .onAppear {
                // UIが表示されてから少し待ってATTダイアログを表示
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    ATTrackingManager.requestTrackingAuthorization { _ in
                        // 許可・拒否どちらの場合でもAdMobを初期化
                        // 拒否の場合は自動的に非パーソナライズ広告になる
                        DispatchQueue.main.async {
                            MobileAds.shared.start(completionHandler: nil)
                            _ = AdManager.shared
                        }
                    }
                }
            }
    }
}
