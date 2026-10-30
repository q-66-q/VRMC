import Foundation

public struct MappingOutput: Equatable, Sendable {
    public var left: IntentInput
    public var right: IntentInput
    public var locomotionActive: Bool
    public var menuHint: MenuHint
    public var leftSignals: HandSignals
    public var rightSignals: HandSignals

    public enum MenuHint: UInt8, Sendable, Equatable {
        case none = 0
        case inventoryAvailable = 1
        case menuAvailable = 2
    }

    public init(
        left: IntentInput,
        right: IntentInput,
        locomotionActive: Bool = false,
        menuHint: MenuHint = .none,
        leftSignals: HandSignals,
        rightSignals: HandSignals
    ) {
        self.left = left
        self.right = right
        self.locomotionActive = locomotionActive
        self.menuHint = menuHint
        self.leftSignals = leftSignals
        self.rightSignals = rightSignals
    }
}

public final class ControllerMapper: @unchecked Sendable {
    private struct Pulses {
        var a: Timestamp?
        var b: Timestamp?
        var stickClick: Timestamp?
        var trackpadClick: Timestamp?
        var triggerClick: Timestamp?
        var gripClick: Timestamp?

        mutating func add(_ button: ControllerButtons, until: Timestamp, now: Timestamp) {
            let current = active(button, now: now)
            if current { return }
            switch button {
            case .a: a = until
            case .b: b = until
            case .stickClick: stickClick = until
            case .trackpadClick: trackpadClick = until
            case .triggerClick: triggerClick = until
            case .gripClick: gripClick = until
            default: break
            }
        }

        func active(_ button: ControllerButtons, now: Timestamp) -> Bool {
            let expiry: Timestamp?
            switch button {
            case .a: expiry = a
            case .b: expiry = b
            case .stickClick: expiry = stickClick
            case .trackpadClick: expiry = trackpadClick
            case .triggerClick: expiry = triggerClick
            case .gripClick: expiry = gripClick
            default: expiry = nil
            }
            guard let expiry else { return false }
            return now < expiry
        }
    }

    private struct MenuState {
        var active = false
        var start: Timestamp?
        var longFired = false
        var hint: MappingOutput.MenuHint = .none
    }

    public let profile: HandMappingProfile
    private let recognizer: GestureRecognizer
    private var pulsesLeft = Pulses()
    private var pulsesRight = Pulses()
    private var locomotionActive = false
    private var locomotionAnchor: Vec3 = .zero
    private var palmUpSince: Timestamp?
    private var menu = MenuState()
    private var sampleCounter: UInt32 = 0

    public init(profile: HandMappingProfile = .v1) {
        self.profile = profile
        self.recognizer = GestureRecognizer(profile: profile)
    }

    public func reset() {
        recognizer.reset()
        pulsesLeft = Pulses()
        pulsesRight = Pulses()
        locomotionActive = false
        locomotionAnchor = .zero
        palmUpSince = nil
        menu = MenuState()
        sampleCounter = 0
    }

    public func update(
        leftSnapshot: HandSnapshot?,
        rightSnapshot: HandSnapshot?,
        headPose: Pose,
        now: Timestamp = .now()
    ) -> MappingOutput {
        sampleCounter &+= 1
        let signals = recognizer.update(
            leftSnapshot: leftSnapshot, rightSnapshot: rightSnapshot,
            headPosition: headPose.position, now: now
        )

        let locomotionHand = profile.locomotionChirality
        let locomotionSignals = locomotionHand == .left ? signals.left : signals.right
        let aimSignals = profile.aimChirality == .left ? signals.left : signals.right
        let aimRole = profile.controllerRole(for: profile.aimChirality)
        let menuHand: HandChirality = profile.leftHanded ? .right : .left
        let menuRole = profile.controllerRole(for: menuHand)
        let menuSignals = menuHand == .left ? signals.left : signals.right

        updateMenu(
            signals: menuSignals,
            role: menuRole,
            aimSignals: aimSignals,
            now: now
        )

        let leftPhysical = makeBaseIntent(chirality: .left, signals: signals.left, now: now)
        let rightPhysical = makeBaseIntent(chirality: .right, signals: signals.right, now: now)
        var leftIntent = leftPhysical.hand == .left ? leftPhysical : rightPhysical
        var rightIntent = leftPhysical.hand == .right ? leftPhysical : rightPhysical

        // Locomotion (palm-up joystick).
        updateLocomotion(
            signals: locomotionSignals,
            headPose: headPose,
            aimSignals: aimSignals,
            menuSignals: menuSignals,
            now: now
        )

        if locomotionActive, locomotionSignals.tracked {
            let (stick, turn) = locomotionValues(signals: locomotionSignals, headPose: headPose)
            leftIntent.stickX = stick.x
            leftIntent.stickY = stick.y
            rightIntent.stickX = turn
            if locomotionSignals.ringPinchEdge {
                addPulse(role: .left, button: .stickClick, now: now)
            }
        }

        // Sneak: hold the aim hand palm-down low.
        if aimSignals.tracked && aimSignals.palmDownLow && !locomotionActive {
            setButton(&leftIntent, &rightIntent, role: aimRole, button: .a, pressed: true)
        }

        // Menu/inventory pulses are emitted after the menu state machine.
        applyPulses(to: &leftIntent, role: .left, now: now)
        applyPulses(to: &rightIntent, role: .right, now: now)

        let hint = menu.hint
        let active = locomotionActive
        return MappingOutput(
            left: leftIntent, right: rightIntent,
            locomotionActive: active, menuHint: hint,
            leftSignals: signals.left, rightSignals: signals.right
        )
    }

    // MARK: - Intent construction

    private func makeBaseIntent(chirality: HandChirality, signals: HandSignals, now: Timestamp) -> IntentInput {
        let role = profile.controllerRole(for: chirality)
        guard signals.tracked else {
            return IntentInput(hand: role, quality: .invalid, sampleId: sampleCounter)
        }
        var buttons: ControllerButtons = []
        if signals.triggerPressed { buttons.insert(.triggerClick) }
        if signals.usePressed { buttons.insert(.trackpadClick) }
        if signals.gripPressed { buttons.insert(.gripClick) }
        if signals.triggerPressed { buttons.insert(.triggerTouch) }
        if signals.gripPressed { buttons.insert(.gripTouch) }
        if pulses(for: role).active(.a, now: now) { buttons.insert(.a) }
        if pulses(for: role).active(.b, now: now) { buttons.insert(.b) }
        if pulses(for: role).active(.stickClick, now: now) { buttons.insert(.stickClick) }
        return IntentInput(
            hand: role,
            quality: signals.degraded ? .degraded : .tracked,
            sampleId: sampleCounter,
            pose: signals.controllerPose,
            linearVelocity: signals.linearVelocity,
            angularVelocity: signals.angularVelocity,
            trigger: signals.trigger,
            grip: signals.grip,
            stickX: 0,
            stickY: 0,
            trackpadX: 0,
            trackpadY: 0,
            buttons: buttons
        )
    }

    private func pulses(for role: HandChirality) -> Pulses {
        role == .left ? pulsesLeft : pulsesRight
    }

    private func updateLocomotion(
        signals: HandSignals,
        headPose: Pose,
        aimSignals: HandSignals,
        menuSignals: HandSignals,
        now: Timestamp
    ) {
        guard signals.tracked, !signals.degraded else {
            locomotionActive = false
            return
        }
        let eligible = signals.palmUp && !signals.palmToFace && !menuSignals.palmToFace &&
            !aimSignals.triggerPressed && !menu.active && !signals.gripPressed
        if !eligible {
            if locomotionActive || palmUpSince != nil {
                locomotionActive = false
            }
            palmUpSince = nil
            return
        }
        if palmUpSince == nil {
            palmUpSince = now
        }
        if !locomotionActive, let since = palmUpSince,
           Double(now.distance(to: since)) / 1_000_000 >= profile.locomotionDwellMs {
            locomotionActive = true
            locomotionAnchor = signals.palmCenter
        }
    }

    private func locomotionValues(signals: HandSignals, headPose: Pose) -> (Vec2, Float) {
        let delta = signals.palmCenter - locomotionAnchor
        let headForward = headPose.orientation.rotate(Vec3(0, 0, -1))
        var forward = Vec3(headForward.x, 0, headForward.z).normalized(or: Vec3(0, 0, -1))
        let right = forward.cross(Vec3(0, 1, 0)).normalized(or: Vec3(1, 0, 0))
        if right.lengthSquared < 0.5 { forward = Vec3(0, 0, -1) }
        let forwardAmount = delta.dot(forward) / profile.locomotionRangeMeters
        let rightAmount = delta.dot(right) / profile.locomotionRangeMeters
        let x = applyDeadzone(clampSigned(rightAmount))
        let y = applyDeadzone(clampSigned(forwardAmount))
        let headYaw = headPose.orientation.yaw
        let turn = clampSigned(normalizedAngle(signals.handYaw - headYaw) / (profile.turnRangeDegrees * .pi / 180))
        return (Vec2(x, y), applyDeadzone(turn))
    }

    private func updateMenu(
        signals: HandSignals,
        role: HandChirality,
        aimSignals: HandSignals,
        now: Timestamp
    ) {
        let suppressed = aimSignals.triggerPressed || aimSignals.usePressed || aimSignals.gripPressed ||
            locomotionActive
        let canOpen = signals.tracked && signals.palmToFace && !suppressed
        if canOpen {
            if menu.start == nil {
                menu.start = now
                menu.longFired = false
            }
            if let start = menu.start {
                let duration = Double(now.distance(to: start)) / 1_000_000
                if duration >= profile.menuShortMs {
                    menu.hint = duration >= profile.menuLongMs ? .menuAvailable : .inventoryAvailable
                }
                if duration >= profile.menuLongMs && !menu.longFired {
                    menu.longFired = true
                    addPulse(role: role, button: .b, now: now)
                }
            }
            menu.active = true
        } else {
            if menu.active, let start = menu.start {
                let duration = Double(now.distance(to: start)) / 1_000_000
                if duration >= profile.menuShortMs && duration < profile.menuLongMs && !menu.longFired {
                    addPulse(role: role, button: .a, now: now)
                }
            }
            menu = MenuState()
        }
    }

    private func addPulse(role: HandChirality, button: ControllerButtons, now: Timestamp) {
        let until = now.adding(milliseconds: profile.buttonPulseMs)
        if role == .left {
            pulsesLeft.add(button, until: until, now: now)
        } else {
            pulsesRight.add(button, until: until, now: now)
        }
    }

    private func applyPulses(to intent: inout IntentInput, role: HandChirality, now: Timestamp) {
        let pulses = pulses(for: role)
        for button in [ControllerButtons.a, .b, .stickClick, .trackpadClick, .triggerClick, .gripClick] {
            if pulses.active(button, now: now) { intent.buttons.insert(button) }
        }
    }

    private func setButton(_ left: inout IntentInput, _ right: inout IntentInput, role: HandChirality, button: ControllerButtons, pressed: Bool) {
        if role == .left {
            if pressed { left.buttons.insert(button) } else { left.buttons.remove(button) }
        } else {
            if pressed { right.buttons.insert(button) } else { right.buttons.remove(button) }
        }
    }

    private func clampSigned(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, -1), 1)
    }

    private func applyDeadzone(_ value: Float) -> Float {
        let magnitude = abs(value)
        guard magnitude > profile.deadzone else { return 0 }
        return (value - (value > 0 ? profile.deadzone : -profile.deadzone)) / (1 - profile.deadzone)
    }

    private func normalizedAngle(_ angle: Float) -> Float {
        var value = angle
        while value > .pi { value -= 2 * .pi }
        while value < -.pi { value += 2 * .pi }
        return value
    }
}
