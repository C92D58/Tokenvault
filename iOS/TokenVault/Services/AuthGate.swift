import LocalAuthentication

/// Face ID / Touch ID / passcode gate.
///
/// `deviceOwnerAuthentication` (not `…Biometrics`) on purpose: a failed Face ID scan must be
/// able to fall back to the device passcode, otherwise a masked face locks you out of your own
/// vault until you take the mask off.
final class AuthGate: ObservableObject {
    @Published private(set) var lastFailure: String?

    private let context = LAContext()

    private var canEvaluate: Bool {
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// "Face ID" / "Touch ID" / "裝置密碼".
    var label: String {
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return L("裝置密碼")
        }
    }

    var symbol: String {
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock.open"
        }
    }

    var isAvailable: Bool { canEvaluate }

    func authenticate(reason: String) async -> Bool {
        guard canEvaluate else {
            // Nothing enrolled (a fresh simulator, or a device with no passcode). Refusing here
            // would make the app unusable, so the vault opens; the lock still applies as soon as
            // the user turns the passcode on.
            return true
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                      localizedReason: reason)
            await MainActor.run { self.lastFailure = ok ? nil : L("驗證失敗") }
            return ok
        } catch {
            await MainActor.run { self.lastFailure = error.localizedDescription }
            return false
        }
    }
}
