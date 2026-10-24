
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
    func testHLGDualOutputMetadataAndHDRDecode() throws {
        let source = try fixture()
        XCTAssertEqual(try Converter.inspect(source).kind, .hlg)
        let before = try Data(contentsOf: source)
        let result = try Converter().convert(source, to: directory)
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
            let image = try XCTUnwrap(CIImage(contentsOf: url, options: [.expandToHDR: false]))
            var pixels = [UInt8](repeating: 0, count: 64 * 48 * 4)
            context.render(image, toBitmap: &pixels, rowBytes: 64 * 4, bounds: CGRect(x: 0, y: 0, width: 64, height: 48), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return pixels
        }
        XCTAssertEqual(try pixels(sdr), try pixels(hdr))
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
}
