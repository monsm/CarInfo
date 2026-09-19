// =============================================================================
// N10 本地数据加密存储 — AES-256 通过 Keychain + CommonCrypto
// =============================================================================

import Foundation
import Security

enum DataEncryption {
    // MARK: - 密钥管理（存储在 Keychain）
    private static let keychainKey = "carkeeper_encryption_key"
    
    static func generateKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: "carkeeper_key",
            kSecAttrKeyType as String: kSecAttrKeyTypeAES,
            kSecAttrKeySizeInBits as String: 256,
            kSecValueData as String: Data(count: 32)
        ]
        
        // 检查是否已存在
        var item: CFTypeRef?
        SecItemCopyMatching(query as CFDictionary, &item)
        if item != nil { return nil } // 已存在
        
        SecItemAdd(query as CFDictionary, nil)
        return SecItemCopyMatching(query as CFDictionary, nil) as? Data
    }
    
    static func getKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: "carkeeper_key",
            kSecReturnData as String: true
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) as? Data
    }
    
    // MARK: - 加密
    static func encrypt(_ plaintext: String, key: Data?) -> String? {
        guard let key = key, key.count == 32 else { return nil }
        let plaintextData = plaintext.data(using: .utf8)!
        
        var encryptedData = Data(count: plaintextData.count + kCCBlockSizeAES128)
        var numBytesEncrypted: size_t = 0
        
        let keyBytes = (key as NSData).bytes
        let result = encryptedData.withUnsafeMutableBytes { buf in
            plaintextData.withUnsafeBytes { ptr in
                CCCrypt(
                    CCOperation(kCCEncrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionPKCS7Padding),
                    keyBytes, key.count,
                    nil, // IV
                    ptr.baseAddress, plaintextData.count,
                    buf.baseAddress, buf.count,
                    &numBytesEncrypted
                )
            }
        }
        
        guard result == kCCSuccess else { return nil }
        encryptedData.removeSubrange(numBytesEncrypted..<encryptedData.count)
        return encryptedData.base64EncodedString()
    }
    
    // MARK: - 解密
    static func decrypt(_ base64: String, key: Data?) -> String? {
        guard let key = key, key.count == 32 else { return nil }
        guard let encryptedData = Data(base64Encoded: base64) else { return nil }
        
        var decryptedData = Data(count: encryptedData.count)
        var numBytesDecrypted: size_t = 0
        
        let result = decryptedData.withUnsafeMutableBytes { buf in
            encryptedData.withUnsafeBytes { ptr in
                CCCrypt(
                    CCOperation(kCCDecrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionPKCS7Padding),
                    (key as NSData).bytes, key.count,
                    nil,
                    ptr.baseAddress, encryptedData.count,
                    buf.baseAddress, buf.count,
                    &numBytesDecrypted
                )
            }
        }
        
        guard result == kCCSuccess else { return nil }
        decryptedData.removeSubrange(numBytesDecrypted..<decryptedData.count)
        return String(data: decryptedData, encoding: .utf8)
    }
    
    // MARK: - 便捷 API
    static func saveEncrypted(_ value: String, forKey key: String) {
        guard let encrypted = encrypt(value, key: getKey()) else { return }
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
