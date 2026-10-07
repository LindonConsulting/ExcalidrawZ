//
//  NetworkViewerServer.swift
//  ExcalidrawZ
//
//  Serves the read-only Viewer to browsers on the local network: a page that
//  embeds the Excalidraw bundle and receives the same scene deltas the local
//  Viewer window gets, over a WebSocket.
//

#if os(macOS)
import Foundation
import FlyingFox

/// Fan-out of mirror messages to every connected browser.
actor NetworkViewerBroadcaster {
    private var clients: [UUID: AsyncStream<WSMessage>.Continuation] = [:]
    private let onClientCountChanged: @Sendable (Int) -> Void
    private let onResyncRequested: @Sendable () -> Void

    init(
        onClientCountChanged: @escaping @Sendable (Int) -> Void,
        onResyncRequested: @escaping @Sendable () -> Void
    ) {
        self.onClientCountChanged = onClientCountChanged
        self.onResyncRequested = onResyncRequested
    }

    var clientCount: Int { clients.count }

    func broadcast(_ text: String) {
        for continuation in clients.values {
            continuation.yield(.text(text))
        }
    }

    func closeAll() {
        for continuation in clients.values {
            continuation.yield(.close(.goingAway))
            continuation.finish()
        }
        clients.removeAll()
        onClientCountChanged(0)
    }

    fileprivate func add(_ continuation: AsyncStream<WSMessage>.Continuation) -> UUID {
        let id = UUID()
        clients[id] = continuation
        onClientCountChanged(clients.count)
        // A newcomer needs the whole scene, not the next delta.
        onResyncRequested()
        return id
    }

    fileprivate func remove(_ id: UUID) {
        clients.removeValue(forKey: id)
        onClientCountChanged(clients.count)
    }

    fileprivate func handleClientMessage(_ message: WSMessage) {
        guard case .text(let text) = message,
              text.contains("\"resync\"") else {
            return
        }
        onResyncRequested()
    }
}

private struct NetworkViewerMessageHandler: WSMessageHandler {
    let broadcaster: NetworkViewerBroadcaster

    func makeMessages(for client: AsyncStream<WSMessage>) async throws -> AsyncStream<WSMessage> {
        let broadcaster = broadcaster
        return AsyncStream { continuation in
            let task = Task {
                let id = await broadcaster.add(continuation)
                for await message in client {
                    await broadcaster.handleClientMessage(message)
                }
                await broadcaster.remove(id)
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

final class NetworkViewerServer {
#if DEBUG
    static let defaultPort: UInt16 = 8489
#else
    static let defaultPort: UInt16 = 8488
#endif

    let port: UInt16
    let token: String

    private let server: HTTPServer
    private let broadcaster: NetworkViewerBroadcaster
    private var didInstallRoutes = false

    init(
        port: UInt16 = NetworkViewerServer.defaultPort,
        token: String,
        broadcaster: NetworkViewerBroadcaster
    ) {
        self.port = port
        self.token = token
        self.broadcaster = broadcaster
        self.server = HTTPServer(port: port, logger: ExcalidrawServerLogger())
    }

    func start() async throws {
        await installRoutesIfNeeded()
        try await server.run()
    }

    func stop() async {
        await broadcaster.closeAll()
        await server.stop()
    }

    private func installRoutesIfNeeded() async {
        guard !didInstallRoutes else { return }
        didInstallRoutes = true

        let token = token
        await server.appendRoute("GET /viewer/:token") { request in
            guard request.routeParameters["token"] == token else {
                return HTTPResponse(statusCode: .notFound)
            }
            guard let page = Self.viewerPageHTML(token: token) else {
                return HTTPResponse(statusCode: .internalServerError)
            }
            return HTTPResponse(
                statusCode: .ok,
                headers: [
                    .contentType: "text/html; charset=utf-8",
                    .cacheControl: "no-store",
                ],
                body: Data(page.utf8)
            )
        }

        let socketHandler = WebSocketHTTPHandler(
            handler: MessageFrameWSHandler(
                handler: NetworkViewerMessageHandler(broadcaster: broadcaster)
            )
        )
        await server.appendRoute("GET /viewer/:token/ws") { request in
            guard request.routeParameters["token"] == token else {
                return HTTPResponse(statusCode: .notFound)
            }
            return try await socketHandler.handleRequest(request)
        }

        // Same bundle the local WebViews load, served from this origin so the
        // viewer page can script the embedded editor.
        await server.appendRoute(
            "GET /*",
            to: .directory(
                for: .main,
                subPath: "excalidraw-latest",
                serverPath: ""
            )
        )
    }

    // MARK: - Page

    /// The browser page is the bundle's own `index.html` with the viewer
    /// bootstrap appended, so Excalidraw runs top-level (it refuses to run
    /// inside an iframe) and the same JS the local Viewer uses can drive it.
    static func viewerPageHTML(token: String) -> String? {
        guard let indexURL = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "excalidraw-latest"
        ),
              let index = try? String(contentsOf: indexURL, encoding: .utf8),
              let bodyEnd = index.range(of: "</body>", options: .backwards) else {
            return nil
        }
        let scripts = Self.jsLiteral([
            "chrome": ViewerMirrorScripts.viewerChromeStyle,
            "prepare": ViewerMirrorScripts.viewerPrepare,
            "apply": ViewerMirrorScripts.viewerApplyDelta,
            "laser": ViewerMirrorScripts.viewerApplyLaserPath,
        ])
        let tokenLiteral = Self.jsLiteral(token)
        let bootstrap = """
        <style>
          #excalidrawz-viewer-status { position: fixed; left: 50%; top: 12px; transform: translateX(-50%);
            z-index: 100000; padding: 6px 12px; border-radius: 8px; background: rgba(0,0,0,.6); color: #fff;
            font: 13px -apple-system, system-ui, sans-serif; pointer-events: none; }
          #excalidrawz-viewer-status.hidden { display: none; }
        </style>
        <div id="excalidrawz-viewer-status">Connecting…</div>
        <script>
        (() => {
          const scripts = \(scripts);
          const token = \(tokenLiteral);
          const status = document.getElementById("excalidrawz-viewer-status");
          let fns = null;

          const setStatus = (text) => {
            status.textContent = text || "";
            status.classList.toggle("hidden", !text);
          };

          // Wait for a laid-out viewport too: the first full sync fits the
          // editor's camera to this page's size.
          const editorReady = () => {
            const api = window.excalidrawZHelper && window.excalidrawZHelper._api;
            if (!api) {
              return false;
            }
            const appState = api.getAppState();
            return appState.width > 0 && appState.height > 0;
          };

          const prepare = () => {
            new Function(scripts.chrome)();
            fns = {
              prepare: new Function(scripts.prepare),
              apply: new Function("payload", "followCamera", scripts.apply),
              laser: new Function("phase", "points", scripts.laser),
            };
            fns.prepare();
          };

          const connect = () => {
            const protocol = location.protocol === "https:" ? "wss" : "ws";
            const socket = new WebSocket(`${protocol}://${location.host}/viewer/${token}/ws`);
            socket.onopen = () => setStatus("");
            // Refit after the browser window changes size.
            let resizeTimer = null;
            window.addEventListener("resize", () => {
              clearTimeout(resizeTimer);
              resizeTimer = setTimeout(() => {
                if (socket.readyState === WebSocket.OPEN) {
                  socket.send(JSON.stringify({ type: "resync" }));
                }
              }, 250);
            });
            socket.onmessage = (event) => {
              const message = JSON.parse(event.data);
              if (message.type === "delta") {
                if (fns.apply(message.payload, true) === "resync") {
                  socket.send(JSON.stringify({ type: "resync" }));
                }
              } else if (message.type === "laser") {
                fns.laser(message.phase, message.points);
              }
            };
            socket.onclose = () => {
              setStatus("Reconnecting…");
              setTimeout(connect, 1500);
            };
          };

          const waitForEditor = () => {
            if (!editorReady()) {
              setTimeout(waitForEditor, 100);
              return;
            }
            prepare();
            connect();
          };
          waitForEditor();
        })();
        </script>
        """
        return index.replacingCharacters(in: bodyEnd, with: bootstrap + "</body>")
    }

    private static func jsLiteral<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "null"
        }
        // Keep the literal safe inside a <script> element.
        return string.replacingOccurrences(of: "</", with: "<\\/")
    }
}

// MARK: - Messages

/// Wire format for server → browser messages.
struct NetworkViewerMessage: Encodable {
    var type: String
    var payload: String?
    var phase: String?
    var points: [[Double]]?

    static func delta(_ payload: String) -> NetworkViewerMessage {
        NetworkViewerMessage(type: "delta", payload: payload)
    }

    static func laser(_ path: ExcalidrawCore.LaserPointerPath) -> NetworkViewerMessage {
        NetworkViewerMessage(type: "laser", phase: path.phase, points: path.points)
    }

    func encodedText() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Local addresses

enum NetworkViewerAddresses {
    /// The Mac's `<name>.local` hostname, reachable from any machine on the
    /// LAN that resolves mDNS (Avahi on Linux).
    static func bonjourHostName() -> String? {
        let name = ProcessInfo.processInfo.hostName
        guard !name.isEmpty, name != "localhost" else { return nil }
        return name.hasSuffix(".local") ? name : name + ".local"
    }

    /// IPv4 addresses of the active, non-loopback interfaces (Wi-Fi/Ethernet first).
    static func localIPv4Addresses() -> [String] {
        var addresses: [(name: String, address: String)] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let addr = interface.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET),
                  (interface.ifa_flags & UInt32(IFF_UP)) != 0,
                  (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else {
                continue
            }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else {
                continue
            }
            addresses.append((String(cString: interface.ifa_name), String(cString: host)))
        }

        // en0/en1 are the user-facing interfaces; keep others (VPN, bridges) after them.
        return addresses
            .sorted { lhs, rhs in
                let l = lhs.name.hasPrefix("en"), r = rhs.name.hasPrefix("en")
                return l != r ? l : lhs.name < rhs.name
            }
            .map(\.address)
    }
}
#endif
