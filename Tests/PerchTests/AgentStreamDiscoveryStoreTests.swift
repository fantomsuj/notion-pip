import Foundation
import XCTest
@testable import Perch

final class AgentStreamDiscoveryStoreTests: XCTestCase {
    func testDefaultFileURLUsesApplicationSupportDirectory() {
        let expected = ApplicationInstanceCoordinator
            .defaultApplicationSupportDirectoryURL
            .appendingPathComponent("agent-server.json")
        XCTAssertEqual(AgentStreamDiscoveryStore.defaultFileURL, expected)
        XCTAssertEqual(
            expected.deletingLastPathComponent(),
            ApplicationInstanceCoordinator.defaultLockFileURL.deletingLastPathComponent()
        )
    }

    func testPublishIsAtomicOwnerOnlyAndLoadRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("agent-server.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = AgentStreamDiscoveryStore(fileURL: fileURL)
        let record = AgentStreamDiscoveryRecord(
            baseURL: "http://127.0.0.1:49152/v1",
            token: "test-token-value",
            pid: 4242,
            startedAt: Date(timeIntervalSince1970: 1_724_500_000)
        )

        try store.publish(record)

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.schemaVersion, 1)
        XCTAssertEqual(loaded.baseURL, record.baseURL)
        XCTAssertEqual(loaded.token, record.token)
        XCTAssertEqual(loaded.pid, record.pid)
        XCTAssertEqual(
            loaded.startedAt.timeIntervalSince1970,
            record.startedAt.timeIntervalSince1970,
            accuracy: 1
        )
    }

    func testRemoveIfMatchesOnlyDeletesCurrentServer() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("agent-server.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = AgentStreamDiscoveryStore(fileURL: fileURL)
        try store.publish(
            AgentStreamDiscoveryRecord(
                baseURL: "http://127.0.0.1:1/v1",
                token: "token-a",
                pid: 11,
                startedAt: Date()
            )
        )

        try store.removeIfMatches(pid: 11, token: "wrong")
        XCTAssertNotNil(try store.load())

        try store.removeIfMatches(pid: 99, token: "token-a")
        XCTAssertNotNil(try store.load())

        try store.removeIfMatches(pid: 11, token: "token-a")
        XCTAssertNil(try store.load())
    }

    func testPublishReplacesExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("agent-server.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = AgentStreamDiscoveryStore(fileURL: fileURL)
        try store.publish(
            AgentStreamDiscoveryRecord(
                baseURL: "http://127.0.0.1:1/v1",
                token: "old",
                pid: 1,
                startedAt: Date()
            )
        )
        try store.publish(
            AgentStreamDiscoveryRecord(
                baseURL: "http://127.0.0.1:2/v1",
                token: "new",
                pid: 2,
                startedAt: Date()
            )
        )

        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.token, "new")
        XCTAssertEqual(loaded.pid, 2)
        XCTAssertEqual(loaded.baseURL, "http://127.0.0.1:2/v1")
    }
}
