import XCTest
import ApplicationServices
@testable import HyperWindow


final class SystemAPITests: XCTestCase {

    func testAccessibilityTrustOptionsUseRequestedBoolean() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String

        let prompted = accessibilityTrustOptions(prompt: true) as NSDictionary
        XCTAssertEqual((prompted[key] as? NSNumber)?.boolValue, true)

        let silent = accessibilityTrustOptions(prompt: false) as NSDictionary
        XCTAssertEqual((silent[key] as? NSNumber)?.boolValue, false)
    }

    func testFrontmostWindowUsesCGOrderAcrossWindowLayersForOwner() {
        let point = CGPoint(x: 50, y: 50)
        let fixtures = [
            windowInfo(pid: 10, frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
            windowInfo(pid: 11, frame: CGRect(x: 0, y: 0, width: 100, height: 100), layer: 1),
            [kCGWindowOwnerPID as String: NSNumber(value: 12)],
            windowInfo(
                pid: 13,
                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                layer: 3,
                title: "Front"
            ),
            windowInfo(pid: 13, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        ]

        XCTAssertEqual(
            frontmostWindow(at: point, in: fixtures, ownedBy: 13),
            CGWindowHit(
                ownerPID: 13,
                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                title: "Front"
            )
        )
    }

    func testFrontmostWindowReturnsNilWithoutContainingBoundsForOwner() {
        let fixtures = [
            windowInfo(pid: 10, frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
            windowInfo(pid: 11, frame: CGRect(x: 0, y: 0, width: 10, height: 10)),
            [kCGWindowOwnerPID as String: NSNumber(value: 11)]
        ]

        XCTAssertNil(
            frontmostWindow(
                at: CGPoint(x: 50, y: 50),
                in: fixtures,
                ownedBy: 11
            )
        )
    }

    func testAXWindowMatchingPrefersFrameWithinTolerance() {
        let hit = CGWindowHit(
            ownerPID: 10,
            frame: CGRect(x: 100, y: 200, width: 800, height: 600),
            title: "Document"
        )
        let candidates = [
            AXWindowMatchCandidate(
                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                title: "Document"
            ),
            AXWindowMatchCandidate(
                frame: CGRect(x: 102, y: 198, width: 798, height: 602),
                title: "Other"
            )
        ]

        XCTAssertEqual(matchingWindowIndex(for: hit, candidates: candidates), 1)
    }

    func testAXWindowMatchingFallsBackToTitle() {
        let hit = CGWindowHit(
            ownerPID: 10,
            frame: CGRect(x: 100, y: 200, width: 800, height: 600),
            title: "Document"
        )
        let candidates = [
            AXWindowMatchCandidate(frame: nil, title: "Other"),
            AXWindowMatchCandidate(frame: nil, title: "Document")
        ]

        XCTAssertEqual(matchingWindowIndex(for: hit, candidates: candidates), 1)
    }

    func testAXWindowMatchingReturnsNilWithoutFrameOrTitleMatch() {
        let hit = CGWindowHit(
            ownerPID: 10,
            frame: CGRect(x: 100, y: 200, width: 800, height: 600),
            title: nil
        )
        let candidates = [
            AXWindowMatchCandidate(
                frame: CGRect(x: 102.1, y: 200, width: 800, height: 600),
                title: "Document"
            ),
            AXWindowMatchCandidate(frame: nil, title: nil)
        ]

        XCTAssertNil(matchingWindowIndex(for: hit, candidates: candidates))
    }

    func testAccessibilityHitDeterminesOwnerBeforeCGMatching() {
        let point = CGPoint(x: 50, y: 50)
        let overlayPID = getpid() + 1
        let targetPID = getpid() + 2
        let hitTestWindow = AXUIElementCreateApplication(targetPID)
        let matchedWindow = AXUIElementCreateSystemWide()
        var resolvedHit: CGWindowHit?

        let result = AXUIElement.window(
            at: point,
            windowInfoProvider: {
                [
                    self.windowInfo(
                        pid: overlayPID,
                        frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                        layer: 24
                    ),
                    self.windowInfo(
                        pid: targetPID,
                        frame: CGRect(x: 0, y: 0, width: 100, height: 100)
                    )
                ]
            },
            accessibilityWindowProvider: {
                resolvedHit = $0
                return matchedWindow
            },
            accessibilityHitTest: { _ in hitTestWindow }
        )

        XCTAssertEqual(resolvedHit?.ownerPID, targetPID)
        XCTAssertTrue(CFEqual(result, matchedWindow))
    }

    func testFloatingCGWindowUsesExactCGMatchRegardlessOfLayer() {
        let point = CGPoint(x: 50, y: 50)
        let ownerPID = getpid() + 1
        let fixture = windowInfo(
            pid: ownerPID,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            layer: 3
        )
        let hitTestWindow = AXUIElementCreateApplication(ownerPID)
        let matchedWindow = AXUIElementCreateSystemWide()

        let result = AXUIElement.window(
            at: point,
            windowInfoProvider: { [fixture] },
            accessibilityWindowProvider: { hit in
                XCTAssertEqual(hit.ownerPID, ownerPID)
                return matchedWindow
            },
            accessibilityHitTest: { _ in hitTestWindow }
        )

        XCTAssertTrue(CFEqual(result, matchedWindow))
    }

    func testUnmatchedCGOverlayDoesNotBlockAccessibilityHit() {
        let overlayPID = getpid() + 1
        let targetPID = getpid() + 2
        let hitTestWindow = AXUIElementCreateApplication(targetPID)

        let result = AXUIElement.window(
            at: CGPoint(x: 50, y: 50),
            windowInfoProvider: {
                [
                    self.windowInfo(
                        pid: overlayPID,
                        frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                        layer: 24
                    )
                ]
            },
            accessibilityWindowProvider: { _ in
                XCTFail("CG windows from another process must not override the Accessibility hit")
                return nil
            },
            accessibilityHitTest: { _ in hitTestWindow }
        )

        XCTAssertTrue(CFEqual(result, hitTestWindow))
    }

    func testAccessibilityHitIsFallbackWhenSameOwnerCGWindowCannotBeMatched() {
        let ownerPID = getpid() + 1
        let hitTestWindow = AXUIElementCreateApplication(ownerPID)

        let result = AXUIElement.window(
            at: CGPoint(x: 50, y: 50),
            windowInfoProvider: {
                [self.windowInfo(
                    pid: ownerPID,
                    frame: CGRect(x: 0, y: 0, width: 100, height: 100)
                )]
            },
            accessibilityWindowProvider: { _ in nil },
            accessibilityHitTest: { _ in hitTestWindow }
        )

        XCTAssertTrue(CFEqual(result, hitTestWindow))
    }

    func testMissingAccessibilityHitFailsClosedBeforeReadingCGWindows() {
        var windowInfoCalls = 0

        let result = AXUIElement.window(
            at: CGPoint(x: 50, y: 50),
            windowInfoProvider: {
                windowInfoCalls += 1
                return []
            },
            accessibilityWindowProvider: { _ in
                XCTFail("A missing Accessibility hit must not resolve a CG window")
                return nil
            },
            accessibilityHitTest: { _ in nil }
        )

        XCTAssertNil(result)
        XCTAssertEqual(windowInfoCalls, 0)
    }

    func testOwnAccessibilityHitFailsClosedBeforeReadingCGWindows() {
        var windowInfoCalls = 0

        let result = AXUIElement.window(
            at: CGPoint(x: 50, y: 50),
            windowInfoProvider: {
                windowInfoCalls += 1
                return []
            },
            accessibilityWindowProvider: { _ in
                XCTFail("HyperWindow must not target its own windows")
                return nil
            },
            accessibilityHitTest: { _ in AXUIElementCreateApplication(getpid()) }
        )

        XCTAssertNil(result)
        XCTAssertEqual(windowInfoCalls, 0)
    }

    private func windowInfo(
        pid: pid_t,
        frame: CGRect,
        layer: Int = 0,
        title: String? = nil
    ) -> CGWindowInfo {
        var info: CGWindowInfo = [
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowBounds as String: CGRectCreateDictionaryRepresentation(frame)
        ]
        info[kCGWindowName as String] = title
        return info
    }
}
