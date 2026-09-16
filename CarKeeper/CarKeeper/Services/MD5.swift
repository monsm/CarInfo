import Foundation

// 纯 Swift MD5：输出与桌面版一致的大写十六进制。
// 输入为 UTF-8 字符串，按标准 MD5 分块（512-bit）处理。
enum MD5 {
    static func hash(_ input: String) -> String {
        let msg = input.data(using: .utf8) ?? Data()
        return hash(data: msg)
    }

    static func hash(data: Data) -> String {
        let n = data.count
        // 分块补齐：n % 64 != 56 则补到下一个 64 边界
        var padded = Data()
        padded.append(data)
        padded.append(0x80)
        while padded.count % 64 != 56 {
            padded.append(0)
        }
        // 64-bit 小端长度（长度 = 原始数据字节数 * 8，按 8 字节小端逐字节追加：LSB 在前）
        let bitLen = UInt64(n) * 8
        for i in 0..<8 {
            padded.append(UInt8(truncatingIfNeeded: bitLen >> UInt64(i * 8)))
        }

        // 初始常量
        var a0: UInt32 = 0x67452301, b0: UInt32 = 0xefcdab89, c0: UInt32 = 0x98badcfe, d0: UInt32 = 0x10325476
        let K: [UInt32] = (0..<64).map { i in
            UInt32((abs(sin(Double(i + 1))) * 0x100000000).rounded(.down))
        }
        let S: [UInt32] = [
            7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,
            5, 9,14,20,5, 9,14,20,5, 9,14,20,5, 9,14,20,
            4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,
            6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21
        ]

        let words = padded.count / 4
        var M = [UInt32](repeating: 0, count: 16)
        for off in stride(from: 0, to: words, by: 16) {
            for i in 0..<16 {
                let idx = off + i
                M[i] = UInt32(padded[idx*4])
                     | (UInt32(padded[idx*4+1]) << 8)
                     | (UInt32(padded[idx*4+2]) << 16)
                     | (UInt32(padded[idx*4+3]) << 24)
            }

            var A = a0, B = b0, C = c0, D = d0
            for i in 0..<64 {
                var F: UInt32
                var g: Int
                switch i {
                case 0..<16:   F = (B & C) | (~B & D); g = i
                case 16..<32:  F = (D & B) | (~D & C); g = (5*i + 1) % 16
                case 32..<48:  F = B ^ C ^ D;         g = (3*i + 5) % 16
                default:       F = C ^ (B | ~D);       g = (7*i) % 16
                }
                F = F &+ A &+ K[i] &+ M[g]
                let temp = D
                D = C
                C = B
                B = B &+ rotateLeft(F, S[i])
                A = temp
            }
            a0 = a0 &+ A
            b0 = b0 &+ B
            c0 = c0 &+ C
            d0 = d0 &+ D
        }

        let digest = [a0, b0, c0, d0]
        // 小端输出
        var out = ""
        for w in digest {
            out += String(format: "%02x", w & 0xff)
            out += String(format: "%02x", (w >> 8) & 0xff)
            out += String(format: "%02x", (w >> 16) & 0xff)
            out += String(format: "%02x", (w >> 24) & 0xff)
        }
        return out.uppercased()
    }

    private static func rotateLeft(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x << n) | (x >> (32 - n))
    }
}
