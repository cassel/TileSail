@testable import AppBundle
import Common
import Foundation
import Network
import XCTest

final class SocketFramingTest: XCTestCase {
    private func withConnections(_ body: (NWConnection, NWConnection) async throws -> Void) async throws {
        // sockaddr_un has a short path limit; macOS's per-user temp directory can exceed it.
        let directory = URL(filePath: "/private/tmp").appendingPathComponent("tilesail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .unix(path: directory.appendingPathComponent("ipc.sock").path)
        let listener = try NWListener(using: parameters)
        defer { listener.cancel() }
        let listening = expectation(description: "listening")
        listener.stateUpdateHandler = { state in
            switch state {
                case .ready, .failed: listening.fulfill()
                default: break
            }
        }
        let server = ConnectionBox()
        let accepted = expectation(description: "accepted")
        listener.newConnectionHandler = { connection in
            server.connection = connection
            connection.start(queue: .global())
            accepted.fulfill()
        }
        listener.start(queue: .global())
        await fulfillment(of: [listening], timeout: 3)
        guard case .ready = listener.state else {
            XCTFail("Listener did not become ready: \(listener.state)")
            accepted.fulfill()
            await fulfillment(of: [accepted], timeout: 0.1)
            return
        }
        let client = NWConnection(to: parameters.requiredLocalEndpoint!, using: .tcp)
        defer { client.cancel(); server.connection?.cancel() }
        client.start(queue: .global())
        await fulfillment(of: [accepted], timeout: 3)
        let connection = try XCTUnwrap(server.connection)
        // Cancel blocked reads on failure, keeping a regression from hanging the test process.
        let deadline = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { connection.cancel(); client.cancel() }
        }
        defer { deadline.cancel() }
        try await body(client, connection)
    }

    private func send(_ data: Data, over connection: NWConnection, final: Bool = false) async throws {
        let error: NWError? = await withCheckedContinuation { continuation in
            connection.send(content: data, contentContext: final ? .finalMessage : .defaultMessage,
                            isComplete: true, completion: .contentProcessed { continuation.resume(returning: $0) })
        }
        if let error { throw error }
    }

    private func header(_ count: UInt32) -> Data {
        unsafe withUnsafeBytes(of: count) { unsafe Data($0) }
    }

    func testGracefulEOFAndTruncatedFramesFailPromptly() async throws {
        for bytes in [Data(), Data([1, 0]), header(4) + Data([1, 2])] {
            try await withConnections { client, server in
                try await self.send(bytes, over: client, final: true)
                let start = Date()
                let result = await server.readNonAtomic()
                guard case .failure(.posix(let error)) = result,
                      error == .ECONNRESET || error == .ENODATA else {
                    return XCTFail("Expected graceful EOF error, got \(result)")
                }
                XCTAssertLessThan(Date().timeIntervalSince(start), 2)
            }
        }
    }

    func testOversizeHeaderRejectedWithoutBody() async throws {
        try await withConnections { client, server in
            try await self.send(self.header(UInt32.max), over: client)
            guard case .failure(.posix(.EMSGSIZE)) = await server.readNonAtomic() else {
                return XCTFail("An oversized frame must fail before allocation or reading its body")
            }
        }
    }

    func testFragmentedFrameAndEmptyFrameRemainCompatible() async throws {
        try await withConnections { client, server in
            let data = Data("hello".utf8)
            let prefix = self.header(UInt32(data.count))
            try await self.send(Data(prefix.prefix(2)), over: client)
            try await self.send(Data(prefix.suffix(2)) + Data(data.prefix(2)), over: client)
            try await self.send(Data(data.suffix(3)), over: client)
            let payload = try await server.readNonAtomic().get()
            XCTAssertEqual(payload, data)
            try await self.send(self.header(0), over: client)
            let empty = try await server.readNonAtomic().get()
            XCTAssertEqual(empty, Data())
        }
    }

    func testWriterRejectsOversizePayload() async throws {
        try await withConnections { client, _ in
            let result = await client.writeAtomic(String(repeating: "x", count: NWConnection.maximumFrameSize))
            XCTAssertEqual(result.error, .posix(.EMSGSIZE)) // JSON adds quotation marks.
        }
    }

    func testOversizeServerAnswerReportsErrorAndPreservesConnectionFraming() async throws {
        try await withConnections { client, server in
            let oversized = ServerAnswer(
                exitCode: EXIT_CODE_ZERO,
                stdout: String(repeating: "x", count: NWConnection.maximumFrameSize),
                serverVersionAndHash: "test-version test-hash",
            )
            let start = Date()
            await sendServerAnswer(oversized, over: server)
            let payload = try await client.readNonAtomic().get()
            let answer = try JSONDecoder().decode(ServerAnswer.self, from: payload)
            XCTAssertLessThan(Date().timeIntervalSince(start), 2)
            XCTAssertEqual(answer.exitCode, EXIT_CODE_TWO)
            XCTAssertEqual(answer.stdout, "")
            XCTAssertTrue(answer.stderr.contains("16 MiB"))
            XCTAssertTrue(answer.stderr.contains("Reduce the output"))
            XCTAssertEqual(answer.serverVersionAndHash, oversized.serverVersionAndHash)

            let normal = ServerAnswer(
                exitCode: EXIT_CODE_ZERO, stdout: "next response", serverVersionAndHash: oversized.serverVersionAndHash,
            )
            await sendServerAnswer(normal, over: server)
            let nextPayload = try await client.readNonAtomic().get()
            let nextAnswer = try JSONDecoder().decode(ServerAnswer.self, from: nextPayload)
            XCTAssertEqual(nextAnswer.exitCode, EXIT_CODE_ZERO)
            XCTAssertEqual(nextAnswer.stdout, normal.stdout)
            XCTAssertEqual(nextAnswer.stderr, "")
            XCTAssertEqual(nextAnswer.serverVersionAndHash, normal.serverVersionAndHash)
        }
    }
}

private final class ConnectionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedConnection: NWConnection?
    var connection: NWConnection? {
        get { lock.withLock { storedConnection } }
        set { lock.withLock { storedConnection = newValue } }
    }
}
