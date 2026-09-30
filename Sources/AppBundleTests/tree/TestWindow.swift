@testable import AppBundle
import AppKit

final class TestWindow: Window, CustomStringConvertible {
    private var _rect: Rect?
    private let getAxRectForTest: (@MainActor () async throws -> Rect?)?
    var isMacosFullscreenForTest = false
    var isMacosMinimizedForTest = false

    override func isMacosMinimized(_ cm: CancellationMode) async throws -> Bool { isMacosMinimizedForTest }

    @MainActor
    private init(
        _ id: UInt32,
        _ parent: NonLeafTreeNodeObject,
        _ adaptiveWeight: CGFloat,
        _ rect: Rect?,
        _ getAxRectForTest: (@MainActor () async throws -> Rect?)?,
    ) {
        _rect = rect
        self.getAxRectForTest = getAxRectForTest
        super.init(id: id, TestApp.shared, lastFloatingSize: nil, parent: parent, adaptiveWeight: adaptiveWeight, index: INDEX_BIND_LAST)
    }

    @discardableResult
    @MainActor
    static func new(
        id: UInt32,
        parent: NonLeafTreeNodeObject,
        adaptiveWeight: CGFloat = 1,
        rect: Rect? = nil,
        getAxRectForTest: (@MainActor () async throws -> Rect?)? = nil,
    ) -> TestWindow {
        let wi = TestWindow(id, parent, adaptiveWeight, rect, getAxRectForTest)
        TestApp.shared._windows.append(wi)
        return wi
    }

    nonisolated var description: String { "TestWindow(\(windowId))" }

    @MainActor
    override func nativeFocus() {
        appForTests = TestApp.shared
        TestApp.shared.focusedWindow = self
    }

    override func closeAxWindow() {
        unbindFromParent()
    }

    override func getTitle(_ cm: CancellationMode) async throws -> String { description }

    @MainActor override func getAxRect(_ cm: CancellationMode) async throws -> Rect? { // todo change to not Optional
        try await getAxRectForTest?() ?? _rect
    }

    @MainActor override func getAxSize(_ cm: CancellationMode) async throws -> CGSize? {
        _rect.map { CGSize(width: $0.width, height: $0.height) }
    }

    override func isMacosFullscreen(_ cm: CancellationMode) async throws -> Bool { isMacosFullscreenForTest }
}
