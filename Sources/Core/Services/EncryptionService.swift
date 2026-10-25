import CryptoKit
import Foundation

/// AES-256-GCM encryption for token values.
/// Master key stored in Secure Enclave-backed Keychain, never leaves the device.
enum EncryptionService {
    private static let keyTag = "org.wahsun.tokenvault.masterkey".data(using: .utf8)!

    /// Test hook only: forces a specific 32-byte master key.
    static var keyOverride: Data?

    // MARK: - Master Key

    /// Get or create the 256-bit master key from Keychain.
    static func masterKey() throws -> SymmetricKey {
        // Test hook: the two-device sync self-test plays both sides in one process, which is only
        // meaningful when each side has its own key.
        if let data = keyOverride, data.count == 32 { return SymmetricKey(data: data) }
        if let existing = try? KeychainService.read(tag: keyTag) {
            return SymmetricKey(data: existing)
        }
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        try KeychainService.write(tag: keyTag, data: raw)
        return key
    }

    // MARK: - Encrypt / Decrypt

    /// Encrypt plaintext → base64-encoded ciphertext (nonce + ciphertext + tag).
    static func encrypt(_ plaintext: String) throws -> String {
        let key = try masterKey()
        let data = Data(plaintext.utf8)
        let sealed = try AES.GCM.seal(data, using: key)
        return (sealed.combined!).base64EncodedString()
    }

    /// Decrypt base64-encoded ciphertext → plaintext, or return original if not encrypted (migration).
    static func decrypt(_ ciphertext: String) throws -> String {
        guard let combined = Data(base64Encoded: ciphertext) else {
            return ciphertext // Legacy plaintext, not yet encrypted
        }
        let key = try masterKey()
        let sealed = try AES.GCM.SealedBox(combined: combined)
        let data = try AES.GCM.open(sealed, using: key)
        return String(data: data, encoding: .utf8) ?? ciphertext
    }
}
