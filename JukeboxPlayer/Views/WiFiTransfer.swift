import Network
import SwiftUI
import UniformTypeIdentifiers

// ============================================================================
// WiFiTransfer — 局域网网页传歌
// App 内嵌轻量 HTTP 服务器(NWListener): 电脑浏览器打开 http://<手机IP>:<端口>
// 输入配对码即可批量拖歌进 App, 文件走 importFile 完整链路(标签提取/去重/入库)。
// 零第三方依赖; 仅监听局域网; 4位配对码防蹭传。
// ============================================================================

final class WiFiTransferServer: ObservableObject {

    // MARK: - 对外状态(全部主线程写)

    @Published private(set) var isRunning = false
    /// 实际监听端口(系统分配, 避免撞车)
    @Published private(set) var port: UInt16 = 0
    @Published private(set) var receivedCount = 0
    @Published private(set) var lastMessage: String?

    /// 本次启动随机生成的4位配对码
    @Published private(set) var pairingCode: String

    /// 收到文件后的落库回调: (tempURL, 原始文件名)。由调用方接 TrackStore.importFile
    var onFileReceived: ((URL, String) async -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "vtune.wifi.transfer")

    init() {
        pairingCode = String(format: "%04d", Int.random(in: 0...9999))
    }

    // MARK: - 启停

    func start() {
        guard !isRunning else { return }
        pairingCode = String(format: "%04d", Int.random(in: 0...9999))

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let l: NWListener
        do {
            l = try NWListener(using: params, on: .any)   // 系统分配空闲端口
        } catch {
            DispatchQueue.main.async { self.lastMessage = "启动失败: \(error.localizedDescription)" }
            return
        }

        l.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        l.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                switch state {
                case .ready:
                    self.isRunning = true
                    self.port = l.port?.rawValue ?? 0
                    self.lastMessage = "服务已开启"
                case .failed(let err):
                    self.isRunning = false
                    self.lastMessage = "服务异常: \(err.localizedDescription)"
                case .cancelled:
                    self.isRunning = false
                default:
                    break
                }
            }
        }
        listener = l
        l.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isRunning = false
            self.lastMessage = "服务已关闭"
        }
    }

    /// 本机局域网 IPv4(WiFi 通常为 en0), 用于界面展示完整地址
    static func localIPv4() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let iface = p.pointee
            if let sa = iface.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: iface.ifa_name)
                if name == "en0" || name == "en1" {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(sa, socklen_t(sa.pointee.sa_len),
                                   &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        address = String(cString: host)
                        if name == "en0" { break }   // en0 优先
                    }
                }
            }
            ptr = p.pointee.ifa_next
        }
        return address
    }

    // MARK: - 连接处理(全部在 self.queue 上)

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(connection, buffer: Data(), headerDone: false, contentLength: 0)
    }

    private func readRequest(_ connection: NWConnection, buffer: Data, headerDone: Bool, contentLength: Int) {
        // 已收满: header + body
        if headerDone, buffer.count >= contentLength {
            route(connection, request: buffer.prefix(contentLength))
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                var buf = buffer
                buf.append(data)

                var hd = headerDone
                var cl = contentLength

                if !hd, let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) {
                    let headText = String(data: buf[buf.startIndex..<headerEnd.lowerBound], encoding: .utf8) ?? ""
                    if let line = headText.split(separator: "\r\n").first(where: { $0.lowercased().hasPrefix("content-length:") }),
                       let n = Int(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) {
                        cl = min(n, 600 * 1024 * 1024)   // 单请求上限 600MB
                    }
                    hd = true
                }
                // 收满或头都还没齐就继续读
                if hd, buf.count >= cl {
                    self.route(connection, request: buf.prefix(cl))
                } else {
                    self.readRequest(connection, buffer: buf, headerDone: hd, contentLength: cl)
                }
                return
            }
            if error == nil, isComplete, headerDone, buffer.count >= contentLength {
                self.route(connection, request: buffer.prefix(contentLength))
                return
            }
            connection.cancel()
        }
    }

    private func route(_ connection: NWConnection, request sub: Data) {
        let req = Data(sub)
        let headerEnd = req.range(of: Data("\r\n\r\n".utf8)) ?? req.startIndex..<req.startIndex
        let headText = String(data: req[req.startIndex..<headerEnd.lowerBound], encoding: .utf8) ?? ""
        let body = Data(req[headerEnd.upperBound...])

        let firstLine = headText.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = firstLine.split(separator: " ")
        let method = parts.count > 0 ? String(parts[0]) : ""
        let rawPath = parts.count > 1 ? String(parts[1]) : "/"

        switch (method, rawPath) {
        case ("GET", "/"), ("GET", "/index.html"):
            send(connection, html: Self.indexPage())
        case ("POST", "/upload"):
            handleUpload(connection, headers: headText, body: body)
        default:
            send(connection, html: "<h2>404</h2><p><a href=\"/\">返回</a></p>", status: "404 Not Found")
        }
    }

    // MARK: - 上传处理

    private struct IncomingFile {
        var name: String
        var data: Data
    }

    private func handleUpload(_ connection: NWConnection, headers: String, body: Data) {
        // ① 配对码校验(multipart 字段 code)
        // ② boundary 分段解析 multipart/form-data
        guard let ctLine = headers.split(separator: "\r\n").first(where: { $0.lowercased().hasPrefix("content-type:") }),
              let bRange = ctLine.range(of: "boundary=") else {
            send(connection, html: Self.resultPage(items: [("参数缺失", false)]))
            return
        }
        let boundaryRaw = String(ctLine[bRange.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        let boundary = Data("--\(boundaryRaw)".utf8)
        let codeOK = { [weak self] in
            guard let self else { return false }
            return body.range(of: Data("name=\"code\"\r\n\r\n".utf8)).flatMap { r in
                let tail = body[r.upperBound...]
                return tail.range(of: Data("\r\n".utf8)).map { String(data: tail[tail.startIndex..<$0.lowerBound], encoding: .utf8) ?? "" }
            } == self.pairingCode
        }()

        guard codeOK else {
            send(connection, html: Self.resultPage(items: [("配对码不对", false)]))
            return
        }

        // 按 boundary 切 part: --boundary ... --boundary-- 
        var files: [IncomingFile] = []
        var cursor = body.startIndex
        while let partStart = body.range(of: boundary, range: cursor..<body.endIndex) {
            let segStart = partStart.upperBound
            // 结束标记 "--boundary--"
            if segStart < body.endIndex,
               body.distance(from: segStart, to: body.endIndex) >= 2,
               body.subdata(in: segStart..<body.index(segStart, offsetBy: 2)) == Data("--".utf8) {
                break
            }
            // 每个 part 从 \r\n 后开始
            guard let crlf = body.range(of: Data("\r\n".utf8), range: segStart..<body.endIndex) else { break }
            let partBodyStart = crlf.upperBound
            // part 结束于下一个 boundary
            guard let partEnd = body.range(of: boundary, range: partBodyStart..<body.endIndex) else { break }
            let partContent = body.subdata(in: partBodyStart..<body.index(partEnd.lowerBound, offsetBy: -2))   // 去掉尾部 \r\n
            cursor = partEnd.lowerBound

            // part 自带头部(\r\n\r\n 前): 抓 filename
            guard let pHdrEnd = partContent.range(of: Data("\r\n\r\n".utf8)) else { continue }
            let partHeader = String(data: partContent[partContent.startIndex..<pHdrEnd.lowerBound], encoding: .utf8) ?? ""
            guard partHeader.contains("filename=") else { continue }   // 非 file 字段(如 code)跳过
            let fileData = partContent.subdata(in: pHdrEnd.upperBound..<partContent.endIndex)
            guard !fileData.isEmpty else { continue }

            var fname = "未命名"
            if let fRange = partHeader.range(of: "filename=\"") {
                let rest = partHeader[fRange.upperBound...]
                if let fEnd = rest.firstIndex(of: "\"") {
                    fname = String(rest[rest.startIndex..<fEnd])
                }
            }
            fname = (fname as NSString).lastPathComponent   // 防路径注入
            if fname.isEmpty { fname = "未命名" }
            files.append(IncomingFile(name: fname, data: fileData))
        }

        guard !files.isEmpty else {
            send(connection, html: Self.resultPage(items: [("没收到文件", false)]))
            return
        }

        // 落盘临时文件并回调导入(异步, 不阻塞响应)
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory
        var results: [(String, Bool)] = []
        let dispatchGroup = DispatchGroup()

        for f in files {
            let safe = UUID().uuidString.suffix(6)
            let tmp = tmpDir.appendingPathComponent("wifi_\(safe)_\(f.name)")
            do {
                try f.data.write(to: tmp, options: [.atomic])
            } catch {
                results.append((f.name, false))
                continue
            }
            let sem = DispatchSemaphore(value: 0)
            dispatchGroup.enter()
            DispatchQueue.main.async { [weak self] in
                guard let self, let cb = self.onFileReceived else {
                    sem.signal(); dispatchGroup.leave(); return
                }
                Task { @MainActor in
                    await cb(tmp, f.name)
                    sem.signal()
                    dispatchGroup.leave()
                }
            }
            _ = sem.wait(wallTimeout: .now() + 120)
            results.append((f.name, true))
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.receivedCount += files.count
            self.lastMessage = "收到 \(files.count) 个文件"
        }
        send(connection, html: Self.resultPage(items: results.map { ($0.0, $0.1) }))
    }

    // MARK: - HTTP 响应

    private func send(_ connection: NWConnection, html: String, status: String = "200 OK") {
        let data = Data(html.utf8)
        var resp = "HTTP/1.1 \(status)\r\n"
        resp += "Content-Type: text/html; charset=utf-8\r\n"
        resp += "Content-Length: \(data.count)\r\n"
        resp += "Connection: close\r\n\r\n"
        var out = Data(resp.utf8)
        out.append(data)
        connection.send(content: out, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - 页面

    private static func indexPage() -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>V-Tune 传歌</title><style>
        body{font-family:-apple-system,sans-serif;background:#101613;color:#e8f0ea;max-width:520px;margin:0 auto;padding:32px 20px}
        h1{font-size:22px} .card{background:#1a231e;border-radius:14px;padding:20px;margin:16px 0}
        input[type=text],input[type=file]{width:100%;margin:8px 0;padding:10px;border-radius:8px;border:1px solid #2c3a31;background:#0d1210;color:#e8f0ea;box-sizing:border-box}
        button{width:100%;padding:12px;border:none;border-radius:10px;background:#18b86b;color:#04130b;font-size:16px;font-weight:700;margin-top:12px}
        .tip{color:#8fa398;font-size:13px;line-height:1.7}
        </style></head><body>
        <h1>🎵 V-Tune 传歌</h1>
        <div class="card">
          <form action="/upload" method="post" enctype="multipart/form-data">
            <label class="tip">配对码(看手机屏幕)</label>
            <input type="text" name="code" placeholder="4 位数字" required>
            <label class="tip">选择音乐文件(可多选)</label>
            <input type="file" name="files" multiple accept=".mp3,.m4a,.flac,.wav,.aac,.ogg,.mp4,.mov">
            <button type="submit">开始上传</button>
          </form>
        </div>
        <p class="tip">上传完成后会自动导入曲库并提取歌手/专辑/封面信息。<br>保持手机和电脑在同一 Wi-Fi,传输期间别锁屏。</p>
        </body></html>
        """
    }

    private static func resultPage(items: [(String, Bool)]) -> String {
        let rows = items.map { name, ok in
            "<li>\(ok ? "✅" : "❌") \(name.replacingOccurrences(of: "<", with: "&lt;"))</li>"
        }.joined()
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1"><title>上传结果</title>
        <style>body{font-family:-apple-system,sans-serif;background:#101613;color:#e8f0ea;max-width:520px;margin:0 auto;padding:32px 20px}
        a{color:#18b86b;font-size:17px}</style></head><body>
        <h1>上传结果</h1><ul>\(rows)</ul>
        \(importing ? "<p class=\"tip\">✅ 已接收, 手机正在后台导入曲库(大文件需要几秒)</p>" : "")
        <p><a href="/">← 继续传</a></p></body></html>
        """
    }
}

// ============================================================================
// 设置页入口视图
// ============================================================================

struct WiFiTransferView: View {
    @EnvironmentObject private var store: TrackStore
    @StateObject private var server = WiFiTransferServer()
    @State private var ipAddress: String = "-"

    var body: some View {
        List {
            Section {
                if server.isRunning {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("电脑浏览器打开:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("http://\(ipAddress):\(server.port)")
                            .font(.system(.title3, design: .monospaced).weight(.bold))
                            .textSelection(.enabled)
                        Text("配对码: \(server.pairingCode)")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                    Button(role: .destructive) {
                        server.stop()
                    } label: {
                        Label("停止服务", systemImage: "stop.circle")
                    }
                } else {
                    Button {
                        ipAddress = WiFiTransferServer.localIPv4() ?? "-"
                        server.onFileReceived = { url, name in
                            do {
                                try await store.importFile(from: url)
                                store.reportImportResult("WiFi 接收: \(name)")
                            } catch {
                                store.reportImportResult("WiFi 接收失败 \(name): \(error.localizedDescription)")
                            }
                            try? FileManager.default.removeItem(at: url)
                        }
                        server.start()
                    } label: {
                        Label("开启 WiFi 传输", systemImage: "wifi")
                    }
                }
            } header: {
                Text("服务")
            } footer: {
                Text(server.lastMessage ?? "手机和电脑连同一个 Wi-Fi,浏览器输入上面的地址即可拖歌进来")
            }

            Section("使用说明") {
                Text("1. 手机和电脑连同一个 Wi-Fi")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("2. 开启服务, 电脑浏览器打开页面上的地址")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("3. 输入配对码, 多选音乐文件上传")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("4. 自动走导入链路: 提取标签/封面、按指纹去重")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack { Text("本次已接收"); Spacer(); Text("\(server.receivedCount) 个") }
            }
        }
        .navigationTitle("WiFi 传歌")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            if server.isRunning { server.stop() }
        }
    }
}