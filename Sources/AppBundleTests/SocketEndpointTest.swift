import Common
import Darwin
import Foundation
import Network
import XCTest

final class SocketEndpointTest: XCTestCase {
    func testUnsafeObjectsSurvive() throws {
        let root = "/private/tmp/ts-" + String(UUID().uuidString.prefix(8))
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let endpoint = SocketEndpoint(bundleId: "test", root: root)
        try endpoint.prepareServer()
        try Data("untouched".utf8).write(to: URL(filePath: endpoint.path))
        XCTAssertThrowsError(try endpoint.prepareServer())
        XCTAssertThrowsError(try endpoint.validateClient())
        XCTAssertEqual(try String(contentsOfFile: endpoint.path, encoding: .utf8), "untouched")
        try FileManager.default.removeItem(atPath: endpoint.path)
        try FileManager.default.createSymbolicLink(atPath: endpoint.path, withDestinationPath: "/dev/null")
        XCTAssertThrowsError(try endpoint.prepareServer())
        XCTAssertThrowsError(try endpoint.validateClient())
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: endpoint.path), "/dev/null")
        try FileManager.default.removeItem(atPath: endpoint.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: endpoint.directory)
        XCTAssertThrowsError(try endpoint.prepareServer())
        XCTAssertThrowsError(try endpoint.validateClient())
        try FileManager.default.removeItem(atPath: endpoint.directory)
        try FileManager.default.createSymbolicLink(atPath: endpoint.directory, withDestinationPath: root)
        XCTAssertThrowsError(try endpoint.prepareServer())
        XCTAssertThrowsError(try endpoint.validateClient())
    }

    func testOwnedStaleSocket() async throws {
        let root = "/private/tmp/ts-" + String(UUID().uuidString.prefix(8))
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let endpoint = SocketEndpoint(bundleId: "test", root: root)
        try endpoint.prepareServer()
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .unix(path: endpoint.path)
        let listener = try NWListener(using: params)
        let ready = expectation(description: "isolated socket listening")
        listener.stateUpdateHandler = { state in
            switch state { case .ready, .failed: ready.fulfill(); default: break }
        }
        listener.newConnectionHandler = { $0.cancel() }
        listener.start(queue: .global())
        await fulfillment(of: [ready], timeout: 3)
        defer { listener.cancel() }
        guard case .ready = listener.state else { XCTFail("Listener failed: \(listener.state)"); return }
        try endpoint.validateClient()
        XCTAssertThrowsError(try endpoint.prepareServer())
        XCTAssertTrue(FileManager.default.fileExists(atPath: endpoint.path))
        try endpoint.validateClient()
        listener.cancel()
    }

    func testClosedBoundSocketIsStale() throws {
        let root = "/private/tmp/ts-" + String(UUID().uuidString.prefix(8))
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let endpoint = SocketEndpoint(bundleId: "test", root: root)
        try endpoint.prepareServer()
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { unsafe $0.copyBytes(from: Array(endpoint.path.utf8) + [0]) }
        let bound = withUnsafePointer(to: &address) { pointer in
            unsafe pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                unsafe Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        close(descriptor)
        XCTAssertEqual(bound, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: endpoint.path))
        try endpoint.prepareServer()
        XCTAssertFalse(FileManager.default.fileExists(atPath: endpoint.path))
    }
}
