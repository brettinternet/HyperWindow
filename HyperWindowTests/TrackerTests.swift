import XCTest
@testable import HyperWindow

final class TrackerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var now: CFAbsoluteTime = 0
    private var timers: TestTimerDriver!

    override func setUp() {
        super.setUp()
        defaults = testUserDefaults()
        registerDefaultPreferences(in: defaults)
        defaults.set(Modifiers<Move>.control.rawValue, forKey: DefaultsKeys.moveModifiers.rawValue)
        defaults.set(Modifiers<Resize>.alt.rawValue, forKey: DefaultsKeys.resizeModifiers.rawValue)
        defaults.set(false, forKey: DefaultsKeys.resizeFromNearestCorner.rawValue)
        Current.defaults = { [unowned self] in self.defaults }
        now = 0
        timers = TestTimerDriver()
    }

    override func tearDown() {
        Tracker.disable()
        Current.defaults = { UserDefaults(suiteName: "cloud.brett.HyperWindow.prefs") ?? .standard }
        super.tearDown()
    }

    func testHandledEventsRefreshInactivityTimeout() throws {
        let window = FakeWindow()
        let tracker = try makeTracker(window: window)

        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        now = 4
        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl, dx: 1, location: CGPoint(x: 1, y: 0)), type: .mouseMoved))
        now = 8
        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl, dx: 1, location: CGPoint(x: 2, y: 0)), type: .mouseMoved))
        fireTimer()
        XCTAssertEqual(window.origin.x, 2)
    }

    func testIdleToMoveAndResizeTransitions() throws {
        let window = FakeWindow()
        let tracker = try makeTracker(window: window)

        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        now = 1
        XCTAssertTrue(tracker.handleEvent(event(flags: .maskAlternate), type: .mouseMoved))
        now = 2
        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        XCTAssertEqual(window.origin, .zero)
    }

    func testFlagsChangedActivatesMoveAtEventLocationWithoutBeingAbsorbed() throws {
        let window = FakeWindow()
        let tracker = try makeTracker(window: window)

        XCTAssertFalse(tracker.handleEvent(
            event(flags: .maskControl, location: CGPoint(x: 10, y: 10)),
            type: .flagsChanged
        ))
        XCTAssertFalse(tracker.handleEvent(
            event(flags: .maskControl, location: CGPoint(x: 14, y: 10)),
            type: .flagsChanged
        ))
        fireTimer()

        XCTAssertEqual(window.origin, CGPoint(x: 4, y: 0))
    }

    func testFlagsChangedDeactivatesMoveBeforeNextMouseEvent() throws {
        let window = FakeWindow()
        let tracker = try makeTracker(window: window)

        XCTAssertFalse(tracker.handleEvent(
            event(flags: .maskControl, location: .zero),
            type: .flagsChanged
        ))
        XCTAssertFalse(tracker.handleEvent(
            event(flags: [], location: CGPoint(x: 12, y: 0)),
            type: .flagsChanged
        ))
        XCTAssertEqual(window.origin, CGPoint(x: 12, y: 0))
        XCTAssertFalse(tracker.handleEvent(
            event(flags: [], location: CGPoint(x: 12, y: 0)),
            type: .leftMouseDown
        ))
    }

    func testFlagsChangedTransitionsBetweenMoveAndResizeWithoutBeingAbsorbed() throws {
        let window = FakeWindow()
        let tracker = try makeTracker(window: window)

        XCTAssertFalse(tracker.handleEvent(
            event(flags: .maskControl, location: .zero),
            type: .flagsChanged
        ))
        XCTAssertFalse(tracker.handleEvent(
            event(flags: .maskAlternate, location: CGPoint(x: 10, y: 0)),
            type: .flagsChanged
        ))
        XCTAssertFalse(tracker.handleEvent(
            event(flags: .maskAlternate, location: CGPoint(x: 20, y: 0)),
            type: .flagsChanged
        ))
        fireTimer()
        XCTAssertEqual(window.size.width, 110)

        XCTAssertFalse(tracker.handleEvent(
            event(flags: .maskControl, location: CGPoint(x: 20, y: 0)),
            type: .flagsChanged
        ))
        XCTAssertFalse(tracker.handleEvent(
            event(flags: .maskControl, location: CGPoint(x: 25, y: 0)),
            type: .flagsChanged
        ))
        fireTimer()
        XCTAssertEqual(window.origin.x, 5)
    }

    func testFocusesEachMovedAndResizedWindowWhenEnabled() throws {
        defaults.set(true, forKey: DefaultsKeys.focusWindowOnManipulation.rawValue)
        let window = FakeWindow()
        let tracker = try makeTracker(window: window)

        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        XCTAssertTrue(tracker.handleEvent(event(flags: []), type: .mouseMoved))
        XCTAssertTrue(tracker.handleEvent(event(flags: .maskAlternate), type: .mouseMoved))

        XCTAssertEqual(window.focusCount, 2)
    }

    func testDoesNotFocusMovedWindowWhenDisabled() throws {
        let window = FakeWindow()
        let tracker = try makeTracker(window: window)

        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))

        XCTAssertEqual(window.focusCount, 0)
    }

    func testModifierReleaseEndsOperationWithoutConsumingMouseUp() throws {
        let tracker = try makeTracker(window: FakeWindow())
        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        XCTAssertTrue(tracker.handleEvent(event(flags: []), type: .mouseMoved))
        XCTAssertFalse(tracker.handleEvent(event(flags: []), type: .leftMouseUp))
    }

    func testTimeoutResetsOperationAndPassesNextEventThrough() throws {
        let tracker = try makeTracker(window: FakeWindow())
        now = 1
        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        now = 7
        XCTAssertFalse(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        now = 8
        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
    }

    func testDragOnlyEndsOnlyForMatchingMouseUp() throws {
        defaults.set(true, forKey: DefaultsKeys.requireDragToActivate.rawValue)
        let window = FakeWindow()
        let tracker = try makeTracker(window: window)
        XCTAssertFalse(tracker.handleEvent(
            event(flags: .maskControl, button: 1),
            type: .leftMouseDown
        ))
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, button: 1),
            type: .leftMouseDragged
        ))
        XCTAssertFalse(tracker.handleEvent(
            event(flags: [], button: 2, location: CGPoint(x: 5, y: 0)),
            type: .leftMouseUp
        ))
        XCTAssertFalse(tracker.handleEvent(
            event(flags: [], button: 1, location: CGPoint(x: 10, y: 0)),
            type: .leftMouseUp
        ))
        XCTAssertEqual(window.origin, CGPoint(x: 10, y: 0))
        XCTAssertFalse(tracker.handleEvent(
            event(flags: .maskControl, button: 1, location: CGPoint(x: 10, y: 0)),
            type: .leftMouseDown
        ))
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, button: 1, location: CGPoint(x: 10, y: 0)),
            type: .leftMouseDragged
        ))
    }

    func testSyntheticMouseMovedReplacesAbsorbedPointerMovementAndPassesThroughTap() throws {
        var postedEvents: [CGEvent] = []
        let tracker = try makeTracker(
            window: FakeWindow(),
            postMouseMoved: { event, _ in postedEvents.append(event) }
        )

        XCTAssertFalse(tracker.handleEvent(
            event(flags: [], location: CGPoint(x: 5, y: 5)),
            type: .leftMouseDragged
        ))
        XCTAssertTrue(postedEvents.isEmpty)

        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskAlternate, location: CGPoint(x: 10, y: 10)),
            type: .mouseMoved
        ))
        XCTAssertEqual(postedEvents.count, 1)
        XCTAssertEqual(postedEvents[0].location, CGPoint(x: 10, y: 10))
        XCTAssertTrue(postedEvents[0].flags.contains(.maskAlternate))

        XCTAssertFalse(tracker.handleEvent(postedEvents[0], type: .mouseMoved))
        XCTAssertEqual(postedEvents.count, 1)

        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskAlternate, location: CGPoint(x: 20, y: 25)),
            type: .leftMouseDragged
        ))
        XCTAssertEqual(postedEvents.count, 2)
        XCTAssertEqual(postedEvents[1].location, CGPoint(x: 20, y: 25))
        XCTAssertTrue(postedEvents[1].flags.contains(.maskAlternate))

        XCTAssertFalse(tracker.handleEvent(postedEvents[1], type: .mouseMoved))
        XCTAssertEqual(postedEvents.count, 2)

        XCTAssertTrue(tracker.handleEvent(
            event(flags: [], location: CGPoint(x: 20, y: 25)),
            type: .mouseMoved
        ))
        XCTAssertEqual(postedEvents.count, 3)
        defaults.set(true, forKey: DefaultsKeys.requireDragToActivate.rawValue)
        tracker.readModifiers()

        XCTAssertFalse(tracker.handleEvent(
            event(flags: .maskAlternate, location: CGPoint(x: 30, y: 35)),
            type: .leftMouseDown
        ))
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskAlternate, location: CGPoint(x: 30, y: 35)),
            type: .leftMouseDragged
        ))
        XCTAssertEqual(postedEvents.count, 4)
        XCTAssertFalse(tracker.handleEvent(postedEvents[3], type: .mouseMoved))
        XCTAssertEqual(postedEvents.count, 4)

        XCTAssertFalse(tracker.handleEvent(
            event(flags: [], location: CGPoint(x: 30, y: 35)),
            type: .leftMouseUp
        ))
        XCTAssertEqual(postedEvents.count, 4)
    }

    func testNonSettableWindowDoesNotConsumeActivation() throws {
        let window = FakeWindow()
        window.canSetOrigin = false
        let tracker = try makeTracker(window: window)

        XCTAssertFalse(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        XCTAssertEqual(window.origin, .zero)
    }

    func testNonSettableResizeDoesNotConsumeActivation() throws {
        let window = FakeWindow()
        window.canSetSize = false
        let tracker = try makeTracker(window: window)

        XCTAssertFalse(tracker.handleEvent(event(flags: .maskAlternate), type: .mouseMoved))
        XCTAssertEqual(window.size.width, 100)
    }

    func testFailedWriteResetsTrackingAsynchronously() throws {
        let window = FakeWindow()
        window.failOriginWrite = true
        let tracker = try makeTracker(window: window)

        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, location: CGPoint(x: 1, y: 0)),
            type: .mouseMoved
        ))
        fireTimer()
        XCTAssertEqual(window.originWriteCount, 1)
        fireTimer()
        XCTAssertEqual(window.originWriteCount, 1)
        window.failOriginWrite = false

        let resetCompleted = expectation(description: "write failure reset")
        DispatchQueue.main.async {
            XCTAssertTrue(tracker.handleEvent(
                self.event(flags: .maskControl),
                type: .mouseMoved
            ))
            resetCompleted.fulfill()
        }
        wait(for: [resetCompleted], timeout: 1)
    }

    func testResizeCommitDoesNotReadBackPositionOrSize() throws {
        defaults.set(true, forKey: DefaultsKeys.resizeFromNearestCorner.rawValue)
        let window = FakeWindow()
        window.origin = CGPoint(x: 100, y: 100)
        let tracker = try makeTracker(window: window)

        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskAlternate, location: CGPoint(x: 100, y: 100)),
            type: .mouseMoved
        ))
        let originReadsAtStart = window.originReadCount
        let sizeReadsAtStart = window.sizeReadCount

        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskAlternate, location: CGPoint(x: 90, y: 90)),
            type: .mouseMoved
        ))
        fireTimer()

        XCTAssertEqual(window.originWriteCount, 1)
        XCTAssertEqual(window.sizeWriteCount, 1)
        XCTAssertEqual(window.originReadCount, originReadsAtStart)
        XCTAssertEqual(window.sizeReadCount, sizeReadsAtStart)
    }

    func testResizeTrustsRequestedSizeWhileNativeClampStaysPinned() throws {
        let window = FakeWindow()
        window.minimumWidth = 50
        let tracker = try makeTracker(window: window)

        XCTAssertTrue(tracker.handleEvent(event(flags: .maskAlternate), type: .mouseMoved))
        now = 1
        XCTAssertTrue(tracker.handleEvent(event(flags: .maskAlternate, dx: -90, location: CGPoint(x: -90, y: 0)), type: .mouseMoved))
        fireTimer()
        XCTAssertEqual(window.size.width, 50)

        now = 2
        XCTAssertTrue(tracker.handleEvent(event(flags: .maskAlternate, dx: 10, location: CGPoint(x: -80, y: 0)), type: .mouseMoved))
        fireTimer()
        XCTAssertEqual(window.size.width, 50)

        now = 3
        XCTAssertTrue(tracker.handleEvent(event(flags: .maskAlternate, dx: 40, location: CGPoint(x: -40, y: 0)), type: .mouseMoved))
        fireTimer()
        XCTAssertEqual(window.size.width, 60)
    }

    func testResizeAccumulatesDeltasBetweenTimerTicks() throws {
        let window = FakeWindow()
        let tracker = try makeTracker(window: window)

        XCTAssertTrue(tracker.handleEvent(event(flags: .maskAlternate), type: .mouseMoved))
        now = 0.005
        XCTAssertTrue(tracker.handleEvent(event(flags: .maskAlternate, dx: 1, location: CGPoint(x: 1, y: 0)), type: .mouseMoved))
        now = 0.010
        XCTAssertTrue(tracker.handleEvent(event(flags: .maskAlternate, dx: 2, location: CGPoint(x: 3, y: 0)), type: .mouseMoved))
        now = 0.030
        XCTAssertTrue(tracker.handleEvent(event(flags: .maskAlternate, dx: 3, location: CGPoint(x: 6, y: 0)), type: .mouseMoved))
        fireTimer()

        XCTAssertEqual(window.size.width, 106)
    }

    func testSubpixelResizeRoundsTargetWithoutLosingAccumulation() throws {
        defaults.set(true, forKey: DefaultsKeys.resizeFromNearestCorner.rawValue)
        let window = FakeWindow()
        let tracker = try makeTracker(window: window)

        XCTAssertTrue(tracker.handleEvent(event(flags: .maskAlternate), type: .mouseMoved))

        for offset in [0.2, 0.4] {
            XCTAssertTrue(tracker.handleEvent(
                event(flags: .maskAlternate, location: CGPoint(x: offset, y: offset)),
                type: .mouseMoved
            ))
            fireTimer()
        }
        XCTAssertEqual(window.originWriteCount, 0)
        XCTAssertEqual(window.sizeWriteCount, 0)

        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskAlternate, location: CGPoint(x: 0.6, y: 0.6)),
            type: .mouseMoved
        ))
        fireTimer()

        XCTAssertEqual(window.origin, CGPoint(x: 1, y: 1))
        XCTAssertEqual(window.size, CGSize(width: 99, height: 99))
        XCTAssertEqual(window.originWriteCount, 1)
        XCTAssertEqual(window.sizeWriteCount, 1)

        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskAlternate, location: CGPoint(x: 0.8, y: 0.8)),
            type: .mouseMoved
        ))
        fireTimer()
        XCTAssertEqual(window.originWriteCount, 1)
        XCTAssertEqual(window.sizeWriteCount, 1)
    }

    func testActivationLookupCompletesOutsideEventCallback() throws {
        let window = FakeWindow()
        var activationWork: (() -> Void)?
        var lookups = 0
        let tracker = try makeTracker(
            window: window,
            windowAt: { _ in
                lookups += 1
                return window.trackingWindow
            },
            enqueueActivation: { activationWork = $0 }
        )

        XCTAssertFalse(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        XCTAssertEqual(lookups, 0)

        XCTAssertFalse(tracker.handleEvent(
            event(flags: .maskControl, location: CGPoint(x: 12, y: 4)),
            type: .mouseMoved
        ))
        activationWork?()
        XCTAssertEqual(lookups, 1)
        fireTimer()
        XCTAssertEqual(window.origin, CGPoint(x: 12, y: 4))
    }

    func testModifierReleaseCancelsPendingActivation() throws {
        var activationWork: (() -> Void)?
        var timersCreated = 0
        let tracker = try makeTracker(
            window: FakeWindow(),
            makeTimer: { _ in
                timersCreated += 1
                return nil
            },
            enqueueActivation: { activationWork = $0 }
        )

        XCTAssertFalse(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        XCTAssertFalse(tracker.handleEvent(event(flags: []), type: .flagsChanged))
        activationWork?()
        XCTAssertEqual(timersCreated, 0)
    }

    func testDragOnlyPreflightActivatesWhenReadyBeforeFirstDrag() throws {
        defaults.set(true, forKey: DefaultsKeys.requireDragToActivate.rawValue)
        var activationWork: (() -> Void)?
        let tracker = try makeTracker(
            window: FakeWindow(),
            enqueueActivation: { activationWork = $0 }
        )

        XCTAssertFalse(tracker.handleEvent(
            event(flags: .maskControl, button: 1),
            type: .leftMouseDown
        ))
        activationWork?()
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, button: 1, location: CGPoint(x: 5, y: 0)),
            type: .leftMouseDragged
        ))
    }

    func testDragOnlyPassesWholeGestureWhenPreflightIsLate() throws {
        defaults.set(true, forKey: DefaultsKeys.requireDragToActivate.rawValue)
        var activationWork: (() -> Void)?
        let tracker = try makeTracker(
            window: FakeWindow(),
            enqueueActivation: { activationWork = $0 }
        )

        XCTAssertFalse(tracker.handleEvent(
            event(flags: .maskControl, button: 1),
            type: .leftMouseDown
        ))
        XCTAssertFalse(tracker.handleEvent(
            event(flags: .maskControl, button: 1, location: CGPoint(x: 5, y: 0)),
            type: .leftMouseDragged
        ))
        activationWork?()
        XCTAssertFalse(tracker.handleEvent(
            event(flags: .maskControl, button: 1, location: CGPoint(x: 10, y: 0)),
            type: .leftMouseDragged
        ))
    }


    func testTapDisablePassesEventThroughAndResetsTracking() throws {
        let tracker = try makeTracker(window: FakeWindow())

        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        XCTAssertFalse(tracker.handleEvent(event(flags: []), type: .tapDisabledByTimeout))
        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
    }

    func testResizeOvershootRemainsAtNativeMinimumUntilRequestedSizeRecovers() throws {
        let window = FakeWindow()
        window.minimumWidth = 50
        let tracker = try makeTracker(window: window)

        XCTAssertTrue(tracker.handleEvent(event(flags: .maskAlternate), type: .mouseMoved))
        now = 1
        XCTAssertTrue(tracker.handleEvent(event(flags: .maskAlternate, dx: -150, location: CGPoint(x: -150, y: 0)), type: .mouseMoved))
        fireTimer()
        XCTAssertEqual(window.size.width, 50)

        now = 2
        XCTAssertTrue(tracker.handleEvent(event(flags: .maskAlternate, dx: -10, location: CGPoint(x: -160, y: 0)), type: .mouseMoved))
        fireTimer()
        XCTAssertEqual(window.size.width, 50)
        XCTAssertEqual(window.sizeWriteCount, 1)

        now = 3
        XCTAssertTrue(tracker.handleEvent(event(flags: .maskAlternate, dx: 20, location: CGPoint(x: -140, y: 0)), type: .mouseMoved))
        fireTimer()
        XCTAssertEqual(window.size.width, 50)

        now = 4
        XCTAssertTrue(tracker.handleEvent(event(flags: .maskAlternate, dx: 39, location: CGPoint(x: -101, y: 0)), type: .mouseMoved))
        fireTimer()
        XCTAssertEqual(window.size.width, 60)
    }

    func testMoveKeepsTitleBarVisibleAcrossDisplays() throws {
        let window = FakeWindow()
        let displays = [
            DisplayFrame(visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)),
            DisplayFrame(visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 800))
        ]
        let tracker = try makeTracker(window: window, displays: { displays })

        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        now = 1
        // Coordinates are Accessibility points (top-left origin, Y down). The
        // proposed origin is below the secondary display and is clamped so its
        // title bar remains reachable.
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, dx: 1_900, dy: 1_000, location: CGPoint(x: 1_900, y: 1_000)),
            type: .mouseMoved
        ))
        fireTimer()
        XCTAssertEqual(window.origin, CGPoint(x: 1_900, y: 776))
    }

    func testSmallMoveDeltasCanCrossDisplayBoundary() throws {
        let window = FakeWindow()
        window.origin = CGPoint(x: 920, y: 100)
        let displays = [
            DisplayFrame(visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)),
            DisplayFrame(visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 800))
        ]
        let tracker = try makeTracker(window: window, displays: { displays })

        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, location: CGPoint(x: 990, y: 100)),
            type: .mouseMoved
        ))
        now = 1
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, dx: 10, location: CGPoint(x: 1_001, y: 100)),
            type: .mouseMoved
        ))
        fireTimer()
        XCTAssertEqual(window.origin.x, 931)
    }

    func testPinnedPointerIgnoresRawDeltaThenFollowsAbsoluteLocation() throws {
        let window = FakeWindow()
        window.size = CGSize(width: 100.25, height: 100.25)
        let tracker = try makeTracker(window: window)
        let location = CGPoint(x: 100, y: 100)

        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, location: location),
            type: .mouseMoved
        ))
        now = 1
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, dx: 20, dy: 19, location: location),
            type: .mouseMoved
        ))
        fireTimer()
        XCTAssertEqual(window.origin, .zero)

        now = 2
        let subpixelNoise = CGPoint(x: 100.4, y: 100.4)
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, dx: 0, dy: 0, location: subpixelNoise),
            type: .mouseMoved
        ))
        fireTimer()
        XCTAssertEqual(window.origin, .zero)
        XCTAssertEqual(window.originWriteCount, 0)

        let movedLocation = CGPoint(x: 100.6, y: 101.25)
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, dx: 0, dy: 0, location: movedLocation),
            type: .mouseMoved
        ))
        fireTimer()
        XCTAssertEqual(window.origin, CGPoint(x: 1, y: 1))
        XCTAssertEqual(window.sizeWriteCount, 0)
    }

    func testMoveAnchorAccumulatesThroughUnappliedOriginWritesAndReverses() throws {
        let window = FakeWindow()
        window.originWriteThreshold = 3
        let tracker = try makeTracker(window: window)
        let start = CGPoint(x: 100, y: 100)

        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, location: start),
            type: .mouseMoved
        ))
        for step in 1...3 {
            now = CFAbsoluteTime(step)
            XCTAssertTrue(tracker.handleEvent(
                event(flags: .maskControl, location: CGPoint(x: 100 + step, y: 100)),
                type: .mouseMoved
            ))
        }
        fireTimer()
        XCTAssertEqual(window.origin, CGPoint(x: 3, y: 0))

        now = 4
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, location: start),
            type: .mouseMoved
        ))
        fireTimer()
        XCTAssertEqual(window.origin, .zero)
    }

    func testSlowAndFastMotionProduceTheSameFinalOrigin() throws {
        let displays = [
            DisplayFrame(visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)),
            DisplayFrame(visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 800))
        ]

        let slowWindow = FakeWindow()
        slowWindow.origin = CGPoint(x: 920, y: 100)
        let slowTracker = try makeTracker(window: slowWindow, displays: { displays })
        XCTAssertTrue(slowTracker.handleEvent(
            event(flags: .maskControl, location: CGPoint(x: 990, y: 100)),
            type: .mouseMoved
        ))
        for step in 1...7 {
            now = CFAbsoluteTime(step)
            XCTAssertTrue(slowTracker.handleEvent(
                event(flags: .maskControl, dx: 10, location: CGPoint(x: 990 + step * 10, y: 100)),
                type: .mouseMoved
            ))
        }
        fireTimer()

        now = 0
        let fastWindow = FakeWindow()
        fastWindow.origin = CGPoint(x: 920, y: 100)
        let fastTracker = try makeTracker(window: fastWindow, displays: { displays })
        XCTAssertTrue(fastTracker.handleEvent(
            event(flags: .maskControl, location: CGPoint(x: 990, y: 100)),
            type: .mouseMoved
        ))
        now = 1
        XCTAssertTrue(fastTracker.handleEvent(
            event(flags: .maskControl, dx: 70, location: CGPoint(x: 1_060, y: 100)),
            type: .mouseMoved
        ))
        fireTimer()

        XCTAssertEqual(slowWindow.origin, fastWindow.origin)
        XCTAssertEqual(fastWindow.origin.x, 990)
    }

    func testVerticallyOffsetDisplaysConstrainOnlyTheUnreachableGap() throws {
        let window = FakeWindow()
        window.origin = CGPoint(x: 920, y: 100)
        let displays = [
            DisplayFrame(visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)),
            DisplayFrame(visibleFrame: CGRect(x: 1000, y: 200, width: 1000, height: 800))
        ]
        let tracker = try makeTracker(window: window, displays: { displays })

        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, location: CGPoint(x: 990, y: 100)),
            type: .mouseMoved
        ))
        now = 1
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, dx: 10, location: CGPoint(x: 1_000, y: 100)),
            type: .mouseMoved
        ))
        fireTimer()
        XCTAssertEqual(window.origin, CGPoint(x: 920, y: 100))

        now = 2
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, dx: 10, dy: 100, location: CGPoint(x: 1_010, y: 200)),
            type: .mouseMoved
        ))
        fireTimer()
        XCTAssertEqual(window.origin, CGPoint(x: 940, y: 200))
    }

    func testTitleBarCanStraddleVerticallyAdjacentDisplays() throws {
        let window = FakeWindow()
        window.origin = CGPoint(x: 100, y: 790)
        let displays = [
            DisplayFrame(visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)),
            DisplayFrame(visibleFrame: CGRect(x: 0, y: 800, width: 1000, height: 800))
        ]
        let tracker = try makeTracker(window: window, displays: { displays })

        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, location: CGPoint(x: 150, y: 790)),
            type: .mouseMoved
        ))
        now = 1
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, dx: 10, location: CGPoint(x: 160, y: 790)),
            type: .mouseMoved
        ))
        fireTimer()
        XCTAssertEqual(window.origin, CGPoint(x: 110, y: 790))
    }

    func testGenuineHorizontalGapDoesNotAddDisjointTitleBarFragments() {
        let displays = [
            DisplayFrame(visibleFrame: CGRect(x: 0, y: 0, width: 40, height: 800)),
            DisplayFrame(visibleFrame: CGRect(x: 60, y: 0, width: 40, height: 800)),
            DisplayFrame(visibleFrame: CGRect(x: 200, y: 0, width: 100, height: 800))
        ]
        let constrained = constrainedOrigin(
            proposed: CGPoint(x: 0, y: 100),
            windowSize: CGSize(width: 100, height: 100),
            displays: displays
        )
        XCTAssertEqual(constrained, CGPoint(x: 180, y: 100))
    }

    func testNarrowDisplayCannotSatisfyMinimumTitleBarWidth() {
        let displays = [
            DisplayFrame(visibleFrame: CGRect(x: 0, y: 0, width: 67, height: 800)),
            DisplayFrame(visibleFrame: CGRect(x: 200, y: 0, width: 100, height: 800))
        ]
        let constrained = constrainedOrigin(
            proposed: CGPoint(x: 0, y: 100),
            windowSize: CGSize(width: 100, height: 100),
            displays: displays
        )
        XCTAssertEqual(constrained, CGPoint(x: 180, y: 100))
    }

    func testOuterBoundaryKeepsMinimumTitleBarVisible() throws {
        let window = FakeWindow()
        let displays = [DisplayFrame(visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))]
        let tracker = try makeTracker(window: window, displays: { displays })

        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, location: CGPoint(x: 0, y: 100)),
            type: .mouseMoved
        ))
        now = 1
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, dx: 2_000, dy: 100, location: CGPoint(x: 2_000, y: 100)),
            type: .mouseMoved
        ))
        fireTimer()
        XCTAssertEqual(window.origin, CGPoint(x: 920, y: 0))
    }

    func testClampedTopLeftResizeStopsAtRequestedMinimumWithoutReadBack() throws {
        defaults.set(true, forKey: DefaultsKeys.resizeFromNearestCorner.rawValue)
        let window = FakeWindow()
        window.origin = CGPoint(x: 100, y: 100)
        window.minimumWidth = 50
        window.minimumHeight = 40
        let tracker = try makeTracker(window: window)

        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskAlternate, location: CGPoint(x: 100, y: 100)),
            type: .mouseMoved
        ))
        now = 1
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskAlternate, location: CGPoint(x: 250, y: 250)),
            type: .mouseMoved
        ))
        fireTimer()
        XCTAssertEqual(window.size, CGSize(width: 50, height: 40))
        XCTAssertEqual(window.origin, CGPoint(x: 199, y: 199))
        XCTAssertEqual(window.sizeWriteCount, 1)
        XCTAssertEqual(window.originWriteCount, 1)

        now = 2
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskAlternate, location: CGPoint(x: 260, y: 260)),
            type: .mouseMoved
        ))
        fireTimer()
        XCTAssertEqual(window.size, CGSize(width: 50, height: 40))
        XCTAssertEqual(window.origin, CGPoint(x: 199, y: 199))
        XCTAssertEqual(window.sizeWriteCount, 1)
        XCTAssertEqual(window.originWriteCount, 1)
    }

    func testFailedResizeWriteDoesNotMoveOrigin() throws {
        defaults.set(true, forKey: DefaultsKeys.resizeFromNearestCorner.rawValue)
        let window = FakeWindow()
        window.origin = CGPoint(x: 100, y: 100)
        window.failSizeWrite = true
        let tracker = try makeTracker(window: window)

        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskAlternate, location: CGPoint(x: 100, y: 100)),
            type: .mouseMoved
        ))
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskAlternate, dx: -10, dy: -10, location: CGPoint(x: 90, y: 90)),
            type: .mouseMoved
        ))
        fireTimer()
        window.failSizeWrite = false
        XCTAssertEqual(window.origin, CGPoint(x: 100, y: 100))
    }

    func testAppKitDisplayFramesConvertToAccessibilityCoordinates() {
        let primary = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let appKitFrames = [
            primary,
            CGRect(x: 0, y: 800, width: 1000, height: 600),
            CGRect(x: 1000, y: -400, width: 800, height: 400)
        ]

        let converted = accessibilityDisplayFrames(
            appKitVisibleFrames: appKitFrames,
            primaryFrame: primary
        ).map(\.visibleFrame)

        XCTAssertEqual(converted[0], CGRect(x: 0, y: 0, width: 1000, height: 800))
        XCTAssertEqual(converted[1], CGRect(x: 0, y: -600, width: 1000, height: 600))
        XCTAssertEqual(converted[2], CGRect(x: 1000, y: 800, width: 800, height: 400))
    }

    func testConstrainedOriginLeavesInvalidGeometryUnchanged() {
        let proposed = CGPoint(x: 10, y: 20)
        let displays = [DisplayFrame(visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))]
        XCTAssertEqual(constrainedOrigin(proposed: proposed, windowSize: CGSize(width: CGFloat.nan, height: 10), displays: displays), proposed)
        XCTAssertEqual(constrainedOrigin(proposed: proposed, windowSize: CGSize(width: 0, height: 10), displays: displays), proposed)
    }

    func testConstrainedOriginHandlesTitleBarExactlyFillingDisplayHeight() {
        let displays = [DisplayFrame(visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 24))]
        XCTAssertEqual(
            constrainedOrigin(
                proposed: CGPoint(x: 500, y: 0),
                windowSize: CGSize(width: 100, height: 24),
                displays: displays
            ),
            CGPoint(x: 500, y: 0)
        )
    }

    func testIdleMouseEventsPassThrough() throws {
        let tracker = try makeTracker(window: FakeWindow())

        XCTAssertFalse(tracker.handleEvent(event(flags: []), type: .mouseMoved))
        XCTAssertFalse(tracker.handleEvent(event(flags: .maskShift), type: .mouseMoved))
    }

    func testTapDisabledEventCancelsPendingActivation() throws {
        var activationWork: (() -> Void)?
        var timersCreated = 0
        let tracker = try makeTracker(
            window: FakeWindow(),
            makeTimer: { _ in
                timersCreated += 1
                return nil
            },
            enqueueActivation: { activationWork = $0 }
        )

        XCTAssertFalse(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        XCTAssertFalse(tracker.handleEvent(event(flags: []), type: .tapDisabledByTimeout))
        activationWork?()
        XCTAssertEqual(timersCreated, 0)
    }

    func testTimerCreationFailureResetsTracking() throws {
        let window = FakeWindow()
        let tracker = try makeTracker(window: window, makeTimer: { _ in nil })

        XCTAssertFalse(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        XCTAssertFalse(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        XCTAssertEqual(window.originWriteCount, 0)
        XCTAssertEqual(window.sizeWriteCount, 0)
    }

    func testTimerCommitsOnlyDirtyTargets() throws {
        let window = FakeWindow()
        let tracker = try makeTracker(window: window)

        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        fireTimer()
        XCTAssertEqual(window.originWriteCount, 0)

        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, location: CGPoint(x: 10, y: 5)),
            type: .mouseMoved
        ))
        fireTimer()
        fireTimer()

        XCTAssertEqual(window.origin, CGPoint(x: 10, y: 5))
        XCTAssertEqual(window.originWriteCount, 1)
    }

    func testQueuedDuplicateTargetsProduceOneWrite() throws {
        let window = FakeWindow()
        let commits = ManualCommitExecutor()
        let tracker = try makeTracker(window: window, enqueueCommit: commits.enqueue)

        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, location: CGPoint(x: 10, y: 0)),
            type: .mouseMoved
        ))
        fireTimer()
        fireTimer()
        XCTAssertEqual(commits.count, 2)

        commits.runAll()

        XCTAssertEqual(window.origin, CGPoint(x: 10, y: 0))
        XCTAssertEqual(window.originWriteCount, 1)
    }

    func testQueuedResizeCommitsDropStaleTargets() throws {
        let window = FakeWindow()
        let commits = ManualCommitExecutor()
        let tracker = try makeTracker(window: window, enqueueCommit: commits.enqueue)

        XCTAssertTrue(tracker.handleEvent(event(flags: .maskAlternate), type: .mouseMoved))
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskAlternate, location: CGPoint(x: 10, y: 10)),
            type: .mouseMoved
        ))
        fireTimer()
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskAlternate, location: CGPoint(x: 20, y: 20)),
            type: .mouseMoved
        ))
        fireTimer()
        XCTAssertEqual(commits.count, 2)

        commits.runAll()

        XCTAssertEqual(window.size, CGSize(width: 120, height: 120))
        XCTAssertEqual(window.sizeWriteCount, 1)
    }

    func testFinalCommitUsesModifierReleaseLocationWithoutTimerTick() throws {
        let window = FakeWindow()
        let tracker = try makeTracker(window: window)

        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, location: CGPoint(x: 10, y: 5)),
            type: .mouseMoved
        ))
        XCTAssertEqual(window.originWriteCount, 0)

        XCTAssertTrue(tracker.handleEvent(
            event(flags: [], location: CGPoint(x: 12, y: 7)),
            type: .mouseMoved
        ))

        XCTAssertEqual(window.origin, CGPoint(x: 12, y: 7))
        XCTAssertEqual(window.originWriteCount, 1)
    }


    func testFailedTickCancelsQueuedFinalCommit() throws {
        let window = FakeWindow()
        let gate = BlockingFirstCommitGate()
        let commitQueue = DispatchQueue(label: "TrackerTests.failed-tick")
        let tracker = try makeTracker(
            window: window,
            enqueueCommit: { work in commitQueue.async(execute: work) },
            commitApplyGate: gate.enter
        )

        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, location: CGPoint(x: 10, y: 0)),
            type: .mouseMoved
        ))
        fireTimer()
        XCTAssertTrue(gate.waitUntilBlocked(timeout: 1))

        XCTAssertTrue(tracker.handleEvent(
            event(flags: [], location: CGPoint(x: 12, y: 0)),
            type: .mouseMoved
        ))
        window.failOriginWrite = true
        gate.release()

        let commitsFinished = expectation(description: "failed tick and final finished")
        commitQueue.async { commitsFinished.fulfill() }
        wait(for: [commitsFinished], timeout: 1)

        XCTAssertEqual(window.originWriteCount, 1)
        XCTAssertEqual(window.origin, .zero)
    }

    func testBlockedTickCannotOverwriteResetOrNewDrag() throws {
        let window = FakeWindow()
        let gate = BlockingFirstCommitGate()
        let commitQueue = DispatchQueue(label: "TrackerTests.blocked-commit")
        let tracker = try makeTracker(
            window: window,
            enqueueCommit: { work in commitQueue.async(execute: work) },
            commitGate: gate.enter
        )

        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, location: CGPoint(x: 10, y: 0)),
            type: .mouseMoved
        ))
        fireTimer()
        XCTAssertTrue(gate.waitUntilBlocked(timeout: 1))

        XCTAssertTrue(tracker.handleEvent(
            event(flags: [], location: CGPoint(x: 10, y: 0)),
            type: .mouseMoved
        ))
        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        XCTAssertTrue(tracker.handleEvent(
            event(flags: .maskControl, location: CGPoint(x: 20, y: 0)),
            type: .mouseMoved
        ))
        fireTimer()

        gate.release()
        let commitsFinished = expectation(description: "serialized commits finished")
        commitQueue.async { commitsFinished.fulfill() }
        wait(for: [commitsFinished], timeout: 1)

        XCTAssertEqual(window.origin, CGPoint(x: 20, y: 0))
        XCTAssertEqual(window.originWriteCount, 2)
    }

    func testConcurrentTimerStress() throws {
        let window = FakeWindow()
        let commitQueue = DispatchQueue(label: "TrackerTests.stress-commit")
        let tracker = try makeTracker(
            window: window,
            enqueueCommit: { work in commitQueue.async(execute: work) }
        )
        let timerDriver = timers!
        let timerGroup = DispatchGroup()

        XCTAssertTrue(tracker.handleEvent(event(flags: .maskControl), type: .mouseMoved))
        for step in 1...200 {
            XCTAssertTrue(tracker.handleEvent(
                event(flags: .maskControl, location: CGPoint(x: step, y: step)),
                type: .mouseMoved
            ))
            timerGroup.enter()
            DispatchQueue.global().async {
                timerDriver.fireLatest()
                timerGroup.leave()
            }
        }
        timerGroup.wait()
        XCTAssertTrue(tracker.handleEvent(
            event(flags: [], location: CGPoint(x: 200, y: 200)),
            type: .mouseMoved
        ))

        let commitsFinished = expectation(description: "stress commits finished")
        commitQueue.async { commitsFinished.fulfill() }
        wait(for: [commitsFinished], timeout: 2)
        XCTAssertEqual(window.origin, CGPoint(x: 200, y: 200))
    }

    private func makeTracker(
        window: FakeWindow,
        windowAt: ((CGPoint) -> TrackingWindow?)? = nil,
        displays: @escaping () -> [DisplayFrame] = { [] },
        makeTimer: ((@escaping () -> Void) -> TrackingTimer?)? = nil,
        enqueueActivation: @escaping (@escaping () -> Void) -> Void = { work in work() },
        enqueueCommit: @escaping (@escaping () -> Void) -> Void = { work in work() },
        commitGate: @escaping () -> Void = {},
        commitApplyGate: @escaping () -> Void = {},
        postMouseMoved: @escaping (CGEvent, CGEventTapProxy?) -> Void = { _, _ in }
    ) throws -> Tracker {
        try Tracker(dependencies: .init(
            windowAt: windowAt ?? { _ in window.trackingWindow },
            now: { self.now },
            displays: displays,
            makeTimer: makeTimer ?? { self.timers.makeTimer(handler: $0) },
            enqueueCommit: enqueueCommit,
            enqueueActivation: enqueueActivation,
            commitGate: commitGate,
            commitApplyGate: commitApplyGate,
            postMouseMoved: postMouseMoved,
            installEventTap: false
        ))
    }

    private func fireTimer() {
        timers.fireLatest()
    }

    private func event(
        flags: CGEventFlags,
        dx: Int32 = 0,
        dy: Int32 = 0,
        button: Int64 = 0,
        location: CGPoint = .zero
    ) -> CGEvent {
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: location,
            mouseButton: .left
        )!
        event.flags = flags
        event.setIntegerValueField(.mouseEventButtonNumber, value: button)
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
        return event
    }
}

private final class FakeWindow {
    private let lock = NSLock()
    private var storedOrigin = CGPoint.zero
    private var storedSize = CGSize(width: 100, height: 100)
    private var storedOriginWriteCount = 0
    private var storedSizeWriteCount = 0
    private var storedOriginReadCount = 0
    private var storedSizeReadCount = 0
    private var storedFocusCount = 0

    var origin: CGPoint {
        get { withLock { storedOrigin } }
        set { withLock { storedOrigin = newValue } }
    }
    var size: CGSize {
        get { withLock { storedSize } }
        set { withLock { storedSize = newValue } }
    }
    var originWriteCount: Int { withLock { storedOriginWriteCount } }
    var sizeWriteCount: Int { withLock { storedSizeWriteCount } }
    var originReadCount: Int { withLock { storedOriginReadCount } }
    var sizeReadCount: Int { withLock { storedSizeReadCount } }
    var focusCount: Int { withLock { storedFocusCount } }

    var canSetOrigin = true
    var canSetSize = true
    var failOriginWrite = false
    var failSizeWrite = false
    var originWriteThreshold: CGFloat = 0
    var minimumWidth: CGFloat = 1
    var minimumHeight: CGFloat = 1

    lazy var trackingWindow = TrackingWindow(
        origin: { [unowned self] in readOrigin() },
        size: { [unowned self] in readSize() },
        canSetOrigin: { [unowned self] in canSetOrigin },
        canSetSize: { [unowned self] in canSetSize },
        focus: { [unowned self] in withLock { storedFocusCount += 1 } },
        setOrigin: { [unowned self] value in setOrigin(value) },
        setSize: { [unowned self] value in setSize(value) }
    )

    private func readOrigin() -> CGPoint {
        withLock {
            storedOriginReadCount += 1
            return storedOrigin
        }
    }

    private func readSize() -> CGSize {
        withLock {
            storedSizeReadCount += 1
            return storedSize
        }
    }

    private func setOrigin(_ value: CGPoint) -> Bool {
        withLock {
            storedOriginWriteCount += 1
            guard !failOriginWrite else { return false }
            if originWriteThreshold > 0,
               value.distance(to: storedOrigin) < originWriteThreshold {
                return true
            }
            storedOrigin = value
            return true
        }
    }

    private func setSize(_ value: CGSize) -> Bool {
        withLock {
            storedSizeWriteCount += 1
            guard !failSizeWrite else { return false }
            storedSize = CGSize(
                width: max(minimumWidth, value.width),
                height: max(minimumHeight, value.height)
            )
            return true
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class TestTimerDriver {
    private final class Entry {
        private let lock = NSLock()
        private let handler: () -> Void
        private var cancelled = false

        init(handler: @escaping () -> Void) {
            self.handler = handler
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        func fire() {
            lock.lock()
            let shouldFire = !cancelled
            lock.unlock()
            if shouldFire {
                handler()
            }
        }

        var isActive: Bool {
            lock.lock()
            defer { lock.unlock() }
            return !cancelled
        }
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    func makeTimer(handler: @escaping () -> Void) -> TrackingTimer {
        let entry = Entry(handler: handler)
        lock.lock()
        entries.append(entry)
        lock.unlock()
        return TrackingTimer(cancel: entry.cancel)
    }

    func fireLatest() {
        lock.lock()
        let entry = entries.last(where: \.isActive)
        lock.unlock()
        entry?.fire()
    }
}

private final class ManualCommitExecutor {
    private var work: [() -> Void] = []

    var count: Int { work.count }

    func enqueue(_ block: @escaping () -> Void) {
        work.append(block)
    }

    func runAll() {
        while !work.isEmpty {
            work.removeFirst()()
        }
    }
}

private final class BlockingFirstCommitGate {
    private let lock = NSLock()
    private let blocked = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)
    private var callCount = 0

    func enter() {
        lock.lock()
        callCount += 1
        let shouldBlock = callCount == 1
        lock.unlock()
        guard shouldBlock else { return }
        blocked.signal()
        released.wait()
    }

    func waitUntilBlocked(timeout: TimeInterval) -> Bool {
        blocked.wait(timeout: .now() + timeout) == .success
    }

    func release() {
        released.signal()
    }
}
