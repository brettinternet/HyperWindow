//
//  TrackingInfo.swift
//  Hummingbird
//
//  Created by Sven A. Schmidt on 03/05/2019.
//  Copyright © 2019 finestructure. All rights reserved.
//

import Foundation
import Cocoa

/// The small window surface Tracker needs while an operation is active.
/// Production windows are backed by AXUIElement; tests provide an in-memory
/// implementation without creating an event tap or querying Accessibility.
struct TrackingWindow {
    let origin: () -> CGPoint?
    let size: () -> CGSize?
    let canSetOrigin: () -> Bool
    let canSetSize: () -> Bool
    let focus: () -> Void
    let setOrigin: (CGPoint) -> Bool
    let setSize: (CGSize) -> Bool
}

final class CommitGenerationState {
    let generation: UInt64
    var lastCommittedRect: CGRect
    var cancelled = false
    var commitClaimed = false
    var failed = false

    init(generation: UInt64, lastCommittedRect: CGRect) {
        self.generation = generation
        self.lastCommittedRect = lastCommittedRect
    }
}

class TrackingInfo {
    var window: TrackingWindow? = nil
    var origin: CGPoint = .zero
    var size: CGSize = .zero
    var corner: Corner = .bottomRight
    var state: State = .idle
    var location: CGPoint = .zero
    var initialOrigin: CGPoint = .zero
    var initialLocation: CGPoint = .zero
    var targetRect: CGRect = .zero
    var lastCommittedRect: CGRect = .zero
    var generation: UInt64 = 0
    var commitsCancelled = true
    var commitState: CommitGenerationState?

    func reset() {
        window = nil
        origin = .zero
        size = .zero
        corner = .bottomRight
        state = .idle
        location = .zero
        initialOrigin = .zero
        initialLocation = .zero
        targetRect = .zero
        lastCommittedRect = .zero
        commitsCancelled = true
        commitState = nil
    }
}
