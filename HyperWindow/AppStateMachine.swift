import Cocoa


protocol DidTransitionDelegate: AnyObject {
    func didTransition(from: AppStateMachine.State, to: AppStateMachine.State)
}


typealias AppStateMachineDelegate = (
    DidTransitionDelegate
)


class AppStateMachine {
    var stateMachine: StateMachine<AppStateMachine>!
    weak var delegate: AppStateMachineDelegate?

    /// Login-item launches must be silent. The app delegate owns this policy so
    /// normal user-initiated activation still follows the existing permission flow.
    var suppressActivationAlerts = false

    var state: State {
        get {
            return stateMachine.state
        }
        set {
            stateMachine.state = newValue
        }
    }

    init(initialState: State = .launching) {
        stateMachine = StateMachine<AppStateMachine>(initialState: initialState, delegate: self)
    }
}


extension AppStateMachine {
    func toggleEnabled() {
        switch state {
            case .activated:
                deactivate()
            case .deactivated:
                checkState()
            default:
                break
        }
    }
}


// MARK:- StateMachineDelegate

extension AppStateMachine: StateMachineDelegate {
    enum State: TransitionDelegate {
        case launching
        case validatingState
        case activating
        case activated
        case deactivated

        func shouldTransition(from: State, to: State) -> Decision {
            log(.debug, "Transition: \(from) -> \(to)")

            switch (from, to) {
                case (.launching, .validatingState):
                    return .continue
                case (.activated, .activating):
                    return .continue
                case (.validatingState, .activating):
                    return .continue
                case (.validatingState, .deactivated):
                    // validating error
                    return .continue
                case (.activating, .activated), (.deactivated, .activated):
                    return .continue
                case (.activating, .deactivated), (.activated, .deactivated):
                    return .continue
                case (.deactivated, .activating):
                    return .continue
                case (.deactivated, .deactivated):
                    // activation error (lack of permissions)
                    return .continue
                default:
                    assertionFailure("💣 Unhandled state transition: \(from) -> \(to)")
                    return .abort
            }

        }
    }

    func didTransition(from: State, to: State) {
        delegate?.didTransition(from: from, to: to)

        switch (from, to) {
            case (.launching, .validatingState):
                checkState()
            case (.validatingState, .activating), (.deactivated, .activating):
                activate(showAlert: !suppressActivationAlerts)
            default:
                break
        }
    }
}


// MARK:- State transition helpers


extension AppStateMachine {
    func checkState() {
        stateMachine.state = .activating
    }

    func activate(showAlert: Bool) {
        guard isTrusted(prompt: false) else {
            if showAlert {
                showAccessibilityAlert()
            }
            stateMachine.state = .deactivated
            return
        }
        
        Tracker.enable()
        if Tracker.isActive {
            stateMachine.state = .activated
        } else {
            stateMachine.state = .deactivated
        }
    }

    func deactivate() {
        Tracker.disable()
        stateMachine.state = .deactivated
    }

}
