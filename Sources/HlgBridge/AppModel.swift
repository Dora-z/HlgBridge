import SwiftUI
import AppKit
import HlgCore
import ImageIO

struct PhotoRow: Identifiable {
    let id = UUID()
    let url: URL
    var info: PhotoInfo?
    var thumbnail: NSImage?
    var status = "等待转换"
    var failed = false
    var outputs: [URL] = []
    var assumeHLG = false
}
@MainActor final class AppModel: ObservableObject {
    @Published var rows: [PhotoRow] = []
    @Published var selection: UUID?
    @Published var mode: OutputMode = .both
    @Published var keepGPS = false
    @Published var outputDirectory: URL?
    @Published var running = false
    @Published var importing = false
    @Published var completed = 0
    @Published var message = "所有照片仅在本机处理"
    @Published var preview: NSImage?
    @Published var previewBusy = false
    @Published var previewMessage = "选择照片，查看转换后的 SDR 预览"
    private var token: CancellationToken?
    private var previewID = UUID()

    func chooseFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true; panel.canChooseFiles = true
        panel.message = "选择 HEIF 照片或包含照片的文件夹"
        if panel.runModal() == .OK { add(panel.urls) }
    }
    func chooseOutput() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true; panel.prompt = "选择输出目录"
        if panel.runModal() == .OK { outputDirectory = panel.url }
    }
    func add(_ urls: [URL]) {
        guard !running, !importing else { return }
        importing = true; message = "正在读取照片…"
        Task {
            let imported = await Task.detached(priority: .userInitiated) {
                PhotoScanner.collect(urls).map { url -> PhotoRow in
                    autoreleasepool {
                        var row = PhotoRow(url: url)
                        do { row.info = try Converter.inspect(url) }
                        catch { row.status = error.localizedDescription; row.failed = true }
                        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                           let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: 160] as CFDictionary) {
                            row.thumbnail = NSImage(cgImage: cg, size: .zero)
                        }
                        return row
                    }
                }
            }.value
            let existing = Set(rows.map(\.url))
            rows.append(contentsOf: imported.filter { !existing.contains($0.url) })
            importing = false
            message = imported.isEmpty ? "未找到 HIF、HEIF 或 HEIC 照片" : "已加入 \(rows.count) 张照片"
            if selection == nil { selection = rows.first?.id }
        }
    }
    func updatePreview() {
        let request = UUID(); previewID = request
        preview = nil
        guard let row = rows.first(where: { $0.id == selection }) else { return }
        previewBusy = true; previewMessage = "正在生成 SDR 预览…"
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<CGImage, Error> in
                Result { try Converter().preview(row.url, assumeHLG: row.assumeHLG) }
            }.value
            guard previewID == request else { return }
            previewBusy = false
            switch result {
            case .success(let image):
                preview = NSImage(cgImage: image, size: .zero)
                previewMessage = "SDR 预览 · sRGB · 导出保持原始尺寸"
            case .failure(let error): previewMessage = error.localizedDescription
            }
        }
    }
    func run() {
        guard !running, !rows.isEmpty, let directory = outputDirectory else { return }
        let cancellation = CancellationToken(); token = cancellation
        let outputMode = mode, gps = keepGPS
        running = true; completed = 0; message = "开始转换…"
        for i in rows.indices { rows[i].status = "等待转换"; rows[i].failed = false; rows[i].outputs = [] }
        Task {
            for index in rows.indices {
                do { try cancellation.check() } catch { break }
                let row = rows[index]
                rows[index].status = "转换中…"
                message = "正在转换 \(index + 1) / \(rows.count)"
                let result = await Task.detached(priority: .userInitiated) { () -> Result<ConversionResult, Error> in
                    autoreleasepool {
                        Result { try Converter().convert(row.url, to: directory,
                            options: .init(mode: outputMode, keepGPS: gps, assumeHLG: row.assumeHLG), cancellation: cancellation) }
                    }
                }.value
                switch result {
                case .success(let output):
                    rows[index].outputs = output.files
                    rows[index].status = output.note ?? "已导出 \(output.files.count) 个文件"
                case .failure(let error):
                    if error is CancellationError { rows[index].status = "已取消" }
                    else { rows[index].status = error.localizedDescription; rows[index].failed = true }
                }
                completed += 1
            }
            let successes = rows.filter { !$0.outputs.isEmpty }.count
            let failures = rows.filter(\.failed).count
            for i in rows.indices where rows[i].status == "等待转换" { rows[i].status = "未处理" }
            message = "完成 \(successes) 张 · 失败 \(failures) 张 · 未输出 \(rows.count - successes - failures) 张"
            running = false; token = nil
        }
    }
    func cancel() { token?.cancel(); message = "正在取消，等待当前编解码步骤结束…" }
    func clear() { rows = []; selection = nil; preview = nil; previewID = UUID(); previewBusy = false; completed = 0; message = "所有照片仅在本机处理" }
}
