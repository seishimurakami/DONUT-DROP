import SwiftUI
import WebKit
import CoreHaptics
import AVFoundation

struct GameWebView: UIViewRepresentable {

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "haptic")
        config.userContentController.add(context.coordinator, name: "gameCenter")
        config.userContentController.add(context.coordinator, name: "bgm")
        config.userContentController.add(context.coordinator, name: "ad")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator

        // www/index.html をバンドルから読み込む
        if let url = Bundle.main.url(forResource: "index", withExtension: "html",
                                     subdirectory: "www") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    // ────────────────────────────────────────────────────────
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

        weak var webView: WKWebView?
        private var hapticEngine: CHHapticEngine?
        private var bgmPlayer: AVAudioPlayer?

        override init() {
            super.init()
            prepareHaptics()
            prepareBGM()
        }

        // ── BGM ──────────────────────────────────────────────
        private func prepareBGM() {
            // DonutDropCrunch.mp3 をプロジェクトに追加すること
            guard let url = Bundle.main.url(forResource: "DonutDropCrunch", withExtension: "mp3") else { return }
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
            let vol = (body["volume"] as? Double).map { Float($0) } ?? 0.3
            switch type {
            case "play":      bgmPlayer?.volume = vol; bgmPlayer?.play()
            case "pause":     bgmPlayer?.volume = 0
            case "resume":    bgmPlayer?.volume = vol
            case "setVolume": bgmPlayer?.volume = vol
            case "stop":      bgmPlayer?.stop(); bgmPlayer?.currentTime = 0
            default: break
            }
        }

        // ── CoreHaptics ──────────────────────────────────────
        private func prepareHaptics() {
            guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
            do {
                hapticEngine = try CHHapticEngine()
                hapticEngine?.stoppedHandler = { [weak self] _ in try? self?.hapticEngine?.start() }
                hapticEngine?.resetHandler  = { [weak self] in   try? self?.hapticEngine?.start() }
                try hapticEngine?.start()
            } catch {}
        }

        // ── JS → Swift メッセージ受信 ─────────────────────────
        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            // GameCenter
            if message.name == "gameCenter" {
                DispatchQueue.main.async {
                    if type == "submitScore",
                       let lid = body["leaderboardID"] as? String,
                       let score = body["score"] as? Int {
                        GameCenterManager.shared.submitScore(score, leaderboardID: lid)
                    } else if type == "showLeaderboards" {
                        GameCenterManager.shared.showLeaderboards()
                    }
                }
                return
            }

            // BGM
            if message.name == "bgm" {
                DispatchQueue.main.async { [weak self] in
                    self?.handleBGM(type: type, body: body)
                }
                return
            }

            // 広告（JS が 3ステージごとに呼ぶ）
            if message.name == "ad", type == "showAd" {
                DispatchQueue.main.async { [weak self] in
                    guard let webView = self?.webView else {
                        self?.webView?.evaluateJavaScript("window.adCallback()", completionHandler: nil)
                        return
                    }
                    guard let rootVC = UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene })
                        .first?.windows.first?.rootViewController else {
                        webView.evaluateJavaScript("window.adCallback()", completionHandler: nil)
                        return
                    }
                    AdManager.shared.requestShow(from: rootVC) {
                        webView.evaluateJavaScript("window.adCallback()", completionHandler: nil)
                    }
                }
                return
            }

            // Haptics
            guard message.name == "haptic" else { return }
            DispatchQueue.main.async { [weak self] in
                switch type {
                case "drop":      self?.hapticDrop()
                case "levelUp":   self?.hapticLevelUp()
                case "warning":   self?.hapticWarning()
                case "gameOver":  self?.hapticGameOver()
                case "combo":
                    let count = body["count"] as? Int ?? 2
                    self?.hapticCombo(count: count)
                default: break
                }
            }
        }

        // ── 振動パターン ──────────────────────────────────────
        private func hapticDrop() {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        private func hapticLevelUp() {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        private func hapticWarning() {
            guard let engine = hapticEngine,
                  CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                return
            }
            do {
                let events: [CHHapticEvent] = [
                    CHHapticEvent(eventType: .hapticTransient,
                                  parameters: [.init(parameterID: .hapticIntensity, value: 1.0),
                                               .init(parameterID: .hapticSharpness, value: 0.1)],
                                  relativeTime: 0.0),
                    CHHapticEvent(eventType: .hapticTransient,
                                  parameters: [.init(parameterID: .hapticIntensity, value: 0.6),
                                               .init(parameterID: .hapticSharpness, value: 0.1)],
                                  relativeTime: 0.18),
                ]
                try engine.makePlayer(with: CHHapticPattern(events: events, parameters: [])).start(atTime: 0)
            } catch {}
        }
        private func hapticGameOver() {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        private func hapticCombo(count: Int) {
            let gen = UIImpactFeedbackGenerator(style: .medium)
            let beats = min(count, 6)
            for i in 0..<beats {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.09) {
                    gen.impactOccurred(intensity: min(0.5 + Double(i) * 0.1, 1.0))
                }
            }
        }

        // ── 外部リンクを Safari で開く ────────────────────────
        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = action.request.url, url.scheme != "file" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
