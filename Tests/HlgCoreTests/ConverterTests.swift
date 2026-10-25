
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import HlgCore

final class ConverterTests {
    var directory: URL!
    func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("HlgBridgeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func fixture(hdr: Bool = true, orientation: Int = 1, colorSpace: CGColorSpace? = nil) throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString + ".heic")
        let space = colorSpace ?? CGColorSpace(name: hdr ? CGColorSpace.itur_2100_HLG : CGColorSpace.sRGB)!
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
        let context = CIContext(options: [.workingColorSpace: linear, .workingFormat: CIFormat.RGBAh])
        let left = CIImage(color: CIColor(red: hdr ? 3 : 0.6, green: hdr ? 2 : 0.3, blue: 0.2, colorSpace: linear)!).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 48))
        let right = CIImage(color: CIColor(red: 0.1, green: 0.2, blue: 0.3, colorSpace: linear)!).cropped(to: CGRect(x: 32, y: 0, width: 32, height: 48))
        let image = left.composited(over: right).settingProperties([
            kCGImagePropertyOrientation as String: orientation,
            kCGImagePropertyTIFFDictionary as String: ["Make": "Synthetic", "Model": "Test Camera", "Orientation": orientation],
            kCGImagePropertyExifDictionary as String: ["DateTimeOriginal": "2026:01:02 03:04:05", "ExposureTime": 0.01, "FNumber": 2.8],
            kCGImagePropertyGPSDictionary as String: ["Latitude": 10.0, "LatitudeRef": "N", "Longitude": 20.0, "LongitudeRef": "E"]
        ])
        if hdr {
            try context.writeHEIF10Representation(of: image, to: url, colorSpace: space)
        } else {
            try context.writeHEIFRepresentation(of: image, to: url, format: .RGBA8, colorSpace: space)
        }
        return url
    }
    func properties(_ url: URL) throws -> [String: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    }
    func testHLGDualOutputMetadataAndHDRDecode(style: ToneStyle = .natural) throws {
        let source = try fixture()
        XCTAssertEqual(try Converter.inspect(source).kind, .hlg)
        let before = try Data(contentsOf: source)
        let result = try Converter().convert(source, to: directory, options: .init(toneStyle: style))
        XCTAssertEqual(result.files.count, 2)
        let sdr = result.files[0], hdr = result.files[1]
        XCTAssertTrue(try Converter.verifyHDR(hdr).contains("64 × 48"))
        for file in [sdr, hdr] {
            let p = try properties(file)
            XCTAssertEqual(p[kCGImagePropertyPixelWidth as String] as? Int, 64)
            XCTAssertEqual(p[kCGImagePropertyPixelHeight as String] as? Int, 48)
            XCTAssertNil(p[kCGImagePropertyGPSDictionary as String])
            let exif = p[kCGImagePropertyExifDictionary as String] as? [String: Any]
            XCTAssertEqual(exif?["DateTimeOriginal"] as? String, "2026:01:02 03:04:05")
            let tiff = p[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
            XCTAssertEqual(tiff?["Model"] as? String, "Test Camera")
        }
        XCTAssertEqual(before, try Data(contentsOf: source))
        // The compressed SDR base must be reused without another JPEG generation.
        let context = CIContext()
        func pixels(_ url: URL) throws -> [UInt8] {
            let encoded = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let base = try XCTUnwrap(CGImageSourceCreateImageAtIndex(encoded, 0, [kCGImageSourceShouldAllowFloat: false] as CFDictionary))
            // Inspect the ordinary JPEG base independently of Core Image's
            // gain-map display adaptation for a file-backed HDR CIImage.
            let image = CIImage(cgImage: base, options: [.contentHeadroom: 1.0, .toneMapHDRtoSDR: false])
            var pixels = [UInt8](repeating: 0, count: 64 * 48 * 4)
            context.render(image, toBitmap: &pixels, rowBytes: 64 * 4, bounds: CGRect(x: 0, y: 0, width: 64, height: 48), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return pixels
        }
        let sdrPixels = try pixels(sdr), hdrPixels = try pixels(hdr)
        XCTAssertEqual(sdrPixels, hdrPixels)
        for file in [sdr, hdr] {
            XCTAssertNotNil(try Data(contentsOf: file).range(of: Data("ICC_PROFILE\0".utf8)))
        }
    }
    func testSDRDoesNotInventHDR() throws {
        let source = try fixture(hdr: false)
        XCTAssertEqual(try Converter.inspect(source).kind, .sdr)
        let result = try Converter().convert(source, to: directory)
        XCTAssertEqual(result.files.count, 1)
        XCTAssertNotNil(result.note)
        XCTAssertThrowsError(try Converter().convert(source, to: directory, options: .init(mode: .hdr)))
    }
    func testOrientationAndGPS() throws {
        let source = try fixture(orientation: 6)
        let result = try Converter().convert(source, to: directory, options: .init(keepGPS: true))
        for file in result.files {
            let p = try properties(file)
            XCTAssertEqual(p[kCGImagePropertyPixelWidth as String] as? Int, 48)
            XCTAssertEqual(p[kCGImagePropertyPixelHeight as String] as? Int, 64)
            XCTAssertEqual(p[kCGImagePropertyOrientation as String] as? Int, 1)
            XCTAssertNotNil(p[kCGImagePropertyGPSDictionary as String])
        }
    }
    func testUnknownProfileAndCorruption() throws {
        XCTAssertEqual(Converter.classify(""), .unknown)
        XCTAssertEqual(Converter.classify("Rec. ITU-R BT.2100 PQ"), .unknown)
        let source = try fixture(hdr: false, colorSpace: CGColorSpace(name: CGColorSpace.itur_2020))
        XCTAssertEqual(try Converter.inspect(source).kind, .unknown)
        XCTAssertThrowsError(try Converter().convert(source, to: directory))
        let broken = directory.appendingPathComponent("broken.hif")
        try Data("broken".utf8).write(to: broken)
        XCTAssertThrowsError(try Converter().convert(broken, to: directory))
    }
    func testCollisionDoesNotReplaceOriginal() throws {
        let token = CancellationToken()
        let original = Data("first".utf8), next = Data("second".utf8)
        let first = try Converter.publish([("SDR", original)], stem: "photo", directory: directory, cancellation: token)
        let second = try Converter.publish([("SDR", next)], stem: "photo", directory: directory, cancellation: token)
        XCTAssertEqual(second.first?.lastPathComponent, "photo_SDR_1.jpg")
        XCTAssertEqual(try Data(contentsOf: first[0]), original)
    }
    func testCancelledAndUnwritableLeaveNoTemporaryFiles() throws {
        let token = CancellationToken(); token.cancel()
        XCTAssertThrowsError(try Converter.publish([("SDR", Data([1]))], stem: "cancel", directory: directory, cancellation: token))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        XCTAssertThrowsError(try Converter.publish([("SDR", Data([1]))], stem: "denied", directory: directory, cancellation: .init()))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
    func testRecursiveScannerDeduplicates() throws {
        let file = try fixture(hdr: false)
        let files = PhotoScanner.collect([file, directory, file])
        XCTAssertEqual(files.count, 1)
    }
    func testSubjectTonePreservesEndpointsAndRaisesMidtones() throws {
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!])
        let space = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
        var previous: Float = -1
        for value in [Float(0), 0.01, 0.1, 0.3, 0.7, 1] {
            let input = CIImage(color: CIColor(red: CGFloat(value), green: CGFloat(value), blue: CGFloat(value), colorSpace: space)!).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
            let output = try SubjectTone.apply(input, strength: 0.65)
            var pixel = [Float](repeating: 0, count: 4)
            context.render(output, toBitmap: &pixel, rowBytes: 16, bounds: input.extent, format: .RGBAf, colorSpace: space)
            XCTAssertTrue(pixel.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1.001 })
            XCTAssertTrue(abs(pixel[0] - pixel[1]) < 0.001 && abs(pixel[1] - pixel[2]) < 0.001)
            XCTAssertTrue(pixel[0] >= previous)
            if value > 0 && value < 1 { XCTAssertTrue(pixel[0] > value) }
            if value == 0 || value == 1 { XCTAssertTrue(abs(pixel[0] - value) < 0.001) }
            previous = pixel[0]
        }
        let source = try fixture(hdr: false)
        let standard = try Converter().convert(source, to: directory, options: .init(mode: .sdr, toneStyle: .standard))
        let subject = try Converter().convert(source, to: directory, options: .init(mode: .sdr, toneStyle: .subject))
        XCTAssertEqual(try Data(contentsOf: standard.files[0]), try Data(contentsOf: subject.files[0]))
    }

    func testCameraToneMonotonicNeutralAndSDRBypass() throws {
        let space = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
        let context = CIContext(options: [.workingColorSpace: space, .workingFormat: CIFormat.RGBAf])
        var previous: Float = -1
        for value in [Float(0), 0.0001, 0.005, 0.02, 0.1, 0.18, 0.5, 1, 2, 4.926] {
            let input = CIImage(color: CIColor(red: CGFloat(value), green: CGFloat(value), blue: CGFloat(value), colorSpace: space)!).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
            let output = try CameraTone.apply(input)
            var p = [Float](repeating: 0, count: 4)
            context.render(output, toBitmap: &p, rowBytes: 16, bounds: input.extent, format: .RGBAf, colorSpace: space)
            XCTAssertTrue(p.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1.001 })
            XCTAssertTrue(abs(p[0] - p[1]) < 0.001 && abs(p[1] - p[2]) < 0.001)
            XCTAssertTrue(p[0] >= previous)
            if value == 0 { XCTAssertTrue(p[0] < 0.0001) }
            if value > 0 && value <= 0.5 { XCTAssertTrue(p[0] > value) }
            if value >= 1 { XCTAssertTrue(abs(p[0] - 1) < 0.001) }
            previous = p[0]
        }
        let sdr = try fixture(hdr: false)
        let standard = try Converter().convert(sdr, to: directory, options: .init(mode: .sdr, toneStyle: .standard))
        let camera = try Converter().convert(sdr, to: directory, options: .init(mode: .sdr))
        XCTAssertEqual(try Data(contentsOf: standard.files[0]), try Data(contentsOf: camera.files[0]))
        XCTAssertEqual(ConversionOptions().toneStyle, .natural)
    }

    func testExportedSDRDoesNotRemapHDRTwice() throws {
        let source = try fixture()
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
        let context = CIContext(options: [.workingColorSpace: linear, .workingFormat: CIFormat.RGBAf])
        let input = try XCTUnwrap(CIImage(contentsOf: source))
        let patch = CGRect(x: 48, y: 24, width: 1, height: 1)
        var raw = [Float](repeating: 0, count: 4)
        context.render(input, toBitmap: &raw, rowBytes: 16, bounds: patch, format: .RGBAf, colorSpace: linear)
        let y = raw[0] * 0.2627 + raw[1] * 0.6780 + raw[2] * 0.0593
        let target = min(3.30 * y / (1 + 2.10 * y), 1)
        let rgb = SIMD3<Float>(raw[0], raw[1], raw[2]) * (target / y)
        // Linear BT.2020 -> linear BT.709, followed by the sRGB transfer curve.
        let r = rgb.x * 1.660491 - rgb.y * 0.587641 - rgb.z * 0.072850
        let g = -rgb.x * 0.124551 + rgb.y * 1.132900 - rgb.z * 0.008349
        let b = -rgb.x * 0.018151 - rgb.y * 0.100579 + rgb.z * 1.118730
        let expected = [r, g, b].map { value -> Float in
            let c = min(1, max(0, value))
            return 255 * (c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055)
        }
        let converter = Converter()
        let result = try converter.convert(source, to: directory, options: .init(mode: .sdr, toneStyle: .camera))
        let output = try XCTUnwrap(CIImage(contentsOf: result.files[0]))
        let preview = CIImage(cgImage: try converter.preview(source, toneStyle: .camera))
        for image in [output, preview] {
            var actual = [UInt8](repeating: 0, count: 4)
            context.render(image, toBitmap: &actual, rowBytes: 4, bounds: patch, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            for channel in 0..<3 { XCTAssertTrue(abs(Float(actual[channel]) - expected[channel]) <= 3) }
        }
    }

    func testCameraHighlightRetainsMidtonesAndBrightDetail() throws {
        let space = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
        let context = CIContext(options: [.workingColorSpace: space, .workingFormat: CIFormat.RGBAf])
        func render(_ color: [Float], protected: Bool, output: CGColorSpace) throws -> [Float] {
            let input = CIImage(color: CIColor(red: CGFloat(color[0]), green: CGFloat(color[1]), blue: CGFloat(color[2]), colorSpace: space)!).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
            let mapped = try protected ? CameraHighlightTone.apply(input) : CameraTone.apply(input)
            var pixel = [Float](repeating: 0, count: 4)
            context.render(mapped, toBitmap: &pixel, rowBytes: 16, bounds: input.extent, format: .RGBAf, colorSpace: output)
            return pixel
        }
        // The new mode must actually retain the old look, not simply darken the photo.
        for rgb: [Float] in [[0, 0, 0], [0.02, 0.02, 0.02], [0.05, 0.05, 0.05], [0.09, 0.09, 0.09], [0.04, 0.06, 0.05]] {
            let old = try render(rgb, protected: false, output: space)
            let new = try render(rgb, protected: true, output: space)
            for channel in 0..<3 { XCTAssertTrue(abs(new[channel] - old[channel]) < 0.0001) }
        }
        var previous: Float = 0
        for value: Float in [0.3825, 0.5, 0.8334, 1, 2, 4.926, 10] {
            let p = try render([value, value, value], protected: true, output: space)
            XCTAssertTrue(p[0] > previous + 0.001 && p[0] < 0.99)
            XCTAssertTrue(abs(p[0] - p[1]) < 0.001 && abs(p[1] - p[2]) < 0.001)
            previous = p[0]
        }
        let firstBright = try render([1, 1, 1], protected: true, output: space)
        let secondBright = try render([2, 2, 2], protected: true, output: space)
        XCTAssertTrue(secondBright[0] - firstBright[0] > 0.08)
        let destination = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        for rgb: [Float] in [[4, 0.1, 0.1], [0.1, 4, 0.1], [0.1, 0.1, 4], [4, 3, 0.1]] {
            let p = try render(rgb, protected: true, output: destination)
            XCTAssertTrue(p.prefix(3).allSatisfy { $0.isFinite && $0 >= -0.002 && $0 <= 1.002 })
        }
        let sdr = try fixture(hdr: false)
        let converter = Converter()
        let original = try converter.convert(sdr, to: directory, options: .init(mode: .sdr, toneStyle: .camera))
        let protected = try converter.convert(sdr, to: directory, options: .init(mode: .sdr, toneStyle: .cameraHighlight))
        XCTAssertEqual(try Data(contentsOf: original.files[0]), try Data(contentsOf: protected.files[0]))
    }

    func testNaturalTonePreservesBrightDetailAndExposure() throws {
        let space = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
        let context = CIContext(options: [.workingColorSpace: space, .workingFormat: CIFormat.RGBAf])
        var previous: Float = 0
        for value in [Float(0.5), 1, 2, 4.926] {
            let input = CIImage(color: CIColor(red: CGFloat(value), green: CGFloat(value), blue: CGFloat(value), colorSpace: space)!).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
            let mapped = try NaturalTone.apply(input)
            var pixel = [Float](repeating: 0, count: 4)
            context.render(mapped, toBitmap: &pixel, rowBytes: 16, bounds: input.extent, format: .RGBAf, colorSpace: space)
            XCTAssertTrue(pixel[0] > previous + 0.001 && pixel[0] < 0.99)
            XCTAssertTrue(abs(pixel[0] - pixel[1]) < 0.001 && abs(pixel[1] - pixel[2]) < 0.001)
            previous = pixel[0]
        }
        let source = try fixture()
        let converter = Converter()
        func rightPatch(_ cg: CGImage) -> Int {
            var pixel = [UInt8](repeating: 0, count: 4)
            context.render(CIImage(cgImage: cg), toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 48, y: 24, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])
        }
        let normal = try converter.preview(source)
        let darker = try converter.preview(source, sdrExposure: -1)
        XCTAssertTrue(rightPatch(darker) < rightPatch(normal))
        XCTAssertThrowsError(try converter.preview(source, sdrExposure: .nan))
    }

}
