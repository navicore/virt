import Foundation

/// Lightweight UDP DNS forwarder that listens on the VZ NAT gateway address
/// and forwards queries to a public resolver. Makes DNS "just work" for VMs
/// since Virtualization.framework's NAT advertises the gateway as nameserver
/// but doesn't actually proxy DNS.
final class DNSForwarder {
    static let shared = DNSForwarder()

    private let listenAddress = "192.168.64.1"
    private let listenPort: UInt16 = 53
    private let upstreamAddress = "1.1.1.1"
    private let upstreamPort: UInt16 = 53
    private var socket: Int32 = -1
    private var running = false
    private var refCount = 0
    private let lock = NSLock()
    private var retryCount = 0
    private let maxRetries = 10

    private init() {}

    func start() {
        lock.lock()
        refCount += 1
        let shouldStart = socket == -1
        lock.unlock()

        guard shouldStart else { return }
        retryCount = 0
        attemptStart()
    }

    func stop() {
        lock.lock()
        refCount = max(0, refCount - 1)
        let shouldStop = refCount == 0 && socket != -1
        let fd = socket
        if shouldStop {
            running = false
            socket = -1
        }
        lock.unlock()

        if shouldStop {
            close(fd)
            fputs("[dns] Forwarder stopped\n", stderr)
        }
    }

    private func attemptStart() {
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            fputs("[dns] Failed to create socket: \(String(cString: strerror(errno)))\n", stderr)
            return
        }

        // Allow port sharing
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = listenPort.bigEndian
        inet_pton(AF_INET, listenAddress, &addr.sin_addr)

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if bindResult < 0 {
            close(fd)
            retryCount += 1
            if retryCount <= maxRetries {
                fputs("[dns] Bind failed (\(String(cString: strerror(errno)))), retrying in 2s (\(retryCount)/\(maxRetries))...\n", stderr)
                DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.attemptStart()
                }
            } else {
                fputs("[dns] Forwarder failed after \(maxRetries) retries.\n", stderr)
            }
            return
        }

        lock.lock()
        self.socket = fd
        self.running = true
        lock.unlock()

        fputs("[dns] Forwarder listening on \(listenAddress):53\n", stderr)

        // Run forwarder loop on a background thread
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.forwardLoop(fd: fd)
        }
    }

    private func forwardLoop(fd: Int32) {
        var buf = [UInt8](repeating: 0, count: 4096)
        var clientAddr = sockaddr_in()
        var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        while running {
            let n = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    recvfrom(fd, &buf, buf.count, 0, sockPtr, &clientLen)
                }
            }

            guard n > 0 else {
                if !running { break }
                continue
            }

            // Forward to upstream
            var upAddr = sockaddr_in()
            upAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            upAddr.sin_family = sa_family_t(AF_INET)
            upAddr.sin_port = upstreamPort.bigEndian
            inet_pton(AF_INET, upstreamAddress, &upAddr.sin_addr)

            let upFd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard upFd >= 0 else { continue }

            // Set timeout on upstream socket
            var tv = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(upFd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            let sent = withUnsafePointer(to: &upAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    sendto(upFd, buf, n, 0, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            guard sent > 0 else {
                close(upFd)
                continue
            }

            // Receive response
            var respBuf = [UInt8](repeating: 0, count: 4096)
            let respN = recv(upFd, &respBuf, respBuf.count, 0)
            close(upFd)

            guard respN > 0 else { continue }

            // Send response back to VM
            withUnsafePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    _ = sendto(fd, respBuf, respN, 0, sockPtr, clientLen)
                }
            }
        }
    }
}
