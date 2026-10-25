import Foundation
import CoreGraphics

package enum JPEGColorProfile {
    /// ImageIO can omit the ICC for its canonical sRGB space. Embed it explicitly
    /// so ordinary JPEG and Ultra HDR viewers use the exact same color profile.
    /// Only an APP2 marker is added; compressed image samples are unchanged.
    package static func embedSRGB(in jpeg: Data) throws -> Data {
        let bytes = [UInt8](jpeg)
        guard bytes.count >= 4, bytes[0] == 0xff, bytes[1] == 0xd8 else {
            throw BridgeError("JPEG 编码结果无效。")
        }
        let signature = Array("ICC_PROFILE\0".utf8)
        var index = 2
        while index + 4 <= bytes.count, bytes[index] == 0xff {
            let marker = bytes[index + 1]
            if marker == 0xda || marker == 0xd9 { break }
            let length = Int(bytes[index + 2]) * 256 + Int(bytes[index + 3])
            guard length >= 2, index + 2 + length <= bytes.count else { break }
            if marker == 0xe2, length >= 16,
               Array(bytes[(index + 4)..<(index + 16)]) == signature { return jpeg }
            index += 2 + length
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let icc = space.copyICCData() as Data?, icc.count <= 65519 else {
            throw BridgeError("无法嵌入 sRGB 色彩配置。")
        }
        let length = icc.count + 16
        var output = Data([0xff, 0xd8, 0xff, 0xe2, UInt8(length >> 8), UInt8(length & 255)])
        output.append(contentsOf: signature)
        output.append(contentsOf: [1, 1])
        output.append(icc)
        output.append(jpeg.dropFirst(2))
        return output
    }
}
