import SwiftUI
import WebKit
import CoreHaptics
import AVFoundation

struct GameWebView: UIViewRepresentable {

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // JavaScriptからの触覚フィードバック要求を受け取る
        config.userContentController.add(context.coordinator, name: "haptic")
        // JavaScriptからのGame Centerスコア送信要求を受け取る
        config.userContentController.add(context.coordinator, name: "gameCenter")
        // JavaScriptからのマルチプレイ操作を受け取る
        config.userContentController.add(context.coordinator, name: "multiplayer")
        // JavaScriptからのBGM制御を受け取る
        config.userContentController.add(context.coordinator, name: "bgm")
        // JavaScriptからの広告表示リクエストを受け取る
        config.userContentController.add(context.coordinator, name: "ad")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator

        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        context.coordinator.webView = webView
        MultiplayerManager.shared.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

        weak var webView: WKWebView?
        private var hapticEngine: CHHapticEngine?
        private var bgmPlayer: AVAudioPlayer?

        override init() {
            super.init()
            prepareHaptics()
            prepareBGM()
        }

        // ── BGMプレイヤーの準備 ──────────────────────────────
        private func prepareBGM() {
            guard let url = Bundle.main.url(forResource: "DonutDrop", withExtension: "mp3") else { return }
            do {
                try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                bgmPlayer = try AVAudioPlayer(contentsOf: url)
                bgmPlayer?.numberOfLoops = -1
                bgmPlayer?.volume = 0.3
                bgmPlayer?.prepareToPlay()
            } catch {}
        }

        private func handleBGM(type: String, body: [String: Any]) {
            switch type {
            case "play":
                let vol = (body["volume"] as? Double).map { Float($0) } ?? 0.3
                bgmPlayer?.volume = vol
                bgmPlayer?.play()
            case "pause":
                bgmPlayer?.volume = 0
            case "resume":
                let vol = (body["volume"] as? Double).map { Float($0) } ?? 0.3
                bgmPlayer?.volume = vol
            case "setVolume":
                let vol = (body["volume"] as? Double).map { Float($0) } ?? 0.3
                bgmPlayer?.volume = vol
            case "stop":
                bgmPlayer?.stop(); bgmPlayer?.currentTime = 0
            default: break
            }
        }

        // ── CoreHapticsエンジンの準備 ──────────────────────────
        private func prepareHaptics() {
            guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
            do {
                hapticEngine = try CHHapticEngine()
                // バックグラウンドから戻ったときにエンジンを再起動
                hapticEngine?.stoppedHandler = { [weak self] _ in try? self?.hapticEngine?.start() }
                hapticEngine?.resetHandler  = { [weak self] in   try? self?.hapticEngine?.start() }
                try hapticEngine?.start()
            } catch {}
        }

        // ── JavaScriptからのメッセージ受信 ────────────────────
        func userContentController(_ controller: WKUserContentController,
                                    didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            // マルチプレイ操作
            if message.name == "multiplayer" {
                DispatchQueue.main.async {
                    let mp = MultiplayerManager.shared
                    switch type {
                    case "startLobby":   mp.startBrowsing()
                    case "cancelLobby":  mp.disconnect()
                    case "invite":
                        if let peerId = body["peerId"] as? String { mp.invite(peerId: peerId) }
                    case "acceptInvite": mp.acceptInvitation()
                    case "declineInvite": mp.declineInvitation()
                    case "send":
                        if let data = body["data"] as? [String: Any] { mp.send(dict: data) }
                    case "sendUnreliable":
                        if let data = body["data"] as? [String: Any] { mp.send(dict: data, reliable: false) }
                    case "disconnect":   mp.disconnect()
                    case "playerWon":
                        let v = (body["wins"] as? Int) ?? 1
                        GameCenterManager.shared.submitScore(v, leaderboardID: GameCenterManager.boardWins)
                    default: break
                    }
                }
                return
            }

            // Game Centerスコア送信・ランキング表示
            if message.name == "gameCenter" {
                DispatchQueue.main.async {
                    if type == "submitScore",
                       let leaderboardID = body["leaderboardID"] as? String,
                       let score = body["score"] as? Int {
                        GameCenterManager.shared.submitScore(score, leaderboardID: leaderboardID)
                    } else if type == "showLeaderboards" {
                        GameCenterManager.shared.showLeaderboards()
                    }
                }
                return
            }

            // BGM制御
            if message.name == "bgm" {
                DispatchQueue.main.async { [weak self] in
                    self?.handleBGM(type: type, body: body)
                }
                return
            }

            // 広告表示リクエスト（「もう一度！」ボタン）
            if message.name == "ad", type == "showAd" {
                DispatchQueue.main.async { [weak self] in
                    guard let webView = self?.webView else { return }
                    guard let rootVC = UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene })
                        .first?.windows.first?.rootViewController else {
                        // 画面取得失敗 → 即遷移
                        webView.evaluateJavaScript("window.adCallback()", completionHandler: nil)
                        return
                    }
                    AdManager.shared.requestShow(from: rootVC) {
                        webView.evaluateJavaScript("window.adCallback()", completionHandler: nil)
                    }
                }
                return
            }

            guard message.name == "haptic" else { return }

            DispatchQueue.main.async { [weak self] in
                switch type {
                case "move":     self?.hapticMove()
                case "drop":     self?.hapticDrop()
                case "lineClear":
                    self?.hapticLineClear(count: body["count"] as? Int ?? 1)
                case "combo":
                    self?.hapticCombo(count: body["count"] as? Int ?? 2)
                case "levelUp":  self?.hapticLevelUp()
                case "warning":  self?.hapticWarning()
                case "gameOver": self?.hapticGameOver()
                default: break
                }
            }
        }

        // ── 振動パターン ────────────────────────────────────────

        // ピース移動・回転: コツッ（選択感）
        private func hapticMove() {
            let gen = UISelectionFeedbackGenerator()
            gen.selectionChanged()
        }

        // ピース落下: トン（軽め）
        private func hapticDrop() {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.impactOccurred()
        }

        // ライン消去: 消えた行数分だけパチパチ（多いほど強く）
        private func hapticLineClear(count: Int) {
            let styles: [UIImpactFeedbackGenerator.FeedbackStyle] = [.medium, .medium, .heavy, .heavy]
            let gen = UIImpactFeedbackGenerator(style: styles[min(count - 1, 3)])
            for i in 0..<min(count, 4) {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.08) {
                    gen.impactOccurred()
                }
            }
        }

        // コンボ: コンボ数分だけ連打、数が多いほど間隔が長くなる
        private func hapticCombo(count: Int) {
            let gen = UIImpactFeedbackGenerator(style: .medium)
            let beats    = min(count, 8)
            // コンボが増えるほど間隔を広げて「長い振動」に感じさせる
            let interval: Double = count <= 3 ? 0.07 : count <= 5 ? 0.10 : 0.13
            for i in 0..<beats {
                let intensity = CGFloat(min(0.45 + Double(i) * 0.08, 1.0))
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * interval) {
                    gen.impactOccurred(intensity: intensity)
                }
            }
        }

        // レベルアップ: 成功通知（プルン）
        private func hapticLevelUp() {
            let gen = UINotificationFeedbackGenerator()
            gen.notificationOccurred(.success)
        }

        // ピンチ警告: CoreHapticsで「ドクン・ドクン」の重い心拍
        private func hapticWarning() {
            guard let engine = hapticEngine,
                  CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
                let gen = UIImpactFeedbackGenerator(style: .heavy)
                gen.impactOccurred()
                return
            }
            do {
                let events: [CHHapticEvent] = [
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [.init(parameterID: .hapticIntensity, value: 1.0),
                                     .init(parameterID: .hapticSharpness, value: 0.1)],
                        relativeTime: 0.0),
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [.init(parameterID: .hapticIntensity, value: 0.6),
                                     .init(parameterID: .hapticSharpness, value: 0.1)],
                        relativeTime: 0.18),
                ]
                let pattern = try CHHapticPattern(events: events, parameters: [])
                try engine.makePlayer(with: pattern).start(atTime: 0)
            } catch {}
        }

        // ゲームオーバー: ズシン×3（エラー通知）
        private func hapticGameOver() {
            let gen = UINotificationFeedbackGenerator()
            gen.notificationOccurred(.error)
        }

        // ── 外部リンクをSafariで開く ────────────────────────────
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, url.scheme != "file" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
