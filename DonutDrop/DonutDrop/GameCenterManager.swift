import GameKit
import UIKit

class GameCenterManager: NSObject, GKGameCenterControllerDelegate {
    static let shared = GameCenterManager()
    private(set) var isAuthenticated = false

    // App Store Connect で設定するリーダーボードID
    static let boardHiScore  = "jp.donutdrop.hiscore"
    static let boardHiLines  = "jp.donutdrop.hilines"
    static let boardHiCombo  = "jp.donutdrop.hicombo"
    static let boardBattleLv = "jp.donutdrop.battlelv"
    static let boardWins = "jp.donutdrop.wins"

    func authenticatePlayer() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            // ログインが必要なときはGame Centerのログイン画面を表示する
            if let vc = viewController {
                self?.rootViewController?.present(vc, animated: true)
            }
            self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated
            if let error = error {
                print("GameCenter auth error: \(error.localizedDescription)")
            }
        }
    }

    // Game Centerのランキング一覧画面を表示する
    func showLeaderboards() {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        let vc = GKGameCenterViewController(state: .leaderboards)
        vc.gameCenterDelegate = self
        rootViewController?.present(vc, animated: true)
    }

    // Game Centerの画面を閉じるデリゲート
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
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
                if let error = error {
                    print("GameCenter submitScore error: \(error.localizedDescription)")
                }
            }
        } else {
            let entry = GKScore(leaderboardIdentifier: leaderboardID)
            entry.value = Int64(score)
            GKScore.report([entry]) { error in
                if let error = error {
                    print("GameCenter submitScore error: \(error.localizedDescription)")
                }
            }
        }
    }

    private var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController
    }
}
