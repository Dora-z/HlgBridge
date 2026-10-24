import Foundation
import HlgCore

let args = Array(CommandLine.arguments.dropFirst())
do {
    if args.count == 2 && args[0] == "--verify" {
        print(try Converter.verifyHDR(URL(fileURLWithPath: args[1])))
    } else {
        guard args.count >= 2 else {
            throw BridgeError("用法：hlgbridge-cli 输入文件或目录 输出目录 [--sdr|--hdr] [--keep-gps] [--assume-hlg]\n      hlgbridge-cli --verify HDR.jpg")
        }
        let allowed = Set(["--sdr", "--hdr", "--keep-gps", "--assume-hlg"])
        guard args.dropFirst(2).allSatisfy({ allowed.contains($0) }), !(args.contains("--sdr") && args.contains("--hdr")) else { throw BridgeError("命令行选项无效。") }
        let source = URL(fileURLWithPath: args[0]), output = URL(fileURLWithPath: args[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let files = PhotoScanner.collect([source])
        guard !files.isEmpty else { throw BridgeError("未找到 HEIF 照片。") }
        let options = ConversionOptions(mode: args.contains("--sdr") ? .sdr : args.contains("--hdr") ? .hdr : .both,
                                        keepGPS: args.contains("--keep-gps"), assumeHLG: args.contains("--assume-hlg"))
        var failed = false
        for file in files {
            do {
                let result = try autoreleasepool { try Converter().convert(file, to: output, options: options) }
                result.files.forEach { print($0.path) }
                if let note = result.note { print(note) }
            } catch {
                failed = true
                FileHandle.standardError.write(Data("\(file.lastPathComponent): \(error.localizedDescription)\n".utf8))
            }
        }
        if failed { exit(1) }
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8)); exit(1)
}
