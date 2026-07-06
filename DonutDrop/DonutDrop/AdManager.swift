import GoogleMobileAds
import UIKit

/// インタースティシャル広告の管理クラス
/// - 起動時・広告閉鎖直後に次の広告を自動プリロード
/// - 「トップへもどる」3回に1回だけ広告を表示
final class AdManager: NSObject, FullScreenContentDelegate {
    static let shared = AdManager()

    private var interstitial: InterstitialAd?
    private var dismissCompletion: (() -> Void)?

    // タップ回数を保持するUserDefaultsキー
    private let countKey = "donutReturnToTopCount"

    // ── 広告ユニットID ──────────────────────────────────────
    private let adUnitID = "ca-app-pub-8655833266772741/5713167693"
    // ──────────────────────────────────────────────────────

    private override init() {
        super.init()
        preload()
    }

    /// バックグラウンドで次の広告をプリロード
    func preload() {
        InterstitialAd.load(with: adUnitID, request: Request(), completionHandler: { [weak self] ad, error in
            guard let self else { return }
            if let error {
                print("[AdManager] preload error: \(error.localizedDescription)")
                return
            }
            self.interstitial = ad
            self.interstitial?.fullScreenContentDelegate = self
        })
    }

    /// 広告表示リクエスト
    /// - 3回に1回だけ広告を表示。それ以外・ロード未完了の場合はすぐにcompletionを呼ぶ
    func requestShow(from rootViewController: UIViewController, completion: @escaping () -> Void) {
        let count = UserDefaults.standard.integer(forKey: countKey) + 1
        UserDefaults.standard.set(count, forKey: countKey)

        guard count % 3 == 0, let ad = interstitial else {
            // 表示条件を満たさない or ロード未完了 → 即遷移
            completion()
            return
        }

        dismissCompletion = completion
        ad.present(from: rootViewController)
    }

    // MARK: - FullScreenContentDelegate

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
        preload() // 広告を閉じたら即次をプリロード
    }
}
