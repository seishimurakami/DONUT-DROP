import GoogleMobileAds
import UIKit

// インタースティシャル広告の管理クラス
// JS 側で「3ステージごと」を判断して showAd を送ってくるため
// Swift 側は無条件で広告を表示する（カウントは JS が管理）
@MainActor
final class AdManager: NSObject, FullScreenContentDelegate {
    static let shared = AdManager()

    private var interstitial: InterstitialAd?
    private var dismissCompletion: (() -> Void)?

    // ── 広告ユニットID（AdMob コンソールで取得したIDに差し替えること）──
    // private let adUnitID = "ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX"
    // テスト用ID（開発中はこちらを使う）:
    private let adUnitID = "ca-app-pub-3940256099942544/4411468910"

    @MainActor private override init() {
        super.init()
        preload()
    }

    func preload() {
        InterstitialAd.load(with: adUnitID, request: Request()) { [weak self] ad, error in
            guard let self else { return }
            if let error {
                print("[AdManager] preload error: \(error.localizedDescription)")
                return
            }
            self.interstitial = ad
            self.interstitial?.fullScreenContentDelegate = self
        }
    }

    func requestShow(from rootViewController: UIViewController, completion: @escaping () -> Void) {
        guard let ad = interstitial else {
            completion()
            return
        }
        dismissCompletion = completion
        ad.present(from: rootViewController)
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        finishAndReload()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("[AdManager] present error: \(error.localizedDescription)")
        finishAndReload()
    }

    private func finishAndReload() {
        let c = dismissCompletion
        dismissCompletion = nil
        interstitial = nil
        c?()
        preload()
    }
}
