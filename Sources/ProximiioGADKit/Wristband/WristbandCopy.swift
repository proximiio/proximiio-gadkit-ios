//
//  WristbandCopy.swift
//  ProximiioGADKit
//
//  Visitor-facing text for the wristband session: one message per bind error and one
//  notice per end reason. Ported from proximiio-blueiot-minimal-ios `WristbandCopy`.
//  Pure functions, covered by tests.
//
//  The text is keyed on the SDK's error cases and end reasons, never on the relay-api's
//  English messages, which may change.
//
import Foundation
import Proximiio
#if canImport(ProximiioBlueiot)
import ProximiioBlueiot
#endif

enum WristbandCopy {

    /// The message for a failed bind or end.
    static func message(for error: Error) -> String {
        guard let error = error as? BlueiotBindingError else {
            return error.localizedDescription
        }
        switch error {
        case .tagAlreadyBound:
            return String(localized: "This wristband is already in use. Please ask the staff.", bundle: .localized)
        case .notInAuthorizedZone(let cause, _, _):
            return message(for: cause)
        case .tagNotAvailable:
            return String(localized: "This wristband is not active. Please ask the staff.", bundle: .localized)
        case .tagNotAtReception:
            return String(localized: "Connect this wristband at the reception desk.", bundle: .localized)
        case .tagNotIssued:
            return String(localized: "This wristband has not been issued yet. Please ask the staff.", bundle: .localized)
        case .invalidTagID:
            return String(localized: "This is not a wristband code. Check the code printed on the wristband.", bundle: .localized)
        case .rateLimited(let retryAfter, _):
            guard let retryAfter, retryAfter > 0 else {
                return String(localized: "Too many attempts. Try again in a moment.", bundle: .localized)
            }
            let seconds = Int(retryAfter.rounded(.up))
            return String(localized: "Too many attempts. Try again in \(seconds) seconds.", bundle: .localized)
        // A refused swap to a new wristband outside reception. The current session is kept.
        case .swapBandsApart:
            return String(localized: "Hold your current wristband next to the new one and scan again.", bundle: .localized)
        case .swapAtReception:
            return String(localized: "Your wristband isn't reachable. Please swap it at the reception desk.", bundle: .localized)
        case .signingUnavailable:
            return String(localized: "The museum’s server is busy. Try again in a moment.", bundle: .localized)
        case .network:
            return String(localized: "The museum’s server cannot be reached. Check your connection and try again.", bundle: .localized)
        case .server, .invalidResponse:
            return String(localized: "The museum’s server failed. Try again in a moment.", bundle: .localized)
        case .sessionLost, .bindingClosed:
            return String(localized: "The wristband session has ended. Connect the wristband again.", bundle: .localized)
        // Configuration faults. A visitor never sees them in a configured build, so they
        // are not localized.
        case .appTokenRejected:
            return "The relay-api refused the app token. Check GAD_RELAY_API_APP_TOKEN."
        case .notARelayAPI:
            return "GAD_RELAY_API_BASE_URL is not a relay-api address."
        case .invalidRequest, .forbidden, .unexpected:
            return error.localizedDescription
        @unknown default:
            return error.localizedDescription
        }
    }

    /// The message for a take-over refused with `not_in_authorized_zone`, per what the
    /// phone sent.
    static func message(for cause: BlueiotLocationCause) -> String {
        switch cause {
        case .permissionMissing:
            return String(localized: "To take over this wristband, allow location for this app in Settings, or ask at the reception desk.", bundle: .localized)
        case .approximateLocation:
            return String(localized: "To take over this wristband, turn on Precise Location for this app in Settings, or ask at the reception desk.", bundle: .localized)
        case .noFreshFix:
            return String(localized: "Your location could not be determined in time. Try again, or ask at the reception desk.", bundle: .localized)
        case .simulatedLocation:
            return String(localized: "This phone reports a simulated location. Turn it off, or ask at the reception desk.", bundle: .localized)
        case .rejectedByRelay:
            return String(localized: "To take over this wristband, be inside the museum with location enabled, or ask at the reception desk.", bundle: .localized)
        @unknown default:
            return String(localized: "To take over this wristband, be inside the museum with location enabled, or ask at the reception desk.", bundle: .localized)
        }
    }

    /// The notice shown on the Hub after a session ended.
    static func notice(for reason: BlueiotBindingEndReason) -> String {
        switch reason {
        case .superseded:
            return String(localized: "Your wristband was scanned by another phone. Connect it again to follow it on this phone.", bundle: .localized)
        case .userEnded, .unknown:
            return String(localized: "Your visit has ended.", bundle: .localized)
        case .returned:
            return String(localized: "The wristband was returned. Thank you for your visit.", bundle: .localized)
        case .timeout:
            return String(localized: "The wristband stopped reporting. Please ask the staff.", bundle: .localized)
        case .leftVenue:
            return String(localized: "The wristband left the museum.", bundle: .localized)
        case .staffRevoked:
            return String(localized: "The staff released this wristband.", bundle: .localized)
        case .expired:
            return String(localized: "Your visit time is over.", bundle: .localized)
        case .replaced:
            return String(localized: "This wristband session was replaced by a newer one.", bundle: .localized)
        case .sessionLost:
            return String(localized: "The connection to your wristband was lost. Connect it again.", bundle: .localized)
        @unknown default:
            return String(localized: "Your visit has ended.", bundle: .localized)
        }
    }

    /// The state for the debug log. Holds no tag id.
    static func logLine(for state: BlueiotBindingState) -> String {
        switch state {
        case .unbound: return "unbound"
        case .binding: return "binding"
        case .active(_, let link, let signal):
            switch signal {
            case .lost: return "active, \(link.rawValue), signal lost"
            case .privacyZone: return "active, \(link.rawValue), privacy zone"
            default: return "active, \(link.rawValue)"
            }
        case .ended(let reason): return "ended, \(reason.rawValue)"
        @unknown default: return "unknown"
        }
    }
}
