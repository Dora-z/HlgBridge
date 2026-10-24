// Usage: swift Scripts/compare-reference.swift reference.jpg output1.jpg [output2.jpg ...]
// Local quantitative comparison only; never uploads or changes the images.
import Foundation
import CoreImage

struct ComparisonError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
let args = Array(CommandLine.arguments.dropFirst())
do {
    guard args.count >= 2 else { throw ComparisonError(message: "请提供一张参考图和至少一张待比较图片。") }
    let context = CIContext(options: [.cacheIntermediates: false])
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    func load(_ path: String) throws -> CIImage {
        guard let image = CIImage(contentsOf: URL(fileURLWithPath: path), options: [.applyOrientationProperty: true, .expandToHDR: false]) else {
            throw ComparisonError(message: "无法读取 \(path)")
        }
        return image
    }
    let reference = try load(args[0])
    let scale = min(1, 1200 / max(reference.extent.width, reference.extent.height))
    let bounds = reference.extent.applying(CGAffineTransform(scaleX: scale, y: scale)).integral
    let width = Int(bounds.width), height = Int(bounds.height)
    func pixels(_ input: CIImage) -> [UInt8] {
        let image = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        context.render(image, toBitmap: &bytes, rowBytes: width * 4, bounds: bounds, format: .RGBA8, colorSpace: colorSpace)
        return bytes
    }
    let expected = pixels(reference)
    print("参考：\(URL(fileURLWithPath: args[0]).lastPathComponent)，比较分辨率 \(width) × \(height)，sRGB 8 位")
    for path in args.dropFirst() {
        let image = try load(path)
        guard image.extent.size == reference.extent.size else { throw ComparisonError(message: "尺寸不同，不能进行对应像素比较：\(path)") }
        let actual = pixels(image)
        var sum: Int64 = 0, sumSquared: Int64 = 0
        var histogram = [Int](repeating: 0, count: 256)
        for index in expected.indices where index % 4 != 3 {
            let difference = abs(Int(actual[index]) - Int(expected[index]))
            sum += Int64(difference); sumSquared += Int64(difference * difference)
            histogram[difference] += 1
        }
        let count = width * height * 3
        var cumulative = 0, percentile95 = 0
        for value in histogram.indices {
            cumulative += histogram[value]
            if Double(cumulative) >= Double(count) * 0.95 { percentile95 = value; break }
        }
        let mae = Double(sum) / Double(count), rmse = sqrt(Double(sumSquared) / Double(count))
        print("\(URL(fileURLWithPath: path).lastPathComponent): MAE=\(String(format: "%.3f", mae))/255，RMSE=\(String(format: "%.3f", rmse))/255，P95=\(percentile95)/255")
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8)); exit(1)
}
