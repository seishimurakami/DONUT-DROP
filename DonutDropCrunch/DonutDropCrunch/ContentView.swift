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
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    ATTrackingManager.requestTrackingAuthorization { _ in
                        DispatchQueue.main.async {
                            MobileAds.shared.start(completionHandler: nil)
                            _ = AdManager.shared
                        }
                    }
                }
            }
    }
}
