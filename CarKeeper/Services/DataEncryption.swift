// =============================================================================
// N10 本地数据加密存储 — AES-256-GCM 通过 CryptoKit + Keychain
// =============================================================================

import Foundation
import Security
import CryptoKit

enum DataEncryption {
    // MARK: - 密钥管理（使用 CryptoKit AES-GCM，存储于 Keychain）
    private static let keychainKey = "carkeeper_encryption_key"

    /// 确保加密密钥已生成（App 启动时调用）
    static func ensureKey() {
        if getKey() == nil { _ = generateKey() }
    }

    static func generateKey() -> SymmetricKey? {
        if getKey() != nil { return nil }
        let key = SymmetricKey(size: .bits256)
        saveKey(key)
        return key
    }

    static func getKey() -> SymmetricKey? {
        guard let data = getKeychainData() else { return nil }
        return SymmetricKey(data: data)
    }

    private static func saveKey(_ key: SymmetricKey) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: "carkeeper_key",
            kSecValueData as String: key.withUnsafeBytes { Data($0) }
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func getKeychainData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: "carkeeper_key",
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        SecItemCopyMatching(query as CFDictionary, &item)
        return item as? Data
    }

    // MARK: - 加密（AES-GCM）
    static func encrypt(_ plaintext: String, key: SymmetricKey?) -> String? {
        guard let key = key else { return nil }
        let plaintextData = plaintext.data(using: .utf8) ?? Data()
        do {
            let sealed = try AES.GCM.seal(plaintextData, using: key)
            return sealed.combined?.base64EncodedString()
        } catch { return nil }
    }

    // MARK: - 解密（AES-GCM）
    static func decrypt(_ base64: String, key: SymmetricKey?) -> String? {
        guard let key = key,
              let combined = Data(base64Encoded: base64),
              let sealedBox = try? AES.GCM.SealedBox(combined: combined) else { return nil }
        do {
            let plaintext = try AES.GCM.open(sealedBox, using: key)
            return String(data: plaintext, encoding: .utf8)
        } catch { return nil }
    }

    static func saveEncrypted(_ plaintext: String, forKey key: String) {
        guard let encrypted = encrypt(plaintext, key: getKey()) else { return }
        UserDefaults.standard.set(encrypted, forKey: "enc_\(key)")
    }

    static func loadEncrypted(forKey key: String) -> String? {
        guard let encrypted = UserDefaults.standard.string(forKey: "enc_\(key)") else { return nil }
        return decrypt(encrypted, key: getKey())
    }
}

// MARK: - 敏感数据封装
struct SecureStorage {
    static let shared = SecureStorage()

    // PIN（已存在 Keychain，这里只做备份加密）
    func savePIN(_ pin: String) {
        DataEncryption.saveEncrypted(pin, forKey: "pin_backup")
    }

    func loadPIN() -> String? {
        return DataEncryption.loadEncrypted(forKey: "pin_backup")
    }

    // 车牌号
    func savePlate(_ plate: String) {
        DataEncryption.saveEncrypted(plate, forKey: "plate")
    }

    func loadPlate() -> String? {
        return DataEncryption.loadEncrypted(forKey: "plate")
    }
}
