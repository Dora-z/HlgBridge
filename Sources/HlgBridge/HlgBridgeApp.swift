import SwiftUI
import AppKit
import HlgCore

@main struct HlgBridgeApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加照片…") { model.chooseFiles() }.keyboardShortcut("o").disabled(model.running || model.importing)
            }
        }
    }
}
struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var targeted = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "sun.max.fill").font(.system(size: 29)).foregroundStyle(.orange)
                    .frame(width: 54, height: 54).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 3) {
                    Text("HlgBridge").font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text("让 HLG 照片，在更多屏幕上自然呈现").foregroundStyle(.secondary)
                }
                Spacer()
                Label("本地处理", systemImage: "lock.shield").font(.callout).foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            HSplitView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("照片队列").font(.headline)
                        Text("\(model.rows.count)").foregroundStyle(.secondary)
                        Spacer()
                        Button { model.chooseFiles() } label: { Image(systemName: "plus") }.help("添加照片或文件夹")
                        Button { model.clear() } label: { Image(systemName: "trash") }.help("清空队列")
                    }.disabled(model.running || model.importing)
                    if model.rows.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "photo.stack").font(.system(size: 44, weight: .light)).foregroundStyle(.orange)
                            Text("拖入照片或文件夹").font(.title3.weight(.medium))
                            Text("HIF · HEIF · HEIC\n保留原片，批量导出新文件").multilineTextAlignment(.center).foregroundStyle(.secondary)
                            Button("选择照片…") { model.chooseFiles() }.buttonStyle(.borderedProminent).tint(.orange)
                                .disabled(model.importing)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(targeted ? Color.orange.opacity(0.1) : Color.clear)
                    } else {
                        List(selection: $model.selection) {
                            ForEach(model.rows) { row in
                                HStack(spacing: 10) {
                                    Group {
                                        if let thumbnail = row.thumbnail { Image(nsImage: thumbnail).resizable().scaledToFill() }
                                        else { Image(systemName: "photo").resizable().scaledToFit().padding(12) }
                                    }.frame(width: 58, height: 48).clipped().clipShape(RoundedRectangle(cornerRadius: 6))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(row.url.lastPathComponent).font(.system(.body, weight: .medium)).lineLimit(1)
                                        Text(row.info.map { "\($0.kind.rawValue) · \($0.width) × \($0.height)" } ?? (row.failed ? "无法读取" : "读取信息…")).font(.caption).foregroundStyle(.secondary)
                                        Text(row.status).font(.caption).foregroundStyle(row.failed ? .red : .secondary).lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                    if !row.outputs.isEmpty { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                                }.padding(.vertical, 4).tag(row.id)
                            }
                        }.listStyle(.inset).scrollContentBackground(.hidden)
                    }
                }.padding(16).frame(minWidth: 310, idealWidth: 370)
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("转换预览").font(.headline); Spacer(); Text("SDR / sRGB").font(.caption.monospaced()).foregroundStyle(.secondary) }
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.90))
                        if let preview = model.preview { Image(nsImage: preview).resizable().scaledToFit().padding(8) }
                        else if model.previewBusy { ProgressView().colorScheme(.dark) }
                        else { Image(systemName: "photo.on.rectangle.angled").font(.system(size: 36)).foregroundStyle(.gray) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text(model.previewMessage).font(.caption).foregroundStyle(.secondary).frame(minHeight: 28)
                    if let index = model.rows.firstIndex(where: { $0.id == model.selection }), model.rows[index].info?.kind == .unknown {
                        Toggle("按松下 HLG 处理这张照片（仅在确认来源后启用）", isOn: $model.rows[index].assumeHLG)
                            .font(.caption).disabled(model.running)
                            .onChange(of: model.rows[index].assumeHLG) { _, _ in model.updatePreview() }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("SDR 观感", selection: $model.toneStyle) {
                            ForEach(ToneStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.onChange(of: model.toneStyle) { _, _ in model.updatePreview() }
                        if model.toneStyle == .natural {
                            Text("柔和压缩高光，保留亮部层次；可用 SDR 曝光补偿微调。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if model.toneStyle == .camera {
                            Text("基于单张室外照片的近似曲线，可能使室内照片偏亮；建议先用自然模式。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if model.toneStyle == .subject {
                            HStack {
                                Text("主体提亮").font(.caption)
                                Slider(value: $model.subjectLift, in: 0...1, step: 0.05) { editing in
                                    if !editing { model.updatePreview() }
                                }
                                Text("\(Int((model.subjectLift * 100).rounded()))%").font(.caption.monospacedDigit()).frame(width: 36)
                            }
                            Text("改善暗部观感，非松下 MODE2 精确复刻；仅影响 SDR 及 HDR 文件的 SDR 底图。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("SDR 曝光").font(.caption)
                            Slider(value: $model.sdrExposure, in: -3...3, step: 0.1) { editing in
                                if !editing { model.updatePreview() }
                            }
                            Text(String(format: "%+.1f EV", model.sdrExposure)).font(.caption.monospacedDigit()).frame(width: 66)
                            Button("重置") { model.sdrExposure = 0; model.updatePreview() }.font(.caption)
                        }
                        Picker("输出格式", selection: $model.mode) {
                            ForEach(OutputMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                        Text(model.mode == .sdr ? "通用 JPEG：适合相册浏览、分享和打印。" : "HDR JPEG 内含 SDR 底图；HDR 显示取决于设备和相册支持。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Label(model.outputDirectory?.lastPathComponent ?? "尚未选择输出目录", systemImage: "folder")
                                .lineLimit(1).help(model.outputDirectory?.path ?? "请选择输出目录")
                            Spacer()
                            Button("选择目录…") { model.chooseOutput() }
                        }
                        HStack {
                            Toggle("保留 GPS 位置", isOn: $model.keepGPS)
                            Spacer()
                            Text("原始尺寸 · 质量 95").font(.caption).foregroundStyle(.secondary)
                        }
                    }.disabled(model.running)
                }.padding(20).frame(minWidth: 440, minHeight: 460)
            }
            Divider()
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.message).font(.callout).foregroundStyle(.secondary)
                    if model.running { ProgressView(value: Double(model.completed), total: Double(max(1, model.rows.count))).tint(.orange) }
                }
                Spacer()
                if let directory = model.outputDirectory {
                    Button { NSWorkspace.shared.open(directory) } label: { Image(systemName: "folder.badge.gearshape") }.help("打开输出目录")
                }
                if model.running {
                    Button("取消") { model.cancel() }
                } else {
                    Button { model.run() } label: { Label("开始转换", systemImage: "arrow.right.circle.fill").padding(.horizontal, 12).padding(.vertical, 5) }
                        .buttonStyle(.borderedProminent).tint(.orange)
                        .disabled(model.rows.isEmpty || model.outputDirectory == nil || model.importing)
                }
            }.padding(20)
        }
        .frame(minWidth: 850, minHeight: 640)
        .onChange(of: model.selection) { _, _ in model.updatePreview() }
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.running, !model.importing else { return false }
            model.add(urls); return true
        } isTargeted: { targeted = $0 }
    }
}
