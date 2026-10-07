//
//  ViewerMirrorController.swift
//  ExcalidrawZ
//
//  App-wide entry point for the Viewer window. Editor canvases register their
//  core; the Viewer mirrors the editor in the most recently key window.
//

#if os(macOS)
import AppKit
import Combine
import Logging

@MainActor
final class ViewerMirrorController: ObservableObject {
    static let shared = ViewerMirrorController()

    static let windowID = "viewer"
    static let shareWindowID = "viewer-share"

    enum NetworkSharingState: Equatable {
        case off
        case starting
        case running
        case failed(String)
    }

    @Published private(set) var session: ViewerMirrorSession?

    /// Follow mode: the Viewer pans/zooms with the editor. Off lets the
    /// presenter zoom in privately while the Viewer holds its view.
    @Published var isFollowingCamera: Bool {
        didSet {
            UserDefaults.standard.set(isFollowingCamera, forKey: Self.followDefaultsKey)
            session?.isFollowingCamera = isFollowingCamera
        }
    }

    /// Sharing to browsers on the local network. Off at launch unless
    /// `startsNetworkSharingAtLaunch` is on: the canvas leaves the machine,
    /// so it stays opt-in.
    @Published private(set) var isNetworkSharingEnabled = false
    /// Turn sharing on as soon as the app starts, so a kiosk pointed at the
    /// link comes up without a visit to this window.
    @Published var startsNetworkSharingAtLaunch: Bool {
        didSet {
            UserDefaults.standard.set(startsNetworkSharingAtLaunch, forKey: Self.autoStartDefaultsKey)
        }
    }
    @Published private(set) var networkSharingState: NetworkSharingState = .off
    @Published private(set) var networkClientCount = 0
    @Published private(set) var networkShareURLs: [URL] = []

    private static let followDefaultsKey = "ViewerFollowsEditorCamera"
    private static let autoStartDefaultsKey = "ViewerNetworkSharingStartsAtLaunch"
    private let logger = Logger(label: "ViewerMirrorController")
    /// Registered editor cores, most recently key (or registered) first.
    private var editors: [WeakEditor] = []
    private var keyWindowCancellable: AnyCancellable?
    private var isViewerWindowOpen = false
    private var networkServer: NetworkViewerServer?
    private var networkServerTask: Task<Void, Never>?
    private init() {
        isFollowingCamera = UserDefaults.standard.object(forKey: Self.followDefaultsKey) as? Bool ?? true
        startsNetworkSharingAtLaunch = UserDefaults.standard.bool(forKey: Self.autoStartDefaultsKey)
        keyWindowCancellable = NotificationCenter.default
            .publisher(for: NSWindow.didBecomeKeyNotification)
            .compactMap { $0.object as? NSWindow }
            .sink { [weak self] window in
                self?.windowDidBecomeKey(window)
            }
    }

    func register(editor: ExcalidrawCore) {
        editors.removeAll { $0.core === editor || $0.core == nil }
        editors.insert(WeakEditor(core: editor), at: 0)
        logger.debug("Registered editor core; total=\(editors.count)")
        session?.refreshEditorBinding()
    }

    func unregister(editor: ExcalidrawCore) {
        editors.removeAll { $0.core === editor || $0.core == nil }
        session?.refreshEditorBinding()
    }

    /// Called once the app has finished launching.
    func applicationDidLaunch() {
        if startsNetworkSharingAtLaunch {
            setNetworkSharing(true)
        }
    }

    func viewerDidAppear() {
        isViewerWindowOpen = true
        ensureSession().refreshEditorBinding()
    }

    func viewerDidDisappear() {
        isViewerWindowOpen = false
        closeSessionIfUnused()
    }

    // MARK: - Network sharing

    func setNetworkSharing(_ enabled: Bool) {
        guard enabled != isNetworkSharingEnabled else { return }
        isNetworkSharingEnabled = enabled
        if enabled {
            startNetworkServer()
        } else {
            stopNetworkServer()
        }
    }

    /// Every address the link works at: the Bonjour hostname first (stable
    /// even when DHCP hands out a new address), then each IPv4 address.
    /// No token: the LAN is the boundary, and the server only runs while
    /// sharing is on.
    private func shareURLs(port: UInt16) -> [URL] {
        var hosts = NetworkViewerAddresses.localIPv4Addresses()
        if let name = NetworkViewerAddresses.bonjourHostName() {
            hosts.insert(name, at: 0)
        }
        return hosts.compactMap { host in
            URL(string: "http://\(host):\(port)/viewer")
        }
    }

    private func startNetworkServer() {
        guard networkServer == nil else { return }

        let broadcaster = NetworkViewerBroadcaster(
            onClientCountChanged: { count in
                Task { @MainActor in
                    ViewerMirrorController.shared.networkClientCount = count
                }
            },
            onResyncRequested: {
                Task { @MainActor in
                    ViewerMirrorController.shared.session?.requestFullSync()
                }
            }
        )
        let server = NetworkViewerServer(broadcaster: broadcaster)
        networkServer = server
        networkSharingState = .starting
        networkShareURLs = shareURLs(port: server.port)

        let session = ensureSession()
        session.networkBroadcaster = broadcaster
        session.refreshEditorBinding()

        networkServerTask = Task { [weak self, server] in
            do {
                await MainActor.run { self?.networkSharingState = .running }
                try await server.start()
                await MainActor.run {
                    guard self?.networkServer === server else { return }
                    self?.networkSharingState = .off
                }
            } catch {
                await MainActor.run {
                    guard self?.networkServer === server else { return }
                    self?.logger.error("Network viewer server failed: \(error)")
                    self?.networkSharingState = .failed(error.localizedDescription)
                    self?.isNetworkSharingEnabled = false
                    self?.networkServer = nil
                    self?.networkServerTask = nil
                    self?.session?.networkBroadcaster = nil
                    self?.closeSessionIfUnused()
                }
            }
        }
    }

    private func stopNetworkServer() {
        guard let server = networkServer else { return }
        networkServer = nil
        networkServerTask = nil
        networkSharingState = .off
        networkClientCount = 0
        networkShareURLs = []
        session?.networkBroadcaster = nil
        Task { await server.stop() }
        closeSessionIfUnused()
    }

    // MARK: - Session lifecycle

    @discardableResult
    private func ensureSession() -> ViewerMirrorSession {
        if let session { return session }
        let session = ViewerMirrorSession(isFollowingCamera: isFollowingCamera) { [weak self] in
            self?.currentEditorCore
        }
        self.session = session
        return session
    }

    /// The session lives while either the Viewer window is open or browsers
    /// are being served.
    private func closeSessionIfUnused() {
        guard !isViewerWindowOpen, !isNetworkSharingEnabled else { return }
        session?.close()
        session = nil
    }

    private var currentEditorCore: ExcalidrawCore? {
        editors.removeAll { $0.core == nil }
        return editors.first?.core
    }

    private func windowDidBecomeKey(_ window: NSWindow) {
        guard let index = editors.firstIndex(where: { $0.core?.webView.window === window }),
              index != 0 else {
            return
        }
        let editor = editors.remove(at: index)
        editors.insert(editor, at: 0)
        session?.refreshEditorBinding()
    }
}

private struct WeakEditor {
    weak var core: ExcalidrawCore?
}
#endif
