import Darwin
import Foundation

/// Owner-private IPC storage. Same-UID processes remain trusted.
public struct SocketEndpoint: Sendable {
    public let directory: String
    public let name: String
    public var path: String { "\(directory)/\(name)" }

    public init(bundleId: String = aeroSpaceAppId, root: String = "/private/tmp") {
        directory = "\(root)/tilesail-\(geteuid())"
        name = "\(bundleId).sock"
    }

    private func fail(_ message: String) -> NSError {
        NSError(domain: "TileSail.SocketEndpoint", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Socket endpoint \(path): \(message)"])
    }

    private func checkedDirectory(create: Bool) throws -> Int32 {
        guard !name.contains("/"), name != ".", name != "..", path.utf8.count < 104 else {
            throw fail("invalid or excessively long endpoint path")
        }
        if create, unsafe mkdir(directory, 0o700) != 0, errno != EEXIST {
            throw fail("cannot create private directory: \(unsafe String(cString: strerror(errno)))")
        }
        var before = stat()
        guard unsafe lstat(directory, &before) == 0 else { throw fail("cannot inspect private directory") }
        guard before.st_mode & S_IFMT == S_IFDIR, before.st_uid == geteuid(), before.st_mode & 0o7777 == 0o700 else {
            throw fail("directory must be a real directory owned by this UID with mode 0700")
        }
        let fd = unsafe open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw fail("cannot open private directory") }
        var after = stat()
        guard unsafe fstat(fd, &after) == 0,
              before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              after.st_mode & S_IFMT == S_IFDIR, after.st_uid == geteuid(), after.st_mode & 0o7777 == 0o700 else {
            close(fd)
            throw fail("private directory changed during validation")
        }
        return fd
    }

    private func checkedSocket(_ fd: Int32, allowAbsent: Bool) throws -> Bool {
        var value = stat()
        if unsafe fstatat(fd, name, &value, AT_SYMLINK_NOFOLLOW) != 0 {
            if allowAbsent, errno == ENOENT { return false }
            throw fail("cannot inspect socket")
        }
        guard value.st_mode & S_IFMT == S_IFSOCK, value.st_uid == geteuid() else {
            throw fail("endpoint must be a real socket owned by this UID")
        }
        return true
    }

    public func validateClient() throws {
        let fd = try checkedDirectory(create: false)
        defer { close(fd) }
        _ = try checkedSocket(fd, allowAbsent: false)
    }

    private func refuseActiveSocket() throws {
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { throw fail("cannot probe endpoint") }
        defer { close(probe) }
        guard fcntl(probe, F_SETFL, O_NONBLOCK) == 0 else { throw fail("cannot bound endpoint probe") }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            let bytes = Array(path.utf8) + [0]
            unsafe buffer.copyBytes(from: bytes)
        }
        let result = withUnsafePointer(to: &address) { pointer in
            unsafe pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                unsafe connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result == 0 { throw fail("a listener is already active; stop it before starting another server") }
        let code = errno
        guard code == ECONNREFUSED || code == ENOENT else {
            throw fail("endpoint may be active or cannot be safely probed (errno \(code))")
        }
    }

    public func prepareServer() throws {
        let fd = try checkedDirectory(create: true)
        defer { close(fd) }
        if try checkedSocket(fd, allowAbsent: true) {
            var before = stat()
            guard unsafe fstatat(fd, name, &before, AT_SYMLINK_NOFOLLOW) == 0 else { throw fail("cannot inspect stale candidate") }
            try refuseActiveSocket()
            var after = stat()
            if unsafe fstatat(fd, name, &after, AT_SYMLINK_NOFOLLOW) != 0 {
                if errno == ENOENT { return }
                throw fail("cannot recheck stale candidate")
            }
            guard before.st_dev == after.st_dev, before.st_ino == after.st_ino,
                  after.st_mode & S_IFMT == S_IFSOCK, after.st_uid == geteuid() else {
                throw fail("socket changed during stale validation")
            }
            guard unsafe unlinkat(fd, name, 0) == 0 else { throw fail("cannot remove stale owned socket") }
        }
    }
}
