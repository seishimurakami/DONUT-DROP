import MultipeerConnectivity
import WebKit
import GameKit

final class MultiplayerManager: NSObject {
    static let shared = MultiplayerManager()
    private static let serviceType = "donutdrop"

    private var myPeerID: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private var peerMap: [String: MCPeerID] = [:]
    private(set) var connectedPeer: MCPeerID?
    private var pendingInvitationHandler: ((Bool, MCSession?) -> Void)?

    weak var webView: WKWebView?

    private override init() {
        let name: String
        if GKLocalPlayer.local.isAuthenticated {
            name = GKLocalPlayer.local.displayName
        } else {
            name = UIDevice.current.name
        }
        myPeerID = MCPeerID(displayName: name)
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    func startBrowsing() {
        // Game Center認証完了後に正しい名前を反映する
        let currentName = GKLocalPlayer.local.isAuthenticated
            ? GKLocalPlayer.local.displayName
            : UIDevice.current.name
        if currentName != myPeerID.displayName {
            myPeerID = MCPeerID(displayName: currentName)
            session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
            session.delegate = self
        }

        peerMap.removeAll()

        let adv = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: Self.serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv

        let br = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        br.delegate = self
        br.startBrowsingForPeers()
        browser = br
    }

    func stopBrowsing() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
    }

    func invite(peerId: String) {
        guard let peer = peerMap[peerId] else { return }
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 30)
    }

    func acceptInvitation() {
        pendingInvitationHandler?(true, session)
        pendingInvitationHandler = nil
    }

    func declineInvitation() {
        pendingInvitationHandler?(false, nil)
        pendingInvitationHandler = nil
    }

    func send(dict: [String: Any], reliable: Bool = true) {
        guard let peer = connectedPeer,
              let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        let mode: MCSessionSendDataMode = reliable ? .reliable : .unreliable
        try? session.send(data, toPeers: [peer], with: mode)
    }

    func disconnect() {
        session.disconnect()
        stopBrowsing()
        connectedPeer = nil
        peerMap.removeAll()
        pendingInvitationHandler = nil
    }

    private func mapID(for peer: MCPeerID) -> String {
        if let existing = peerMap.first(where: { $0.value === peer })?.key { return existing }
        let id = UUID().uuidString
        peerMap[id] = peer
        return id
    }

    private func notifyJS(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(
                "window.mpEvent&&window.mpEvent(\(json))",
                completionHandler: nil
            )
        }
    }
}

// MARK: - MCSessionDelegate
extension MultiplayerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            connectedPeer = peerID
            stopBrowsing()
            notifyJS(["type": "connected", "name": peerID.displayName])
        case .notConnected:
            if connectedPeer === peerID {
                connectedPeer = nil
                notifyJS(["type": "disconnected"])
            }
        default: break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let outData = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: outData, encoding: .utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(
                "window.mpEvent&&window.mpEvent({type:'dataReceived',data:\(json)})",
                completionHandler: nil
            )
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultiplayerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        pendingInvitationHandler = invitationHandler
        let id = mapID(for: peerID)
        notifyJS(["type": "inviteReceived", "name": peerID.displayName, "peerId": id])
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultiplayerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let id = mapID(for: peerID)
        notifyJS(["type": "peerFound", "name": peerID.displayName, "peerId": id])
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        if let id = peerMap.first(where: { $0.value === peerID })?.key {
            notifyJS(["type": "peerLost", "peerId": id])
            peerMap.removeValue(forKey: id)
        }
    }
}
