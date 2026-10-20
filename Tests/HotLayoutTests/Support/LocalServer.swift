import Foundation

/// A tiny HTTP/1.0 server on 127.0.0.1 for tests that need a real network stack (cookies,
/// redirects, a body that does not end). One connection at a time, one response per connection.
final class LocalServer: @unchecked Sendable {
    struct Request {
        let path: String
        let headers: [String: String]
    }

    struct Response {
        var status = 200
        var headers: [String: String] = [:]
        /// The body, written in pieces; a piece is produced only when the one before was accepted.
        var chunks: AnyIterator<Data> = AnyIterator([Data]().makeIterator())

        static func data(_ data: Data, type: String = "image/png", headers: [String: String] = [:]) -> Response {
            var all = headers
            all["Content-Type"] = type
            all["Content-Length"] = String(data.count)
            return Response(status: 200, headers: all, chunks: AnyIterator([data].makeIterator()))
        }

        static func redirect(_ location: String) -> Response {
            Response(status: 302, headers: ["Location": location, "Content-Length": "0"])
        }
    }

    private let socketFD: Int32
    let port: UInt16
    private let lock = NSLock()
    private var _requests: [Request] = []
    private var _bytesWritten = 0
    private let handler: (Request) -> Response

    var requests: [Request] { lock.lock(); defer { lock.unlock() }; return _requests }
    /// Bytes of bodies the client accepted (written without an error).
    var bytesWritten: Int { lock.lock(); defer { lock.unlock() }; return _bytesWritten }

    init(handler: @escaping (Request) -> Response) throws {
        self.handler = handler
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 16) == 0 else { throw POSIXError(.EADDRINUSE) }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        port = UInt16(bigEndian: address.sin_port)
        socketFD = fd
        let thread = Thread { [weak self] in self?.serve() }
        thread.start()
    }

    var base: String { "http://127.0.0.1:\(port)" }

    func stop() { close(socketFD) }

    private func serve() {
        while true {
            let client = accept(socketFD, nil, nil)
            guard client >= 0 else { return }
            var yes: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
            DispatchQueue.global().async { self.handle(client) }
        }
    }

    private func handle(_ client: Int32) {
        defer { close(client) }
        var buffer = [UInt8](repeating: 0, count: 65536)
        var received = Data()
        while !(received.range(of: Data("\r\n\r\n".utf8)) != nil) {
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else { return }
            received.append(contentsOf: buffer[0..<count])
        }
        let text = String(decoding: received, as: UTF8.self)
        let lines = text.components(separatedBy: "\r\n")
        let path = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let request = Request(path: path, headers: headers)
        lock.lock(); _requests.append(request); lock.unlock()
        let response = handler(request)
        var head = "HTTP/1.0 \(response.status) X\r\nConnection: close\r\n"
        for (name, value) in response.headers { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        guard write(all: Data(head.utf8), to: client) else { return }
        while let chunk = response.chunks.next() {
            guard write(all: chunk, to: client) else { return }
            lock.lock(); _bytesWritten += chunk.count; lock.unlock()
        }
    }

    private func write(all data: Data, to client: Int32) -> Bool {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(client, raw.baseAddress! + offset, raw.count - offset)
                if written <= 0 { return false }
                offset += written
            }
            return true
        }
    }
}

/// PNG files made in the test, without a drawing: a picture of any size whose file is small.
enum PNGFile {
    /// A grey picture of `width` × `height` pixels, one bit per pixel, all black. The file is a
    /// few kilobytes per million pixels of a side, the decoded bitmap is `width × height × 4` bytes.
    static func blank(width: Int, height: Int) -> Data {
        let rowBytes = (width + 7) / 8 + 1 // the filter byte, then the bits
        let raw = Data(count: rowBytes * height)
        let deflated = (try? (raw as NSData).compressed(using: .zlib)) as Data? ?? Data()
        // zlib stream: header, raw DEFLATE, Adler-32 of the uncompressed data (all zero bytes).
        let adler = (UInt32(raw.count % 65521) << 16) | 1
        var zlib = Data([0x78, 0x01])
        zlib.append(deflated)
        zlib.append(contentsOf: bigEndian(adler))
        var file = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var header = Data()
        header.append(contentsOf: bigEndian(UInt32(width)))
        header.append(contentsOf: bigEndian(UInt32(height)))
        header.append(contentsOf: [1, 0, 0, 0, 0]) // depth 1, grey, deflate, filter 0, no interlace
        file.append(chunk("IHDR", header))
        file.append(chunk("IDAT", zlib))
        file.append(chunk("IEND", Data()))
        return file
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func chunk(_ type: String, _ body: Data) -> Data {
        var out = Data(bigEndian(UInt32(body.count)))
        var crcInput = Data(type.utf8)
        crcInput.append(body)
        out.append(crcInput)
        out.append(contentsOf: bigEndian(crc32(crcInput)))
        return out
    }

    private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in data { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    /// A real 2 × 2 picture, for the requests that must succeed.
    static var small: Data { blank(width: 2, height: 2) }
}
