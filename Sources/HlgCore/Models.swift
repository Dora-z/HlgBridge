import Foundation
import ImageIO

public enum OutputMode: String, CaseIterable, Sendable {
    case sdr = "普通 JPEG", hdr = "HDR JPEG", both = "同时导出"
}
public enum ToneStyle: String, CaseIterable, Sendable {
    case natural = "自然 · 保留高光", cameraHighlight = "机内近似 · 保留高光", camera = "机内转换近似", subject = "主体明亮", standard = "系统映射"
}
public enum ColorKind: String, Sendable { case hlg = "HDR · HLG", sdr = "SDR", unknown = "未知色彩" }
public struct PhotoInfo: Sendable {
    public let url: URL
    public let width: Int
    public let height: Int
    public let depth: Int
    public let profile: String
    public let kind: ColorKind
}
public struct ConversionOptions: Sendable {
    public var mode: OutputMode = .both
    public var keepGPS = false
    public var assumeHLG = false
    public var toneStyle: ToneStyle = .natural
    public var subjectLift: Double = 0.65
    public var sdrExposure: Double = 0
    public init(mode: OutputMode = .both, keepGPS: Bool = false, assumeHLG: Bool = false, toneStyle: ToneStyle = .natural, subjectLift: Double = 0.65, sdrExposure: Double = 0) {
        self.mode = mode; self.keepGPS = keepGPS; self.assumeHLG = assumeHLG
        self.toneStyle = toneStyle; self.subjectLift = subjectLift; self.sdrExposure = sdrExposure
    }
}
public struct ConversionResult: Sendable {
    public let files: [URL]
    public let note: String?
}
public struct BridgeError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public func check() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw CancellationError() }
    }
}
public enum PhotoScanner {
    public static let extensions: Set<String> = ["hif", "heif", "heic"]
    public static func collect(_ urls: [URL]) -> [URL] {
        var found = Set<URL>()
        for url in urls {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                    for case let child as URL in files where extensions.contains(child.pathExtension.lowercased()) {
                        if (try? child.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { found.insert(child.standardizedFileURL.resolvingSymlinksInPath()) }
                    }
                }
            } else if extensions.contains(url.pathExtension.lowercased()) { found.insert(url.standardizedFileURL.resolvingSymlinksInPath()) }
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
