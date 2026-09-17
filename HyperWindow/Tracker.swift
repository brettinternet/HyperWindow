//
//  Tracker.swift
//  Hummingbird
//
//  Created by Sven A. Schmidt on 02/05/2019.
//  Copyright © 2019 finestructure. All rights reserved.
//

import Cocoa

final class TrackingTimer {
    private let lock = NSLock()
    private let cancelHandler: () -> Void
    private var isCancelled = false

    init(cancel: @escaping () -> Void) {
        self.cancelHandler = cancel
    }

    func cancel() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        lock.unlock()
        cancelHandler()
    }

    deinit {
        cancel()
    }
}

private struct EventTapInstallation {
    let eventTap: CFMachPort
    let runLoopSource: CFRunLoopSource?
}


private final class EventTapThread {
    private let ready = DispatchSemaphore(value: 0)
    private let activation = DispatchSemaphore(value: 0)
    private let stopped = DispatchSemaphore(value: 0)
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var startupError: Swift.Error?
    private(set) var eventTap: CFMachPort?

    init(install: @escaping () throws -> EventTapInstallation) throws {
        let thread = Thread { [weak self] in
            self?.run(install: install)
        }
        thread.name = "cloud.brett.HyperWindow.event-tap"
        thread.qualityOfService = .userInteractive
        thread.threadPriority = 1.0
        self.thread = thread
        thread.start()
        ready.wait()

        if let startupError {
            stopped.wait()
            throw startupError
        }
    }

    func startHandlingEvents() {
        activation.signal()
    }

    func perform(_ work: @escaping () -> Void) {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, work)
        CFRunLoopWakeUp(runLoop)
    }

    func performAndWait(_ work: @escaping () -> Void) {
        let completed = DispatchSemaphore(value: 0)
        perform {
            work()
            completed.signal()
        }
        completed.wait()
    }

    func stop() {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
            CFRunLoopStop(runLoop)
        }
        CFRunLoopWakeUp(runLoop)
        stopped.wait()
        self.runLoop = nil
        thread = nil
    }

    private func run(install: @escaping () throws -> EventTapInstallation) {
        autoreleasepool {
            do {
                let installation = try install()
                eventTap = installation.eventTap
                runLoop = CFRunLoopGetCurrent()
                ready.signal()
                activation.wait()

                CGEvent.tapEnable(tap: installation.eventTap, enable: true)
                CFRunLoopRun()
                disableTap(installation)
                eventTap = nil
            } catch {
                startupError = error
                ready.signal()
            }
        }
        stopped.signal()
    }
}




class Tracker {


    struct Dependencies {
        var windowAt: (CGPoint) -> TrackingWindow?
        var now: () -> CFAbsoluteTime
        var displays: () -> [DisplayFrame] = { [] }
        var makeTimer: (@escaping () -> Void) -> TrackingTimer? = { handler in
            let source = DispatchSource.makeTimerSource(
                queue: DispatchQueue.global(qos: .userInteractive)
            )
            source.schedule(
                deadline: .now() + .milliseconds(5),
                repeating: .milliseconds(5),
                leeway: .milliseconds(1)
            )
            source.setEventHandler(handler: handler)
            source.resume()
            return TrackingTimer(cancel: source.cancel)
        }
        var enqueueCommit: (@escaping () -> Void) -> Void
        var enqueueActivation: (@escaping () -> Void) -> Void = { work in work() }
        var commitGate: () -> Void = {}
        var commitApplyGate: () -> Void = {}
        var postMouseMoved: (CGEvent, CGEventTapProxy?) -> Void = { event, proxy in
            if let proxy {
                event.tapPostEvent(proxy)
            } else {
                event.post(tap: .cghidEventTap)
            }
        }
        var installEventTap: Bool

        static var live: Self {
            return Self(
                windowAt: { AXUIElement.window(at: $0)?.trackingWindow },
                now: { CFAbsoluteTimeGetCurrent() },
                displays: {
                    let screens = NSScreen.screens
                    guard let primaryFrame = screens.first?.frame else { return [] }
                    return accessibilityDisplayFrames(
                        appKitVisibleFrames: screens.map(\.visibleFrame),
                        primaryFrame: primaryFrame
                    )
                },
                enqueueCommit: { work in Tracker.commitQueue.async(execute: work) },
                enqueueActivation: { work in Tracker.commitQueue.async(execute: work) },
                installEventTap: true
            )
        }

    }


    private static let commitQueue = DispatchQueue(label: "cloud.brett.HyperWindow.window-commit")

    // Tracker.shared is created and destroyed on the main thread. With a live
    // tap, the tap thread exclusively owns currentState, modifier snapshots,
    // drag-button state, and cursor changes. Tests that skip tap installation
    // retain their existing main-thread ownership. trackingInfo and its
    // generation/commit state are shared with timer and commit queues only
    // through trackingLock; AX writes remain exclusive to commitQueue.
    static var shared: Tracker? = nil

    static func enable() {
        assert(Thread.isMainThread)
        guard isTrusted(prompt: false) else {
            log(.debug, "❌ Cannot enable tracker: accessibility not trusted")
            return
        }
        do {
            shared?.shutdown()
            shared = try .init()
        } catch {
            shared = nil
            log(.error, "Could not create mouse event tap: \(error)")
        }
    }

    static func disable() {
        assert(Thread.isMainThread)
        shared?.shutdown()
        shared = nil
    }

    static var isActive: Bool {
        return shared != nil
    }


    private let trackingInfo = TrackingInfo()
    private let trackingLock = NSLock()
    private var trackingTimer: TrackingTimer?


    private struct CommitSnapshot {
        let window: TrackingWindow
        let rect: CGRect
        let corner: Corner
        let state: State
        let commitState: CommitGenerationState
    }

    private struct PreparedTracking {
        let window: TrackingWindow
        let origin: CGPoint
        let size: CGSize
        let canSetOrigin: Bool
        let canSetSize: Bool
    }

    private struct PendingActivation {
        let generation: UInt64
        let state: State
        let requestLocation: CGPoint
        var location: CGPoint
        let dragButton: Int64?
        let waitForDrag: Bool
        var prepared: PreparedTracking?
    }

    private let dependencies: Dependencies
    private var eventTapThread: EventTapThread?
    private var eventTap: CFMachPort?

    private var currentState: State = .idle
    private var moveModifiers = Modifiers<Move>(forKey: .moveModifiers, defaults: Current.defaults())
    private var resizeModifiers = Modifiers<Resize>(forKey: .resizeModifiers, defaults: Current.defaults())
    private var requireDragToActivate: Bool = Current.defaults().bool(forKey: DefaultsKeys.requireDragToActivate.rawValue)
    private var focusWindowOnManipulation = Current.defaults().bool(
        forKey: DefaultsKeys.focusWindowOnManipulation.rawValue
    )
    private var resizeFromNearestCorner: Bool = Current.defaults().bool(forKey: DefaultsKeys.resizeFromNearestCorner.rawValue)
    private var currentDisplays: [DisplayFrame]
    private var lastEventTime: CFAbsoluteTime = 0
    private var activeDragButton: Int64?
    private var pendingActivation: PendingActivation?
    private var activationGeneration: UInt64 = 0
    private static let maxEventAbsorptionTime: CFAbsoluteTime = 5.0  // Max 5 seconds of continuous absorption
    private static let syntheticMouseMovedMarker: Int64 = 0x4152_4D4F_5645


    init(dependencies: Dependencies = .live) throws {
        self.dependencies = dependencies
        currentDisplays = dependencies.displays()
        if dependencies.installEventTap {
            assert(Thread.isMainThread)
            let tapThread = try EventTapThread { [unowned self] in
                try enableTap(userInfo: Unmanaged.passUnretained(self).toOpaque())
            }
            eventTapThread = tapThread
            eventTap = tapThread.eventTap
            tapThread.startHandlingEvents()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(readModifiers),
                name: UserDefaults.didChangeNotification,
                object: Current.defaults()
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(readDisplays),
                name: NSApplication.didChangeScreenParametersNotification,
                object: nil
            )
        }
    }


    deinit {
        shutdown()
        NotificationCenter.default.removeObserver(self)
    }


    @objc func readModifiers() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.readModifiers()
            }
            return
        }
        guard let eventTapThread else {
            loadModifiers()
            return
        }
        eventTapThread.perform { [weak self] in
            self?.loadModifiers()
        }
    }

    @objc private func readDisplays() {
        assert(Thread.isMainThread)
        let displays = dependencies.displays()
        guard let eventTapThread else {
            currentDisplays = displays
            return
        }
        eventTapThread.perform { [weak self] in
            self?.currentDisplays = displays
        }
    }

    private func loadModifiers() {
        moveModifiers = Modifiers<Move>(forKey: .moveModifiers, defaults: Current.defaults())
        resizeModifiers = Modifiers<Resize>(forKey: .resizeModifiers, defaults: Current.defaults())
        requireDragToActivate = Current.defaults().bool(forKey: DefaultsKeys.requireDragToActivate.rawValue)
        focusWindowOnManipulation = Current.defaults().bool(
            forKey: DefaultsKeys.focusWindowOnManipulation.rawValue
        )
        resizeFromNearestCorner = Current.defaults().bool(forKey: DefaultsKeys.resizeFromNearestCorner.rawValue)
    }
    public func handleEvent(
        _ event: CGEvent,
        type: CGEventType,
        proxy: CGEventTapProxy? = nil
    ) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            log(.debug, "Re-enabling event tap")
            resetTrackingState()
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return false
        }

        if type == .mouseMoved,
           event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMouseMovedMarker {
            return false
        }

        // Check if we should respond to this event type based on drag-only setting
        let isDragEvent = type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged
        let isFlagsChangedEvent = type == .flagsChanged
        let isMoveEvent = type == .mouseMoved
        let isStateReevaluationEvent = isMoveEvent || isFlagsChangedEvent
        let isMouseButtonEvent = type == .leftMouseDown || type == .leftMouseUp || 
                                type == .rightMouseDown || type == .rightMouseUp ||
                                type == .otherMouseDown || type == .otherMouseUp
        let isMouseUp = type == .leftMouseUp || type == .rightMouseUp || type == .otherMouseUp
        let isMouseDown = type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown

        func absorbActiveEvent(_ handled: Bool) -> Bool {
            guard !isFlagsChangedEvent else { return false }
            guard handled else { return false }
            if isMoveEvent || isDragEvent {
                postSyntheticMouseMoved(for: event, proxy: proxy)
            }
            return true
        }
        if requireDragToActivate,
           currentState == .idle,
           pendingActivation == nil,
           isMouseDown {
            let nextState = state(for: event.flags)
            if nextState != .idle {
                requestTracking(
                    at: event.location,
                    state: nextState,
                    dragButton: event.getIntegerValueField(.mouseEventButtonNumber),
                    waitForDrag: true
                )
            }
            return false
        }

        if var pending = pendingActivation,
           isDragEvent || isStateReevaluationEvent || isMouseButtonEvent {
            if requireDragToActivate,
               isMouseUp,
               let button = pending.dragButton,
               event.getIntegerValueField(.mouseEventButtonNumber) == button {
                cancelPendingActivation()
                return false
            }

            guard state(for: event.flags) == pending.state else {
                cancelPendingActivation()
                return false
            }
            pending.location = event.location
            pendingActivation = pending
            if isDragEvent {
                guard pending.prepared != nil else {
                    cancelPendingActivation()
                    return false
                }
                activatePending()
                return currentState != .idle && absorbActiveEvent(true)
            }
            return false
        }

        // Drag-only mode must not consume button transitions. Once a drag has
        // actually started, use its button to identify the matching mouse-up
        // and end the operation before the up event reaches the system.
        if requireDragToActivate {
            if isMouseUp,
               let storedButton = activeDragButton,
               event.getIntegerValueField(.mouseEventButtonNumber) == storedButton {
                _ = updateTargetForRelease(at: event.location)
                resetTrackingState()
                return false
            }
            if isMouseButtonEvent { return false }
        }

        if moveModifiers.isEmpty && resizeModifiers.isEmpty { return false }

        // Re-evaluate active state for mouse and modifier events, but only mouse events may be absorbed.
        if currentState != .idle && (isDragEvent || isStateReevaluationEvent || isMouseButtonEvent) {
            let currentTime = dependencies.now()
            
            // Safety timeout: if we've been absorbing events for too long, reset to idle
            if lastEventTime > 0 && (currentTime - lastEventTime) > Self.maxEventAbsorptionTime {
                log(.error, "⚠️ Event absorption timeout - resetting to idle state to prevent system freeze")
                resetTrackingState()
                return false
            }
            
            if lastEventTime == 0 {
                lastEventTime = currentTime
            }
            
            let nextState = state(for: event.flags)
            
            switch (currentState, nextState) {
                case (.moving, .moving):
                    let handled = move(to: event.location)
                    if handled { lastEventTime = currentTime }
                    return absorbActiveEvent(handled)
                case (.resizing, .resizing):
                    let handled = resize(delta: trackingDelta(at: event.location))
                    if handled { lastEventTime = currentTime }
                    return absorbActiveEvent(handled)
                case (.moving, .idle), (.resizing, .idle):
                    guard updateTargetForRelease(at: event.location) else { return false }
                    resetTrackingState()
                    return absorbActiveEvent(isMouseButtonEvent ? false : true)
                case (.moving, .resizing), (.resizing, .moving):
                    requestTracking(
                        at: event.location,
                        state: nextState,
                        dragButton: activeDragButton,
                        waitForDrag: false
                    )
                    return currentState != .idle && absorbActiveEvent(true)
                default:
                    break
            }
        }

        if requireDragToActivate {
            return false
        }
        if !requireDragToActivate && !isStateReevaluationEvent && !isDragEvent {
            return false  // In normal mode, respond to mouse movement, drags, and modifier changes
        }

        var absorbEvent = false
        let nextState = state(for: event.flags)

        guard nextState != .idle else { return false }

        switch (currentState, nextState) {
            // .idle -> X
            case (.idle, .idle):
                // event is not for us
                break
            case (.idle, .moving),
                 (.idle, .resizing):
                requestTracking(
                    at: event.location,
                    state: nextState,
                    dragButton: requireDragToActivate
                        ? event.getIntegerValueField(.mouseEventButtonNumber)
                        : nil,
                    waitForDrag: false
                )
                absorbEvent = currentState != .idle

            // .moving -> X
            case (.moving, .moving):
                absorbEvent = move(to: event.location)  // Block default actions while moving
            case (.moving, .idle),
                 (.moving, .resizing):
                break

            // .resizing -> X
            case (.resizing, .idle):
                break
            case (.resizing, .moving):
                requestTracking(
                    at: event.location,
                    state: nextState,
                    dragButton: activeDragButton,
                    waitForDrag: false
                )
                absorbEvent = true
            case (.resizing, .resizing):
                absorbEvent = resize(delta: trackingDelta(at: event.location))  // Block default actions while resizing
        }


        return absorbActiveEvent(absorbEvent)
    }

    private func postSyntheticMouseMoved(for event: CGEvent, proxy: CGEventTapProxy?) {
        guard let mouseMoved = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: event.location,
            mouseButton: .left
        ) else { return }
        mouseMoved.flags = event.flags
        mouseMoved.setIntegerValueField(
            .eventSourceUserData,
            value: Self.syntheticMouseMovedMarker
        )
        dependencies.postMouseMoved(mouseMoved, proxy)
    }


    private func resetTrackingState() {
        cancelPendingActivation()
        currentState = .idle
        lastEventTime = 0
        activeDragButton = nil
        finishTrackingInfo()
    }

    private func updateTargetForRelease(at location: CGPoint) -> Bool {
        switch currentState {
        case .moving:
            return move(to: location)
        case .resizing:
            return resize(delta: trackingDelta(at: location))
        case .idle:
            return true
        }
    }



    private func state(for modifiers: CGEventFlags) -> State {
        guard !modifierBindingsConflict(move: moveModifiers, resize: resizeModifiers) else {
            return .idle
        }
        if moveModifiers.exclusivelySet(in: modifiers) {
            return .moving
        }
        if resizeModifiers.exclusivelySet(in: modifiers) {
            return .resizing
        }
        return .idle
    }


    private func requestTracking(
        at location: CGPoint,
        state: State,
        dragButton: Int64?,
        waitForDrag: Bool
    ) {
        currentState = .idle
        lastEventTime = 0
        activeDragButton = nil
        finishTrackingInfo()

        activationGeneration &+= 1
        let generation = activationGeneration
        pendingActivation = PendingActivation(
            generation: generation,
            state: state,
            requestLocation: location,
            location: location,
            dragButton: dragButton,
            waitForDrag: waitForDrag,
            prepared: nil
        )
        let eventTapThread = eventTapThread

        dependencies.enqueueActivation { [weak self] in
            guard let self else { return }
            let prepared = self.prepareTracking(at: location)
            let complete: () -> Void = { [weak self] in
                guard let self else { return }
                self.completeActivation(generation: generation, prepared: prepared)
            }
            if let eventTapThread {
                eventTapThread.perform(complete)
            } else {
                complete()
            }
        }
    }

    private func prepareTracking(at location: CGPoint) -> PreparedTracking? {
        guard let window = dependencies.windowAt(location),
              let origin = window.origin(),
              let size = window.size() else { return nil }
        return PreparedTracking(
            window: window,
            origin: origin,
            size: size,
            canSetOrigin: window.canSetOrigin(),
            canSetSize: window.canSetSize()
        )
    }

    private func completeActivation(generation: UInt64, prepared: PreparedTracking?) {
        guard var pending = pendingActivation,
              pending.generation == generation else { return }
        guard let prepared else {
            pendingActivation = nil
            return
        }
        pending.prepared = prepared
        pendingActivation = pending
        if !pending.waitForDrag {
            activatePending()
        }
    }

    private func activatePending() {
        guard let pending = pendingActivation,
              let prepared = pending.prepared else { return }
        pendingActivation = nil

        let corner = resizeFromNearestCorner
            ? Corner.corner(for: pending.location - prepared.origin, in: prepared.size)
            : .bottomRight
        switch pending.state {
        case .moving:
            guard prepared.canSetOrigin else { return }
        case .resizing:
            guard prepared.canSetSize,
                  corner == .bottomRight || prepared.canSetOrigin else { return }
        case .idle:
            return
        }

        guard activateTracking(
            prepared,
            at: pending.requestLocation,
            state: pending.state,
            corner: corner
        ) else { return }
        currentState = pending.state
        activeDragButton = pending.dragButton
        if pending.location != pending.requestLocation {
            switch pending.state {
            case .moving:
                _ = move(to: pending.location)
            case .resizing:
                _ = resize(delta: trackingDelta(at: pending.location))
            case .idle:
                break
            }
        }
    }
    private func activateTracking(
        _ prepared: PreparedTracking,
        at location: CGPoint,
        state: State,
        corner: Corner
    ) -> Bool {
        let startTime = dependencies.now()
        let initialRect = roundedTargetRect(origin: prepared.origin, size: prepared.size)
        let generation = withTrackingLock {
            trackingInfo.generation &+= 1
            let commitState = CommitGenerationState(
                generation: trackingInfo.generation,
                lastCommittedRect: initialRect
            )
            trackingInfo.window = prepared.window
            trackingInfo.origin = prepared.origin
            trackingInfo.size = prepared.size
            trackingInfo.corner = corner
            trackingInfo.state = state
            trackingInfo.location = location
            trackingInfo.initialOrigin = prepared.origin
            trackingInfo.initialLocation = location
            trackingInfo.targetRect = initialRect
            trackingInfo.lastCommittedRect = initialRect
            trackingInfo.commitsCancelled = false
            trackingInfo.commitState = commitState
            return trackingInfo.generation
        }
        lastEventTime = startTime

        guard let timer = dependencies.makeTimer({ [weak self] in
            self?.timerFired()
        }) else {
            resetTrackingState()
            return false
        }
        let timerIsCurrent = withTrackingLock {
            guard trackingInfo.generation == generation,
                  trackingInfo.commitState?.generation == generation,
                  !trackingInfo.commitsCancelled else { return false }
            trackingTimer = timer
            return true
        }
        guard timerIsCurrent else {
            timer.cancel()
            return false
        }
        if focusWindowOnManipulation {
            dependencies.enqueueCommit {
                prepared.window.focus()
            }
        }
        return true
    }

    private func cancelPendingActivation() {
        pendingActivation = nil
    }

    private func trackingDelta(at location: CGPoint) -> Delta {
        withTrackingLock {
            let delta = location - trackingInfo.location
            trackingInfo.location = location
            return Delta(dx: delta.x, dy: delta.y)
        }
    }

    private func roundedTargetRect(origin: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: origin.x.rounded(),
            y: origin.y.rounded(),
            width: size.width.rounded(),
            height: size.height.rounded()
        )
    }

    private func move(to location: CGPoint) -> Bool {
        let hasWindow = withTrackingLock { trackingInfo.window != nil }
        guard hasWindow else {
            log(.debug, "No window!")
            resetTrackingState()
            return false
        }

        withTrackingLock {
            trackingInfo.location = location
            let displacement = location - trackingInfo.initialLocation
            trackingInfo.origin = constrainedOrigin(
                proposed: trackingInfo.initialOrigin + Delta(dx: displacement.x, dy: displacement.y),
                windowSize: trackingInfo.size,
                displays: currentDisplays
            )
            trackingInfo.targetRect = roundedTargetRect(
                origin: trackingInfo.origin,
                size: trackingInfo.size
            )
        }
        return true
    }

    private func resize(delta: Delta) -> Bool {
        let targetIsValid = withTrackingLock {
            guard trackingInfo.window != nil else { return false }

            switch trackingInfo.corner {
            case .topLeft:
                trackingInfo.origin += delta
                trackingInfo.size -= delta
            case .topRight:
                trackingInfo.origin += Delta(dx: 0, dy: delta.dy)
                trackingInfo.size += Delta(dx: delta.dx, dy: -delta.dy)
            case .bottomRight:
                trackingInfo.size += delta
            case .bottomLeft:
                trackingInfo.origin += Delta(dx: delta.dx, dy: 0)
                trackingInfo.size += Delta(dx: -delta.dx, dy: delta.dy)
            }

            guard trackingInfo.origin.x.isFinite, trackingInfo.origin.y.isFinite,
                  trackingInfo.size.width.isFinite, trackingInfo.size.height.isFinite else {
                return false
            }

            let fixedRightEdge = trackingInfo.origin.x + trackingInfo.size.width
            let fixedBottomEdge = trackingInfo.origin.y + trackingInfo.size.height
            if trackingInfo.size.width < 1 {
                trackingInfo.size.width = 1
                if trackingInfo.corner == .topLeft || trackingInfo.corner == .bottomLeft {
                    trackingInfo.origin.x = fixedRightEdge - trackingInfo.size.width
                }
            }
            if trackingInfo.size.height < 1 {
                trackingInfo.size.height = 1
                if trackingInfo.corner == .topLeft || trackingInfo.corner == .topRight {
                    trackingInfo.origin.y = fixedBottomEdge - trackingInfo.size.height
                }
            }

            trackingInfo.targetRect = roundedTargetRect(
                origin: trackingInfo.origin,
                size: trackingInfo.size
            )
            return true
        }

        guard targetIsValid else {
            resetTrackingState()
            return false
        }
        return true
    }

    private func timerFired() {
        let snapshot = withTrackingLock {
            commitSnapshotIfNeeded()
        }
        guard let snapshot else { return }
        enqueueCommit(snapshot, unconditional: false)
    }

    private func finishTrackingInfo() {
        let ended = withTrackingLock { () -> (CommitSnapshot?, TrackingTimer?) in
            trackingInfo.commitsCancelled = true
            if trackingInfo.commitState?.commitClaimed == false {
                trackingInfo.commitState?.cancelled = true
            }
            let snapshot = trackingInfo.window.flatMap { window in
                trackingInfo.commitState.map {
                    CommitSnapshot(
                        window: window,
                        rect: trackingInfo.targetRect,
                        corner: trackingInfo.corner,
                        state: trackingInfo.state,
                        commitState: $0
                    )
                }
            }
            return (snapshot, trackingTimer)
        }

        if let snapshot = ended.0 {
            enqueueCommit(snapshot, unconditional: true)
        }
        ended.1?.cancel()

        withTrackingLock {
            trackingTimer = nil
            trackingInfo.reset()
        }
    }

    private func commitSnapshotIfNeeded() -> CommitSnapshot? {
        guard !trackingInfo.commitsCancelled,
              let window = trackingInfo.window,
              let commitState = trackingInfo.commitState,
              trackingInfo.targetRect != commitState.lastCommittedRect else {
            return nil
        }
        return CommitSnapshot(
            window: window,
            rect: trackingInfo.targetRect,
            corner: trackingInfo.corner,
            state: trackingInfo.state,
            commitState: commitState
        )
    }

    private func enqueueCommit(_ snapshot: CommitSnapshot, unconditional: Bool) {
        dependencies.enqueueCommit {
            self.commit(snapshot, unconditional: unconditional)
        }
    }

    private func commit(_ snapshot: CommitSnapshot, unconditional: Bool) {
        dependencies.commitGate()
        let lastCommittedRect = withTrackingLock { () -> CGRect? in
            guard !snapshot.commitState.failed else { return nil }
            if !unconditional {
                guard !snapshot.commitState.cancelled,
                      trackingInfo.commitState === snapshot.commitState,
                      trackingInfo.targetRect == snapshot.rect,
                      snapshot.rect != snapshot.commitState.lastCommittedRect else {
                    return nil
                }
            }
            guard snapshot.rect != snapshot.commitState.lastCommittedRect else {
                return nil
            }
            // Linearization point: after this claim the commit has started.
            // Reset invalidates only unclaimed work, so an in-flight write is
            // always followed by the ended generation's queued final commit.
            snapshot.commitState.commitClaimed = true
            return snapshot.commitState.lastCommittedRect
        }
        guard let lastCommittedRect else { return }
        dependencies.commitApplyGate()

        guard apply(snapshot, lastCommittedRect: lastCommittedRect) else {
            handleCommitFailure(for: snapshot.commitState)
            return
        }

        withTrackingLock {
            snapshot.commitState.lastCommittedRect = snapshot.rect
            snapshot.commitState.commitClaimed = false
            guard trackingInfo.commitState === snapshot.commitState else { return }
            trackingInfo.lastCommittedRect = snapshot.rect
        }
    }

    private func apply(
        _ snapshot: CommitSnapshot,
        lastCommittedRect: CGRect
    ) -> Bool {
        let sizeChanged = snapshot.rect.size != lastCommittedRect.size
        let originChanged = snapshot.rect.origin != lastCommittedRect.origin

        if sizeChanged && !snapshot.window.setSize(snapshot.rect.size) {
            return false
        }

        let shouldWriteOrigin = (snapshot.state == .resizing
            && snapshot.corner != .bottomRight
            && (originChanged || sizeChanged))
            || (!sizeChanged && originChanged)
        if shouldWriteOrigin && !snapshot.window.setOrigin(snapshot.rect.origin) {
            return false
        }
        return true
    }

    private func handleCommitFailure(for commitState: CommitGenerationState) {
        let aborted = withTrackingLock { () -> (Bool, TrackingTimer?) in
            commitState.commitClaimed = false
            commitState.failed = true
            guard trackingInfo.commitState === commitState else {
                return (false, nil)
            }
            commitState.cancelled = true
            trackingInfo.commitsCancelled = true
            let timer = trackingTimer
            trackingTimer = nil
            trackingInfo.reset()
            return (true, timer)
        }
        aborted.1?.cancel()

        guard aborted.0 else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let eventTapThread = self.eventTapThread {
                eventTapThread.perform { [weak self] in
                    self?.resetEventStateAfterCommitFailure()
                }
            } else {
                self.resetEventStateAfterCommitFailure()
            }
        }
    }

    private func resetEventStateAfterCommitFailure() {
        currentState = .idle
        lastEventTime = 0
        activeDragButton = nil
    }

    private func shutdown() {
        guard let eventTapThread else {
            trackingTimer?.cancel()
            return
        }
        eventTapThread.performAndWait { [weak self] in
            self?.resetTrackingState()
        }
        eventTapThread.stop()
        self.eventTapThread = nil
        eventTap = nil
    }

    private func withTrackingLock<T>(_ body: () -> T) -> T {
        trackingLock.lock()
        defer { trackingLock.unlock() }
        return body()
    }

}


extension Tracker {
    enum Error: Swift.Error {
        case tapCreateFailed
    }
}


private func enableTap(userInfo: UnsafeMutableRawPointer) throws -> EventTapInstallation {
    // https://stackoverflow.com/a/31898592/1444152

    let mouseMoved = 1 << CGEventType.mouseMoved.rawValue
    let flagsChanged = 1 << CGEventType.flagsChanged.rawValue
    let leftDragged = 1 << CGEventType.leftMouseDragged.rawValue
    let rightDragged = 1 << CGEventType.rightMouseDragged.rawValue
    let otherDragged = 1 << CGEventType.otherMouseDragged.rawValue
    let leftDown = 1 << CGEventType.leftMouseDown.rawValue
    let leftUp = 1 << CGEventType.leftMouseUp.rawValue
    let rightDown = 1 << CGEventType.rightMouseDown.rawValue
    let rightUp = 1 << CGEventType.rightMouseUp.rawValue
    let otherDown = 1 << CGEventType.otherMouseDown.rawValue
    let otherUp = 1 << CGEventType.otherMouseUp.rawValue
    let eventMask = mouseMoved | flagsChanged | leftDragged | rightDragged | otherDragged |
                    leftDown | leftUp | rightDown | rightUp | otherDown | otherUp
    guard let eventTap = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(eventMask),
        callback: myCGEventCallback,
        userInfo: userInfo
    ) else {
        throw Tracker.Error.tapCreateFailed
    }

    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    return EventTapInstallation(eventTap: eventTap, runLoopSource: runLoopSource)
}


private func disableTap(_ installation: EventTapInstallation) {
    log(.debug, "Disabling event tap")
    CGEvent.tapEnable(tap: installation.eventTap, enable: false)
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), installation.runLoopSource, .commonModes)
}


private func myCGEventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    assert(!Thread.isMainThread, "The event-tap callback must run on its dedicated thread")
    guard let refcon else {
        log(.error, "Event tap callback has no Tracker")
        return Unmanaged.passUnretained(event)
    }
    let tracker = Unmanaged<Tracker>.fromOpaque(refcon).takeUnretainedValue()
    let absorbEvent = tracker.handleEvent(event, type: type, proxy: proxy)

    return absorbEvent ? nil : Unmanaged.passUnretained(event)
}
