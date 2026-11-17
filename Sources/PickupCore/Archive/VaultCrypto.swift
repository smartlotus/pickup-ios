import CryptoKit
import Foundation

public enum VaultCryptoError: Error, Sendable, Equatable, LocalizedError {
    case emptyPassphrase
    case invalidVaultFormat
    case authenticationFailed

    public var errorDescription: String? {
        switch self {
        case .emptyPassphrase:
            return "Passphrase cannot be empty."
        case .invalidVaultFormat:
            return "Unrecognized or corrupted encrypted Pickup vault file."
        case .authenticationFailed:
            return "Incorrect passphrase or tampered backup file."
        }
    }
}

public struct VaultEnvelope: Codable, Sendable, Equatable {
    public let format: String
    public let version: Int
    public let kdf: String
    public let iterations: Int
    public let saltBase64: String
    public let nonceBase64: String
    public let ciphertextBase64: String
    public let tagBase64: String
    public let createdAt: String

    public static let expectedFormat = "pickup-ios-vault"
}

public enum VaultCrypto {
    public static let defaultIterations = 80_000

    public static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        for idx in 0..<count {
            bytes[idx] = UInt8.random(in: 0...255)
        }
        return Data(bytes)
    }

    public static func deriveKey(passphrase: String, salt: Data, iterations: Int = defaultIterations) throws -> SymmetricKey {
        let clean = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            throw VaultCryptoError.emptyPassphrase
        }
        let passwordData = Data(clean.utf8)
        let derived = pbkdf2HMACSHA256(password: passwordData, salt: salt, iterations: iterations, keyByteCount: 32)
        return SymmetricKey(data: derived)
    }

    public static func hashPassphraseForLock(_ passphrase: String, salt: Data? = nil) throws -> (saltBase64: String, hashBase64: String) {
        let actualSalt = salt ?? randomBytes(count: 16)
        let key = try deriveKey(passphrase: passphrase, salt: actualSalt, iterations: 40_000)
        let keyData = key.withUnsafeBytes { Data($0) }
        return (actualSalt.base64EncodedString(), keyData.base64EncodedString())
    }

    public static func verifyPassphraseForLock(_ passphrase: String, saltBase64: String, hashBase64: String) -> Bool {
        guard let salt = Data(base64Encoded: saltBase64),
              let expected = Data(base64Encoded: hashBase64),
              let (_, candidate) = try? hashPassphraseForLock(passphrase, salt: salt),
              let candidateData = Data(base64Encoded: candidate) else {
            return false
        }
        return constantTimeEqual(expected, candidateData)
    }

    public static func seal(plaintext: Data, passphrase: String, iterations: Int = defaultIterations) throws -> Data {
        let salt = randomBytes(count: 16)
        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)

        let envelope = VaultEnvelope(
            format: VaultEnvelope.expectedFormat,
            version: 1,
            kdf: "pbkdf2-hmac-sha256",
            iterations: iterations,
            saltBase64: salt.base64EncodedString(),
            nonceBase64: Data(nonce).base64EncodedString(),
            ciphertextBase64: sealed.ciphertext.base64EncodedString(),
            tagBase64: sealed.tag.base64EncodedString(),
            createdAt: PortableDateCodec.format(Date())
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    public static func open(vaultData: Data, passphrase: String) throws -> Data {
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(VaultEnvelope.self, from: vaultData),
              envelope.format == VaultEnvelope.expectedFormat,
              envelope.version == 1,
              envelope.iterations >= 1_000 && envelope.iterations <= 2_000_000,
              let salt = Data(base64Encoded: envelope.saltBase64),
              let nonceData = Data(base64Encoded: envelope.nonceBase64),
              let ciphertext = Data(base64Encoded: envelope.ciphertextBase64),
              let tag = Data(base64Encoded: envelope.tagBase64),
              let nonce = try? AES.GCM.Nonce(data: nonceData) else {
            throw VaultCryptoError.invalidVaultFormat
        }
        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: envelope.iterations)
        do {
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw VaultCryptoError.authenticationFailed
        }
    }

    public static func looksLikeEncryptedVault(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return (json["format"] as? String) == VaultEnvelope.expectedFormat
    }

    // Pure Swift PBKDF2-HMAC-SHA256 using Apple CryptoKit
    private static func pbkdf2HMACSHA256(password: Data, salt: Data, iterations: Int, keyByteCount: Int) -> Data {
        let prfKey = SymmetricKey(data: password)
        let blockCount = (keyByteCount + 31) / 32
        var result = Data()
        result.reserveCapacity(keyByteCount)

        for blockIndex in 1...blockCount {
            var blockInput = salt
            var beIndex = UInt32(blockIndex).bigEndian
            withUnsafeBytes(of: &beIndex) { blockInput.append(contentsOf: $0) }

            var u = Data(HMAC<SHA256>.authenticationCode(for: blockInput, using: prfKey))
            var t = u

            if iterations > 1 {
                for _ in 2...iterations {
                    u = Data(HMAC<SHA256>.authenticationCode(for: u, using: prfKey))
                    for i in 0..<32 {
                        t[i] ^= u[i]
                    }
                }
            }
            result.append(t)
        }
        return result.prefix(keyByteCount)
    }

    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count {
            diff |= a[i] ^ b[i]
        }
        return diff == 0
    }
}
