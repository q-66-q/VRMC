import Foundation
import Darwin

public enum TransportError: Error, CustomStringConvertible, Sendable {
    case resolve(String)
    case socket(String)
    case connect(Int32)
    case closed
    case send(Int32)
    case receive(Int32)
    case timeout

    public var description: String {
        switch self {
        case .resolve(let host): return "cannot resolve \(host)"
        case .socket(let detail): return "socket error: \(detail)"
        case .connect(let code): return "connect failed (\(code))"
        case .closed: return "connection closed"
        case .send(let code): return "send failed (\(code))"
        case .receive(let code): return "receive failed (\(code))"
        case .timeout: return "timeout"
        }
    }
}

/// Reliable TCP control connection. Plaintext frames are supported for the simulator/demo
/// path; the secure AEAD layer is implemented above this primitive in production builds.
public final class TCPControlConnection: @unchecked Sendable {
    public typealias MessageHandler = @Sendable (ControlHeader, ControlMessage) -> Void
    public typealias FailureHandler = @Sendable (Error?) -> Void

    private let host: String
    private let port: UInt16
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var sequence: UInt32 = 1
    private var running = false
    private var thread: Thread?
    private let onMessage: MessageHandler
    private let onFailure: FailureHandler

    public init(
        host: String,
        port: UInt16,
        onMessage: @escaping MessageHandler,
        onFailure: @escaping FailureHandler
    ) {
        self.host = host
        self.port = port
        self.onMessage = onMessage
        self.onFailure = onFailure
    }

    deinit {
        close()
    }

    public func start() throws {
        let socketFD = try Self.connectSocket(host: host, port: port)
        lock.lock()
        fd = socketFD
        running = true
        lock.unlock()
        let thread = Thread { [weak self] in
            self?.readLoop()
        }
        thread.name = "VRMC Control"
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
    }

    public func send(_ message: ControlMessage, sessionId: UInt32) throws {
        lock.lock()
        let data: Data
        do {
            data = try message.encoded(sessionId: sessionId, sequence: sequence, flags: .plaintext)
            sequence &+= 1
        } catch {
            lock.unlock()
            throw error
        }
        let socketFD = fd
        lock.unlock()
        guard socketFD >= 0 else { throw TransportError.closed }
        try Self.sendAll(fd: socketFD, data: data)
    }

    public func close() {
        lock.lock()
        running = false
        let socketFD = fd
        fd = -1
        lock.unlock()
        if socketFD >= 0 {
            shutdown(socketFD, SHUT_RDWR)
            Darwin.close(socketFD)
        }
    }

    private func readLoop() {
        while true {
            lock.lock()
            let socketFD = fd
            let shouldRun = running
            lock.unlock()
            guard shouldRun, socketFD >= 0 else { return }
            do {
                let headerData = try Self.recvExact(fd: socketFD, count: ProtocolConstants.controlHeaderSize)
                let header = try ControlHeader.decode(from: headerData)
                let payloadData = try Self.recvExact(fd: socketFD, count: Int(header.payloadLength))
                var full = headerData
                full.append(payloadData)
                let (decodedHeader, message) = try ControlMessage.decode(full)
                onMessage(decodedHeader, message)
            } catch {
                lock.lock()
                let wasRunning = running
                running = false
                lock.unlock()
                if wasRunning { onFailure(error) }
                return
            }
        }
    }

    public static func connectSocket(host: String, port: UInt16, timeoutSeconds: Int = 5) throws -> Int32 {
        var hints = addrinfo(
            ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP, ai_addrlen: 0, ai_canonname: nil,
            ai_addr: nil, ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &result)
        guard status == 0, let first = result else {
            throw TransportError.resolve(host)
        }
        defer { freeaddrinfo(result) }
        var lastError: Int32 = 0
        var pointer: UnsafeMutablePointer<addrinfo>? = first
        while let info = pointer {
            let socketFD = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            if socketFD < 0 {
                lastError = errno
                pointer = info.pointee.ai_next
                continue
            }
            var one: Int32 = 1
            setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            var tv = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
            setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            let connectResult = Darwin.connect(socketFD, info.pointee.ai_addr, info.pointee.ai_addrlen)
            if connectResult == 0 {
                return socketFD
            }
            lastError = errno
            Darwin.close(socketFD)
            pointer = info.pointee.ai_next
        }
        throw TransportError.connect(lastError)
    }

    public static func sendAll(fd: Int32, data: Data) throws {
        var offset = 0
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            while offset < data.count {
                let written = Darwin.send(fd, base.advanced(by: offset), data.count - offset, 0)
                if written <= 0 {
                    throw TransportError.send(errno)
                }
                offset += written
            }
        }
    }

    public static func recvExact(fd: Int32, count: Int) throws -> Data {
        guard count >= 0 else { throw TransportError.receive(EINVAL) }
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            while offset < count {
                let read = Darwin.recv(fd, base.advanced(by: offset), count - offset, 0)
                if read == 0 { throw TransportError.closed }
                if read < 0 {
                    if errno == EINTR { continue }
                    throw TransportError.receive(errno)
                }
                offset += read
            }
        }
        return data
    }
}

/// Single UDP socket used for input, media, and feedback. The host learns the client's
/// ephemeral port from the first input/keepalive datagram and sends media there.
public final class UDPTransport: @unchecked Sendable {
    public typealias DatagramHandler = @Sendable (MediaHeader, Data) -> Void
    public typealias FailureHandler = @Sendable (Error?) -> Void

    private let host: String
    private let inputPort: UInt16
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var running = false
    private var thread: Thread?
    private var resolvedHost: sockaddr_in?
    private let onDatagram: DatagramHandler
    private let onFailure: FailureHandler

    public init(
        host: String,
        inputPort: UInt16,
        onDatagram: @escaping DatagramHandler,
        onFailure: @escaping FailureHandler
    ) {
        self.host = host
        self.inputPort = inputPort
        self.onDatagram = onDatagram
        self.onFailure = onFailure
    }

    deinit { close() }

    public func start() throws {
        let socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else { throw TransportError.socket(String(cString: strerror(errno))) }
        var one: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("0.0.0.0")
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(socketFD)
            throw TransportError.socket("udp bind \(errno)")
        }
        var target = sockaddr_in()
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = inputPort.bigEndian
        target.sin_addr.s_addr = inet_addr(host)
        if target.sin_addr.s_addr == INADDR_NONE {
            var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_DGRAM, ai_protocol: IPPROTO_UDP, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
            var result: UnsafeMutablePointer<addrinfo>?
            if getaddrinfo(host, nil, &hints, &result) == 0, let info = result {
                target.sin_addr = info.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                freeaddrinfo(result)
            }
        }
        lock.lock()
        fd = socketFD
        resolvedHost = target
        running = true
        lock.unlock()
        let thread = Thread { [weak self] in self?.receiveLoop() }
        thread.name = "VRMC UDP"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    public var localPort: UInt16? {
        lock.lock()
        defer { lock.unlock() }
        guard fd >= 0 else { return nil }
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        return result == 0 ? UInt16(bigEndian: address.sin_port) : nil
    }

    public func send(_ data: Data, port: UInt16? = nil) throws {
        lock.lock()
        let socketFD = fd
        var address = resolvedHost
        lock.unlock()
        guard socketFD >= 0, var target = address else { throw TransportError.closed }
        if let port { target.sin_port = port.bigEndian }
        address = target
        let result = data.withUnsafeBytes { raw in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.sendto(socketFD, raw.baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if result < 0 { throw TransportError.send(errno) }
    }

    public func close() {
        lock.lock()
        running = false
        let socketFD = fd
        fd = -1
        lock.unlock()
        if socketFD >= 0 { Darwin.close(socketFD) }
    }

    private func receiveLoop() {
        var buffer = [UInt8](repeating: 0, count: 65_535)
        while true {
            lock.lock()
            let socketFD = fd
            let shouldRun = running
            lock.unlock()
            guard shouldRun, socketFD >= 0 else { return }
            let count = buffer.withUnsafeMutableBytes { raw in
                Darwin.recvfrom(socketFD, raw.baseAddress, raw.count, 0, nil, nil)
            }
            if count < 0 {
                if errno == EINTR { continue }
                lock.lock(); let wasRunning = running; running = false; lock.unlock()
                if wasRunning { onFailure(TransportError.receive(errno)) }
                return
            }
            if count == 0 { continue }
            let data = Data(buffer[0..<count])
            do {
                let (header, payload) = try MediaHeader.parseDatagram(data)
                onDatagram(header, payload)
            } catch {
                // Malformed datagrams are dropped and counted by the caller; never crash.
            }
        }
    }
}
