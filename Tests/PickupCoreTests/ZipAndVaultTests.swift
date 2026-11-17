import Foundation
import Testing
@testable import PickupCore

@Suite("ZIP Archive & Vault Crypto Tests")
struct ZipAndVaultTests {

    @Test("ZIP round-trip preserves Deflate text and Store media bytes")
    func zipRoundTrip() throws {
        let jsonBytes = Data(String(repeating: #"{"content":"把日子，拾起来。"}"#, count: 30).utf8)
        let smallBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let input: [String: Data] = [
            "backup.json": jsonBytes,
            "media/media_0000.png": smallBytes,
            "中文备注.txt": Data("本地日记不依赖云端".utf8),
        ]
        let archive = try ZipArchive.encode(files: input)
        #expect(ZipArchive.looksLikeZip(archive))

        let decoded = try ZipArchive.decode(archive)
        #expect(decoded.count == 3)
        #expect(decoded["backup.json"] == jsonBytes)
        #expect(decoded["media/media_0000.png"] == smallBytes)
        #expect(decoded["中文备注.txt"] == input["中文备注.txt"])
    }

    @Test("ZIP blocks unsafe path traversal entries")
    func zipPathTraversalRejected() throws {
        #expect(!ZipArchive.isSafeRelativePath("../etc/passwd"))
        #expect(!ZipArchive.isSafeRelativePath("/absolute/path"))
        #expect(!ZipArchive.isSafeRelativePath("media/../../secret.txt"))
        #expect(ZipArchive.isSafeRelativePath("media/media_0000.jpg"))

        #expect(throws: ZipArchiveError.self) {
            _ = try ZipArchive.encode(files: ["../evil.txt": Data("bad".utf8)])
        }
    }

    @Test("ZIP detects CRC32 corruption")
    func zipDetectsCorruptedCRC() throws {
        let original = try ZipArchive.encode(files: ["note.txt": Data(String(repeating: "pickup", count: 40).utf8)])
        var corrupted = original
        // Flip a byte inside the compressed payload (after local header of 38 bytes)
        corrupted[45] ^= 0xFF
        #expect(throws: Error.self) {
            _ = try ZipArchive.decode(corrupted)
        }
    }

    @Test("VaultCrypto AES-256-GCM seal/open, wrong passphrase, and tamper checks")
    func vaultCryptoRoundTripAndGuards() throws {
        let secret = Data("Pickup Secret Memory Payload — 把日子拾起来".utf8)
        let sealed = try VaultCrypto.seal(plaintext: secret, passphrase: "my-strong-passphrase", iterations: 5_000)
        #expect(VaultCrypto.looksLikeEncryptedVault(sealed))

        let opened = try VaultCrypto.open(vaultData: sealed, passphrase: "my-strong-passphrase")
        #expect(opened == secret)

        #expect(throws: VaultCryptoError.authenticationFailed) {
            _ = try VaultCrypto.open(vaultData: sealed, passphrase: "wrong-passphrase")
        }

        // Tamper ciphertext byte
        var tamperedJson = try JSONSerialization.jsonObject(with: sealed) as! [String: Any]
        let oldCipher = Data(base64Encoded: tamperedJson["ciphertextBase64"] as! String)!
        var flipped = oldCipher
        flipped[0] ^= 0x5A
        tamperedJson["ciphertextBase64"] = flipped.base64EncodedString()
        let tamperedData = try JSONSerialization.data(withJSONObject: tamperedJson)
        #expect(throws: VaultCryptoError.authenticationFailed) {
            _ = try VaultCrypto.open(vaultData: tamperedData, passphrase: "my-strong-passphrase")
        }
    }

    @Test("Passphrase lock verification hashes match correctly")
    func passphraseLockVerification() throws {
        let (salt, hash) = try VaultCrypto.hashPassphraseForLock("pickup2026")
        #expect(VaultCrypto.verifyPassphraseForLock("pickup2026", saltBase64: salt, hashBase64: hash))
        #expect(!VaultCrypto.verifyPassphraseForLock("wrong", saltBase64: salt, hashBase64: hash))
    }
}
