import GameKit
import UIKit

class GameCenterManager: NSObject, GKGameCenterControllerDelegate {
    static let shared = GameCenterManager()
    private(set) var isAuthenticated = false

    // ── App Store Connect で作成するリーダーボード ID ──
    static let boardHiScore = "jp.crunch.hiscore"          // ハイスコア（高いほど良い）
    static let boardHiCombo = "jp.crunch.hicombo"          // 最大コンボ数（高いほど良い）
    // ステージ 1〜20 のクリアタイム（低いほど良い → App Store Connect で「Low is Better」に設定）
    static func boardStageTime(_ stage: Int) -> String {
        "jp.crunch.stagetime.\(stage)"
    }

    func authenticatePlayer() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            if let vc = viewController {
                self?.rootViewController?.present(vc, animated: true)
            }
            self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated
        }
    }

    func showLeaderboards() {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        let vc = GKGameCenterViewController(state: .leaderboards)
        vc.gameCenterDelegate = self
        rootViewController?.present(vc, animated: true)
    }

    func gameCenterViewControllerDidFinish(_ gc: GKGameCenterViewController) {
        gc.dismiss(animated: true)
    }

    func submitScore(_ score: Int, leaderboardID: String) {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        if #available(iOS 14.0, *) {
            GKLeaderboard.submitScore(
                score,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [leaderboardID]
            ) { error in
                if let error { print("[GC] submitScore error: \(error.localizedDescription)") }
            }
        } else {
            let entry = GKScore(leaderboardIdentifier: leaderboardID)
            entry.value = Int64(score)
            GKScore.report([entry]) { _ in }
        }
    }

    private var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController
    }
}
