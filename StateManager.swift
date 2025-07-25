// Copyright 2018 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import FirebaseAnalytics
import Foundation
import Lottie

// swiftlint:disable:next legacy_objc_type
extension NSNotification.Name {
    // swiftlint:disable:next legacy_objc_type
    static var STATE_CHANGED = NSNotification.Name("stateChanged")
}

/// States for Pairing Interface
enum State: String {
    case NO_STATE
    case LOOKING
    case DISCOVERY_TIMEOUT
    case HOST_CONNECTED
    case PARTNER_CONNECTED
    case HOST_SET_ANCHOR
    case PARTNER_SET_ANCHOR
    case HOST_READY_AND_WAITING
    case PARTNER_READY_AND_WAITING
    case HOST_ANCHOR_ERROR
    case HOST_CONNECTING
    case PARTNER_CONNECTING
    case GLOBAL_CONNECTING
    case HOST_RESOLVE_ERROR
    case PARTNER_RESOLVE_ERROR
    case SYNCED
    case FINISHED
    case GLOBAL_NO_ANCHOR
    case GLOBAL_RESOLVE_ERROR
    case CONNECTION_LOST
    case OFFLINE
    case UNKNOWN_ERROR
}

protocol StateManagerDelegate: AnyObject {
    func stateChangeCompleted(_ state: State)
    func attemptPartnerDiscovery()
    func anchorDrawingTryAgain()
    func pairingFinished()
    func pairCancelled()
    func onReadyToSetAnchor()
    func retryResolvingAnchor()
}

// TODO: Ultimately need to refactor to StateViewController with singleton StateManager for storing and publishing state changes
// In the meantime, AppDelegate stores changes, and static StateManager method publishes
// swiftlint:disable:next type_body_length
class StateManager: UIViewController {
    // MARK: Properties

    /// Lottie animation view
    var animationView: LottieAnimationView?

    /// Primary message for pairing
    @IBOutlet var centerMessageLabel: UILabel! // swiftlint:disable:this private_outlet type_contents_order

    /// Modal background, also container for rest of interface
    @IBOutlet var fullBackground: UIView! // swiftlint:disable:this private_outlet type_contents_order

    /// Constant for time delay between automatic sequential states
    let SEQUENTIAL_STATE_DELAY: Double = 2.0

    /// Progress bar timer max value
    let COUNTDOWN_DURATION: Double = 30.0

    /// Progress bar maximum progress
    let COUNTDOWN_MAX_PROGRESS: Float = 0.8

    /// Progress bar timer
    var progressTimer: Timer?

    /// Current state
    var state: State?

    weak var delegate: StateManagerDelegate?

    /// When using an image instead of an animation
    @IBOutlet private var imageView: UIImageView!

    /// Holds Lottie view, managing constraints
    @IBOutlet private var animationContainer: UIView!
    @IBOutlet private var animationWidthConstraint: NSLayoutConstraint!
    @IBOutlet private var animationHeightConstraint: NSLayoutConstraint!

    /// Smaller additional line for detail
    @IBOutlet private var secondaryMessageLabel: UILabel!

    /// Try again button for failed pairing
    @IBOutlet private var tryAgainButton: UIButton!

    /// Progress Bar
    @IBOutlet private var progressView: UIProgressView!

    /// Ready button
    @IBOutlet private var readyButton: UIButton!

    /// Cancel button
    @IBOutlet private var closeButton: UIButton!

    // MARK: Overridden Functions

    // swiftlint:disable:next type_contents_order
    override func viewDidLoad() {
        super.viewDidLoad()

        centerMessageLabel.isHidden = true
        secondaryMessageLabel.isHidden = true
        readyButton?.isHidden = true
        tryAgainButton?.isHidden = true

        NotificationCenter.default.addObserver(self, selector: #selector(stateNotification), name: .STATE_CHANGED, object: nil)

        configureAccessibility()
    }

    // MARK: Static Functions

    /// Update state manager
    static func updateState(_ state: State) {
        print("updateState: \(state)")
        NotificationCenter.default.post(name: .STATE_CHANGED, object: self, userInfo: ["state": state])
    }

    /// determines when to allow tracking state to override pairing state
    static func shouldShowTracking(for pairState: State) -> Bool {
        pairState == .SYNCED
    }

    // MARK: Functions

    func configureAccessibility() {
        closeButton.accessibilityLabel = NSLocalizedString("menu_close", comment: "Close")
    }

    @objc
    func stateNotification(notification: Notification) {
        if let userInfo = notification.userInfo, let state = userInfo["state"] as? State {
            DispatchQueue.main.async {
                self.setState(state)
            }
        }
    }

    /// Some states automatically transition to another state
    func handleSequentialStates() {
        guard let state = self.state else {
            return
        }

        var nextState: State?

        switch state {
        case .HOST_CONNECTED:
            nextState = .HOST_SET_ANCHOR

        case .PARTNER_CONNECTED:
            nextState = .PARTNER_SET_ANCHOR

        case .SYNCED:
            nextState = .FINISHED

        default:
            break
        }

        if let newState = nextState {
            setState(newState)
        }
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func setState(_ newState: State) {
        print("StateManager: setState - Setting state to \(newState.rawValue)")
        if newState == .NO_STATE {
            self.state = nil
        } else {
            self.state = newState
        }
        // swiftlint:disable:next force_cast
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.pairingState = self.state

        animationView?.stop()
        animationView?.removeFromSuperview()
        animationView = nil
        progressView.progress = 0.0
        centerMessageLabel.text = ""
        imageView.image = nil
        secondaryMessageLabel.text = ""
        tryAgainButton.setTitle(NSLocalizedString("try_again", comment: "Try Again"), for: .normal)
        readyButton.setTitle(NSLocalizedString("ready", comment: "Ready"), for: .normal)

        var message: String?
        var secondMessage: String?
        var image: UIImage?
        var animationName: String?
        var showProgress = false
        var showTryAgain = false
        var showReadyButton = false
        var completeProgress = false
        var delayedStateTransition = false
        var accessibleMessage: String?

        switch newState {
        case .LOOKING:
            message = NSLocalizedString("pair_looking_for_partner", comment: "Looking for your drawing partner...")
//                secondMessage = NSLocalizedString("Ask them to tap the partner icon", comment: "Ask them to tap the partner icon")
            animationName = "looking_partner"
//                image = UIImage(named: "jal_looking_for_partner")

        case .DISCOVERY_TIMEOUT:
            message = NSLocalizedString("pair_discovery_timeout", comment: "Hmm… we didn\'t find anyone nearby.")
            image = UIImage(named: "jal_ui_error_icon_partner")
            showTryAgain = true

        case .HOST_CONNECTED: fallthrough

        case .PARTNER_CONNECTED:
            message = NSLocalizedString("pair_connected", comment: "Partner found!")
            animationName = "partner_found"
//                image = UIImage(named: "jal_partner_found")
            delayedStateTransition = true

        case .HOST_SET_ANCHOR: fallthrough

        case .PARTNER_SET_ANCHOR:
            message = NSLocalizedString("pair_look_at_same_thing", comment: "")
            accessibleMessage = NSLocalizedString("pair_look_at_same_thing_accessible", comment: "")
            image = UIImage(named: "jal_ui_illustrations_sync")
            showReadyButton = true

        case .HOST_READY_AND_WAITING: fallthrough

        case .PARTNER_READY_AND_WAITING:
            message = NSLocalizedString("pair_look_at_same_thing", comment: "")
            accessibleMessage = NSLocalizedString("pair_look_at_same_thing_accessible", comment: "")
            secondMessage = NSLocalizedString("Waiting for partner", comment: "Waiting for partner")
            image = UIImage(named: "jal_ui_illustrations_sync")

        case .HOST_ANCHOR_ERROR:
            message = NSLocalizedString(
                "pair_anchor_error",
                comment: "Something went wrong syncronizing with your partner. Try again, drawing in a new area."
            )
            showTryAgain = true

        case .HOST_CONNECTING: fallthrough

        case .PARTNER_CONNECTING:
            message = NSLocalizedString("pair_connect_phones", comment: "")
            animationName = "stay_put"
            showProgress = true
//                animation = true
//                looping = true

        case .GLOBAL_CONNECTING:
            message = NSLocalizedString("pair_global_connecting", comment: "Connecting to global room")

        case .HOST_RESOLVE_ERROR:
            message = NSLocalizedString("pair_anchor_error", comment: "Something went wrong during the sync.")
            secondMessage = NSLocalizedString("pair_anchor_error_line2", comment: "Try again in a more distinct spot.")
            image = UIImage(named: "jal_ui_error_icon_sync")
            showTryAgain = true

        case .PARTNER_RESOLVE_ERROR:
            message = NSLocalizedString("pair_anchor_error", comment: "Something went wrong during the sync.\n\nTry again in a more distinct spot.")
            image = UIImage(named: "jal_ui_error_icon_sync")
            showTryAgain = true
            delegate?.retryResolvingAnchor()

        case .GLOBAL_NO_ANCHOR:
            message = NSLocalizedString("pair_global_no_anchor", comment: "There is no anchor in the global room.")
            image = UIImage(named: "jal_ui_error_icon_sync")
            readyToSetAnchor()

        case .GLOBAL_RESOLVE_ERROR:
            message = NSLocalizedString("pair_global_localization_error", comment: "Couldn\'t find room. Are you in the right spot?")
            image = UIImage(named: "jal_ui_error_icon_sync")
            showTryAgain = true

        case .SYNCED:
            message = NSLocalizedString("pair_synced", comment: "Paired!")
            image = UIImage(named: "paired_check_icon")
            showProgress = true
            completeProgress = true
            delayedStateTransition = true

        case .FINISHED:
            delegate?.pairingFinished()
            return

        case .CONNECTION_LOST:
            image = UIImage(named: "jal_ui_error_icon_partner")
            message = NSLocalizedString("pair_lost_connection", comment: "Lost connection\nto partner")
            showTryAgain = true
            tryAgainButton.setTitle(NSLocalizedString("ok", comment: "OK"), for: .normal)

        case .OFFLINE:
            message = NSLocalizedString("pair_no_data_connection", comment: "Can\'t sync without internet connection")
            image = UIImage(named: "jal_ui_error_icon_partner")

        case .UNKNOWN_ERROR:
            message = NSLocalizedString("Unknown error", comment: "Something unexpected happened")
            secondMessage = NSLocalizedString("pair_unknown_error", comment: "We're not sure what happened...but it did")
            image = UIImage(named: "jal_ui_error_icon_partner")

        default:
            break
        }

        // Set image, animation, and text values
        if image != nil {
            imageView?.image = image
        } else {
            imageView?.image = nil
        }

        if let animation = animationName {
            configureAnimation(name: animation)
        }

        centerMessageLabel?.text = message
        centerMessageLabel?.accessibilityLabel = accessibleMessage
        secondaryMessageLabel?.text = (secondMessage != nil) ? secondMessage : ""

        // Set visibility states
        fullBackground.isHidden = false
        centerMessageLabel.isHidden = false
        progressView.isHidden = showProgress ? false : true
        secondaryMessageLabel.isHidden = (secondMessage == nil) ? true : false
        readyButton?.isHidden = showReadyButton ? false : true
        tryAgainButton?.isHidden = showTryAgain ? false : true
        delegate?.stateChangeCompleted(newState)

        if showProgress, progressTimer == nil {
            self.progressView.progress = 0
            progressTimer = Timer(timeInterval: 0.1, repeats: true, block: { timer in
                let elapsedTime = Date().timeIntervalSince(timer.fireDate)

                let progressValue = Float(min(self.progressView.progress + Float(timer.timeInterval / self.COUNTDOWN_DURATION), self.COUNTDOWN_MAX_PROGRESS))
                self.progressView.setProgress(progressValue, animated: true)

                if elapsedTime >= self.COUNTDOWN_DURATION {
                    self.progressTimer?.invalidate()
                    self.progressTimer = nil
                }
            })
            // swiftlint:disable:next force_unwrapping
            RunLoop.main.add(progressTimer!, forMode: RunLoop.Mode.default)
        }

        if completeProgress {
            progressView.progress = 1.0
            progressTimer?.invalidate()
            progressTimer = nil
        }

        if delayedStateTransition {
            DispatchQueue.main.asyncAfter(deadline: .now() + SEQUENTIAL_STATE_DELAY) {
                self.handleSequentialStates()
            }
        }

        UIAccessibility.post(notification: UIAccessibility.Notification.layoutChanged, argument: centerMessageLabel)
    }

    func configureAnimation(name: String) {
        var loopAnimation = LottieLoopMode.playOnce
        animationWidthConstraint.constant = 82
        animationHeightConstraint.constant = 97

        switch name {
        case "looking_partner":
            loopAnimation = .loop

        case "stay_put":
            animationWidthConstraint.constant = 197
            animationHeightConstraint.constant = 197

        default:
            break
        }

        animationView = LottieAnimationView(name: name)
        animationView?.frame = CGRect(origin: .zero, size: CGSize(width: animationWidthConstraint.constant, height: animationHeightConstraint.constant))
        animationView?.loopMode = loopAnimation
        animationView?.contentMode = .scaleAspectFit
        // swiftlint:disable:next force_unwrapping
        animationContainer.addSubview(animationView!)

        if name == "stay_put" {
            animationView?.play(completion: { completed in
                if completed {
                    self.loopFromFrame(250)
                }
            })
        } else {
            animationView?.play()
        }
    }

    func loopFromFrame(_ frameNumber: AnimationFrameTime) {
        self.animationView?.currentFrame = frameNumber
        self.animationView?.play(completion: { completed in
            if completed {
                self.loopFromFrame(frameNumber)
            }
        })
    }

    func hostAnchorDrawn() {
        readyButton?.isHidden = false
    }

    func readyToSetAnchor() {
        print("readyToSetAnchor: \(state)")
        if state == .HOST_SET_ANCHOR || state == .PARTNER_SET_ANCHOR || state == .GLOBAL_NO_ANCHOR {
            delegate?.onReadyToSetAnchor()
        }
    }

    // MARK: - Button Methods

    @IBAction private func anchorDoneTapped(_: UIButton) {
        guard let state = self.state else {
            return
        }

        readyToSetAnchor()
        readyButton?.isHidden = true
    }

    @IBAction private func closeTapped(_: UIButton) {
        if state == .SYNCED || state == .FINISHED {
            delegate?.stateChangeCompleted(.SYNCED)
            return
        }
        delegate?.pairCancelled()
        Analytics.logEvent(AnalyticsKey.val(.tapped_exit_pair_flow), parameters: nil)
    }

    @IBAction private func tryAgainTapped(_ sender: UIButton) {
        guard let state = self.state else {
            return
        }

        switch state {
        case .DISCOVERY_TIMEOUT:
            delegate?.attemptPartnerDiscovery()

        case .HOST_ANCHOR_ERROR: fallthrough

        case .HOST_RESOLVE_ERROR:
            Self.updateState(.HOST_SET_ANCHOR)

        case .PARTNER_RESOLVE_ERROR:
            Self.updateState(.PARTNER_SET_ANCHOR)

        case .GLOBAL_RESOLVE_ERROR:
            Self.updateState(.GLOBAL_CONNECTING)
            delegate?.retryResolvingAnchor()

        // try again button is used as an ok button on connection lost
        case .CONNECTION_LOST:
            closeTapped(sender)

        default:
            break
        }
    }
}
