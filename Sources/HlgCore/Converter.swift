import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers
import CHDR

public final class Converter {
    private let context = CIContext(options: [.workingFormat: CIFormat.RGBAh,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!, .cacheIntermediates: false])
    public init() {}

    public static func inspect(_ url: URL) throws -> PhotoInfo {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = p[kCGImagePropertyPixelWidth as String] as? Int,
              let height = p[kCGImagePropertyPixelHeight as String] as? Int else {
            throw BridgeError("无法读取图片，文件可能损坏或格式不受支持。")
        }
        let profile = p[kCGImagePropertyProfileName as String] as? String ?? ""
        return PhotoInfo(url: url, width: width, height: height,
                         depth: p[kCGImagePropertyDepth as String] as? Int ?? 8,
                         profile: profile, kind: classify(profile))
    }
    public static func classify(_ profile: String) -> ColorKind {
        let name = profile.lowercased()
        if name.contains("hlg") { return .hlg }
        if name.contains("pq") || name.contains("log") { return .unknown }
        // Do not interpret untagged, PQ, or log images as sRGB.
        if name.contains("srgb") || name.contains("display p3") || name.contains("adobe rgb") || name.contains("bt.709") {
            return .sdr
        }
        return .unknown
    }
    private func load(_ url: URL, assumeHLG: Bool) throws -> (CIImage, PhotoInfo, [String: Any]) {
        let info = try Self.inspect(url)
        guard info.kind != .unknown || assumeHLG else {
            throw BridgeError("色彩标记未知。确认原片为松下 HLG 后，勾选“按松下 HLG 处理”并重试。")
        }
        var options: [CIImageOption: Any] = [.applyOrientationProperty: true]
        if info.kind == .unknown && assumeHLG { options[.colorSpace] = CGColorSpace(name: CGColorSpace.itur_2100_HLG)! }
        guard let image = CIImage(contentsOf: url, options: options),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            throw BridgeError("系统无法解码这张照片。")
        }
        let bounds = image.extent.integral
        guard bounds.width > 0, bounds.height > 0, bounds.width * bounds.height <= 100_000_000 else {
            throw BridgeError("照片尺寸无效或超过首版的 1 亿像素限制。")
        }
        return (image.transformed(by: CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)), info, properties)
    }
    private func sdrImage(_ image: CIImage, hdr: Bool, toneStyle: ToneStyle, subjectLift: Double) throws -> CIImage {
        guard hdr else { return image }
        let filter = CIFilter.toneMapHeadroom()
        filter.inputImage = image
        filter.sourceHeadroom = image.contentHeadroom > 1 ? image.contentHeadroom : 1000 / 203
        filter.targetHeadroom = 1
        let mapped = filter.outputImage ?? image
        return toneStyle == .subject ? try SubjectTone.apply(mapped, strength: subjectLift) : mapped
    }
    public func preview(_ url: URL, assumeHLG: Bool = false, toneStyle: ToneStyle = .subject, subjectLift: Double = 0.65) throws -> CGImage {
        let (input, info, _) = try load(url, assumeHLG: assumeHLG)
        let scale = min(1, 1400 / max(input.extent.width, input.extent.height))
        let image = try sdrImage(input, hdr: info.kind == .hlg || (info.kind == .unknown && assumeHLG), toneStyle: toneStyle, subjectLift: subjectLift)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let output = context.createCGImage(image, from: image.extent.integral, format: .RGBA8,
                                                 colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else {
            throw BridgeError("无法生成预览。")
        }
        return output
    }
    private func jpeg(_ image: CIImage, properties: [String: Any], keepGPS: Bool) throws -> Data {
        guard let cg = context.createCGImage(image, from: image.extent, format: .RGBA8,
                                             colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else {
            throw BridgeError("无法生成 SDR 像素。")
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw BridgeError("无法创建 JPEG 编码器。")
        }
        var output: [String: Any] = [kCGImageDestinationLossyCompressionQuality as String: 0.95,
                                    kCGImagePropertyOrientation as String: 1]
        // Copy photographic fields only. MakerNotes and stale HDR/container metadata are excluded.
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            let allowed = ["DateTimeOriginal", "DateTimeDigitized", "OffsetTime", "OffsetTimeOriginal", "OffsetTimeDigitized", "SubsecTimeOriginal", "SubsecTimeDigitized", "ExposureTime", "FNumber", "ISOSpeedRatings", "ExposureProgram", "ExposureBiasValue", "MeteringMode", "Flash", "FocalLength", "FocalLenIn35mmFilm", "LensMake", "LensModel", "WhiteBalance", "ExposureMode", "ApertureValue", "ShutterSpeedValue"]
            var clean = exif.filter { allowed.contains($0.key) }
            clean["PixelXDimension"] = cg.width; clean["PixelYDimension"] = cg.height; clean["ColorSpace"] = 1
            output[kCGImagePropertyExifDictionary as String] = clean
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            var clean = tiff.filter { ["Make", "Model", "DateTime", "Artist", "Copyright"].contains($0.key) }
            clean["Orientation"] = 1; clean["Software"] = "HlgBridge 1.0"
            output[kCGImagePropertyTIFFDictionary as String] = clean
        }
        if keepGPS { output[kCGImagePropertyGPSDictionary as String] = properties[kCGImagePropertyGPSDictionary as String] }
        CGImageDestinationAddImage(dest, cg, output as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw BridgeError("JPEG 编码失败。") }
        return data as Data
    }
    private func ultraHDR(_ input: CIImage, sdr: Data) throws -> Data {
        let width = Int(input.extent.width), height = Int(input.extent.height)
        // Core Image's extended linear BT.2020 uses SDR reference white = 1,
        // matching libultrahdr's linear-half input (203 nits reference white).
        var pixels = [UInt16](repeating: 0, count: width * height * 4)
        context.render(input, toBitmap: &pixels, rowBytes: width * 8, bounds: input.extent,
                       format: .RGBAh, colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!)
        var result: UnsafeMutablePointer<UInt8>?
        var size = 0
        var error = [CChar](repeating: 0, count: 512)
        let headroom: Float = input.contentHeadroom > 1 ? input.contentHeadroom : Float(1000.0 / 203.0)
        let peak: Float = min(10000.0, max(203.0, headroom * 203.0))
        let ok = pixels.withUnsafeBufferPointer { p in
            sdr.withUnsafeBytes { j in
                hlg_encode(p.baseAddress, UInt32(width), UInt32(height), j.bindMemory(to: UInt8.self).baseAddress,
                           sdr.count, peak, &result, &size, &error, error.count)
            }
        }
        guard ok == 1, let result else { throw BridgeError(String(cString: error)) }
        defer { hlg_free(result) }
        return Data(bytes: result, count: size)
    }
    public func convert(_ source: URL, to directory: URL, options: ConversionOptions = .init(),
                        cancellation: CancellationToken = .init()) throws -> ConversionResult {
        try cancellation.check()
        let (input, info, props) = try load(source, assumeHLG: options.assumeHLG)
        let isHDR = info.kind == .hlg || (info.kind == .unknown && options.assumeHLG)
        if !isHDR && options.mode == .hdr { throw BridgeError("这是 SDR 照片，不能生成真实 HDR；请选择普通 JPEG 或同时导出。") }
        let sdr = try jpeg(sdrImage(input, hdr: isHDR, toneStyle: options.toneStyle, subjectLift: options.subjectLift), properties: props, keepGPS: options.keepGPS)
        try cancellation.check()
        var pending: [(String, Data)] = []
        if options.mode != .hdr { pending.append(("SDR", sdr)) }
        if isHDR && options.mode != .sdr {
            pending.append(("HDR", try ultraHDR(input, sdr: sdr)))
        }
        try cancellation.check()
        let outputs = try Self.publish(pending, stem: source.deletingPathExtension().lastPathComponent,
                                       directory: directory, cancellation: cancellation)
        context.clearCaches()
        return ConversionResult(files: outputs, note: !isHDR && options.mode == .both ? "SDR 原片：仅导出普通 JPEG，未生成 HDR。" : nil)
    }
    // Stage all renditions before publishing. Never replace an existing file.
    package static func publish(_ items: [(String, Data)], stem: String, directory: URL,
                        cancellation: CancellationToken) throws -> [URL] {
        let fm = FileManager.default
        guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw BridgeError("输出目录不存在。")
        }
        var staging: [URL] = [], published: [URL] = []
        defer { for url in staging { try? fm.removeItem(at: url) } }
        do {
            for (_, data) in items {
                try cancellation.check()
                let url = directory.appendingPathComponent(".hlgbridge-\(UUID().uuidString).tmp")
                staging.append(url)
                try data.write(to: url, options: .withoutOverwriting)
            }
            for (index, item) in items.enumerated() {
                try cancellation.check()
                var number = 0
                while true {
                    let suffix = number == 0 ? "" : "_\(number)"
                    let destination = directory.appendingPathComponent("\(stem)_\(item.0)\(suffix).jpg")
                    if fm.fileExists(atPath: destination.path) { number += 1; continue }
                    do { try fm.moveItem(at: staging[index], to: destination) }
                    catch {
                        if fm.fileExists(atPath: destination.path) { number += 1; continue }
                        throw error
                    }
                    published.append(destination); break
                }
            }
            try cancellation.check()
            return published
        } catch {
            for url in published { try? fm.removeItem(at: url) }
            throw error
        }
    }
    public static func verifyHDR(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        var w: UInt32 = 0, h: UInt32 = 0, boost: Float = 0
        var error = [CChar](repeating: 0, count: 512)
        let result = data.withUnsafeBytes {
            hlg_verify($0.bindMemory(to: UInt8.self).baseAddress, data.count, &w, &h, &boost, &error, error.count)
        }
        guard result == 1 else { throw BridgeError(String(cString: error)) }
        return "有效 Ultra HDR：\(w) × \(h)，显示增益上限 \(boost)×；HDR 解码成功"
    }
}
