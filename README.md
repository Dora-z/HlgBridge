# HlgBridge

中文 macOS 桌面工具，将松下相机的 HLG HEIF 照片批量转换为普通 sRGB JPEG 和 Ultra HDR JPEG。照片只在本机处理，原片不变。

## 使用

1. 打开 `HlgBridge.app`，拖入 `.HIF`、`.HEIF`、`.HEIC` 照片或文件夹。
2. 选择普通 JPEG、HDR JPEG 或同时导出（默认）。
3. 选择输出目录，点击「开始转换」。

普通 JPEG 适合相册、分享和打印。HDR JPEG 含普通 SDR 底图与增益图，兼容的查看器可恢复高光；不支持 HDR 的查看器显示 SDR 底图。HDR 屏幕本身不代表相册一定兼容 Ultra HDR。

- 原始尺寸、JPEG 质量 95；输出后缀 `_SDR.jpg` / `_HDR.jpg`，重名自动编号。
- 保留拍摄时间、机型和常见曝光参数，应用照片方向后将方向标记重置为 1。
- GPS 默认移除，可选保留。不会复制 MakerNotes、旧缩略图或源 HDR 容器元数据。
- SDR 原片不会制造 HDR；双输出模式仅生成普通 JPEG。
- 未知色彩先报错，只有确认原片为松下 HLG 时才启用单张「按松下 HLG 处理」。PQ、Log、RAW 和视频不在首版范围内。
- 单张失败后继续下一张。取消会在当前编解码步骤结束后生效，并清理当前图片未完成输出；已完成的其他图片保留。
- 预览为 SDR 色调映射结果，不是手机 HDR 显示模拟。队列小缩略图由系统生成。

## 构建

需要 macOS 15+、Xcode Command Line Tools（Swift 6+）、Git 和 CMake 3.15+。无须安装完整 Xcode。应用按当前 Mac 架构构建；Intel 和 Apple Silicon 应分别构建。

```sh
# 没有 CMake 时，可以安装到项目构建目录
python3 -m pip install --target .build/tools cmake==3.31.6
./Scripts/bootstrap.sh
swift run HlgChecks
./Scripts/build-app.sh
open dist/HlgBridge.app
```

产物：`dist/HlgBridge.app`、`dist/HlgBridge-macOS.zip` 和命令行工具 `dist/hlgbridge-cli`。原生库静态链接，运行时不需要 Python、CMake、Homebrew 或联网。应用仅做本地 ad-hoc 签名，不包含 Developer ID 签名、公证或 App Store 发布。

构建依赖固定为 Google libultrahdr **v2.0.2**，提交 `e5f5a022fe96fc4dc2ee35c19f733a50df807abe`；其上游构建固定 libjpeg-turbo 3.1.0。首次构建需要联网下载依赖。

### 命令行

```sh
dist/hlgbridge-cli /path/to/photos /path/to/output
dist/hlgbridge-cli /path/to/photo.HIF /path/to/output --sdr
dist/hlgbridge-cli /path/to/photo.HIF /path/to/output --hdr --keep-gps
dist/hlgbridge-cli --verify /path/to/photo_HDR.jpg
```

`--assume-hlg` 对本次任务所有未知色彩照片生效，仅在明确来源时使用。命令行批次有失败时以非零状态退出。

## 转换原理

ImageIO 读取色彩配置和拍摄信息，Core Image 以扩展线性 BT.2020、半精度浮点处理，不提前截断为 8 位。

HLG 输入通过 macOS 15 的 `CIToneMapHeadroom` 映射至 SDR，再转换为带 ICC 配置的 sRGB JPEG。HDR 路径将原始线性 HDR 像素和**已经编码的同一张 SDR JPEG**传给 libultrahdr，生成多通道增益图（1/2 分辨率，质量 95）。启用 XMP 与 ISO 21496-1 两种增益图元数据。不会将 HDR 成品再交给普通 JPEG 编码器，以免丢失增益图。

HLG 默认参考峰值为 1000 nits，线性参考白为 203 nits；优先使用 Core Image 解析出的 content headroom。SDR 色调映射是显示适配，不保证重现相机所有屏幕设置或厂商相册风格。

每张照片逐一处理、及时释放解码内存；首版拒绝超过 1 亿像素的输入。20MP HDR 编码仍可能使用数百 MB 至超过 1GB 内存。

## 验证和兼容性

测试通过独立 Swift 可执行检查器运行，不依赖仅完整 Xcode 提供的 XCTest。自动测试使用运行时生成的合成 HEIF，不包含个人照片。检查双输出、增益图解码、SDR 底图一致性、方向、Exif、GPS、未知配置、损坏文件、重名、取消和无写入权限。

| 环境 | 状态 |
|---|---|
| macOS 15.6 / Intel | 本地构建与测试环境 |
| Panasonic DC-L10 / 固件 1.2 / 10 位 BT.2100 HLG | 已确认系统解码支持；原片不入库 |
| 小米 13 / HyperOS 4.0.0.32 / 相册 5.4.2.10-0907-cn | **待实机验收，未宣称 HDR 适配成功** |
| Apple Silicon | 源码支持，待独立构建验证 |

手机验收：用不会压缩或重编码的文件传输方式复制两种 JPEG，先确认 SDR 的亮度、色彩和方向正常，再观察 HDR 成品在相册中是否触发高动态显示；同时检查拍摄日期排序。分享平台可能移除增益图，应另行验证。

## 项目结构

- `HlgCore`：检测、色彩处理、元数据和安全输出。
- `CHDR`：libultrahdr 的 C 接口封装。
- `HlgBridge`：SwiftUI 界面与批处理任务。
- `HlgCLI`：批处理和 HDR 解码验证工具。

第三方声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。个人照片、生成图片、应用包和构建缓存不提交到仓库。
