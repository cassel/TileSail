import AppKit

struct LayoutFrameTarget: Equatable {
    let window: Window
    let topLeft: CGPoint?
    let size: CGSize?

    static func == (lhs: LayoutFrameTarget, rhs: LayoutFrameTarget) -> Bool {
        lhs.window === rhs.window &&
            lhs.topLeft == rhs.topLeft &&
            lhs.size == rhs.size
    }
}

@MainActor
final class LayoutTransaction {
    private(set) var targets: [UInt32: LayoutFrameTarget] = [:]

    func setFrame(_ window: Window, _ topLeft: CGPoint?, _ size: CGSize?) {
        targets[window.windowId] = LayoutFrameTarget(window: window, topLeft: topLeft, size: size)
    }
}

struct RejectedWindowSize: Equatable {
    let requested: CGSize
    let observed: CGSize
    let confirmations: Int
}

/// Learns when an application consistently clamps a requested AX size. Once a
/// refusal is confirmed, layout passes continue positioning the window but stop
/// resubmitting that impossible size until the requested size changes.
@MainActor
struct LayoutFrameAcceptanceTracker {
    private(set) var rejectedSizes: [UInt32: RejectedWindowSize] = [:]

    mutating func sizeToApply(windowId: UInt32, requested: CGSize?) -> CGSize? {
        guard let requested,
              let rejection = rejectedSizes[windowId],
              rejection.confirmations >= 2,
              sizesAreEffectivelyEqual(requested, rejection.requested)
        else { return requested }
        return nil
    }

    mutating func retain(windowIds: Set<UInt32>) {
        rejectedSizes = rejectedSizes.filter { windowIds.contains($0.key) }
    }

    mutating func observe(windowId: UInt32, requested: CGSize, observed: CGSize) {
        if sizesAreEffectivelyEqual(requested, observed) {
            rejectedSizes.removeValue(forKey: windowId)
            return
        }

        if let previous = rejectedSizes[windowId],
           sizesAreEffectivelyEqual(previous.requested, requested),
           sizesAreEffectivelyEqual(previous.observed, observed)
        {
            rejectedSizes[windowId] = RejectedWindowSize(
                requested: requested,
                observed: observed,
                confirmations: min(previous.confirmations + 1, 2),
            )
        } else {
            rejectedSizes[windowId] = RejectedWindowSize(
                requested: requested,
                observed: observed,
                confirmations: 1,
            )
        }
    }
}

@MainActor
final class LayoutFrameApplier {
    static let shared = LayoutFrameApplier()

    private var verificationTask: Task<Void, Never>?
    private var lastSubmittedTargets: [UInt32: LayoutFrameTarget]?
    private var acceptanceTracker = LayoutFrameAcceptanceTracker()
    private var generation: UInt = 0

    init() {}

    func apply(_ transaction: LayoutTransaction) {
        let targets = transaction.targets
        // Always submit the final frame, including after a user moves a tiled
        // window. MacApp skips AX writes when the frame already matches.
        applyImmediately(targets.values)
        guard lastSubmittedTargets != targets else { return }

        generation &+= 1
        let currentGeneration = generation
        verificationTask?.cancel()
        verificationTask = nil
        lastSubmittedTargets = targets
        acceptanceTracker.retain(windowIds: Set(targets.keys))
        guard !targets.isEmpty else { return }

        // Size acceptance is asynchronous; it never delays applying the frame.
        verificationTask = Task.startUnstructured { @MainActor [weak self] in
            guard let self else { return }
            await verifyAcceptedSizes(Array(targets.values), generation: currentGeneration)
            if generation == currentGeneration {
                verificationTask = nil
            }
        }
    }

    private func applyImmediately(_ targets: Dictionary<UInt32, LayoutFrameTarget>.Values) {
        for target in targets {
            target.window.setAxFrame(
                target.topLeft,
                acceptanceTracker.sizeToApply(windowId: target.window.windowId, requested: target.size),
            )
        }
    }

    private func verifyAcceptedSizes(_ targets: [LayoutFrameTarget], generation expectedGeneration: UInt) async {
        guard !targets.isEmpty else { return }
        // Take two samples after AX has processed the final write. Requiring the
        // same mismatch twice distinguishes a real application constraint from
        // a delayed notification without waiting for another layout transaction.
        for _ in 0 ..< 2 {
            try? await Task.sleep(for: .milliseconds(34))
            guard !Task.isCancelled, generation == expectedGeneration else { return }
            for target in targets {
                guard !Task.isCancelled, generation == expectedGeneration else { return }
                guard let requested = target.size,
                      let actual = try? await target.window.getAxRect(.cancellable)?.size
                else { continue }
                guard !Task.isCancelled, generation == expectedGeneration else { return }
                acceptanceTracker.observe(
                    windowId: target.window.windowId,
                    requested: requested,
                    observed: actual,
                )
            }
        }
    }
}

private func sizesAreEffectivelyEqual(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
    abs(lhs.width - rhs.width) < 1 && abs(lhs.height - rhs.height) < 1
}
