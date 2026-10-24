# HlgBridge

中文 macOS / Windows 桌面工具，将松下相机的 HLG HEIF 照片批量转换为普通 sRGB JPEG 和 Ultra HDR JPEG。照片只在本机处理，原片不变。

## 使用

1. 打开 Mac 的 `HlgBridge.app` 或 Windows 的 `HlgBridge.exe`，拖入 `.HIF`、`.HEIF`、`.HEIC` 照片或文件夹。
2. 选择普通 JPEG、HDR JPEG 或同时导出（默认）。
3. 选择 SDR 观感：默认「自然 · 保留高光」，可用 SDR 曝光补偿微调；另保留机内近似、主体明亮和系统映射。
4. 选择输出目录，点击「开始转换」。

普通 JPEG 适合相册、分享和打印。HDR JPEG 含普通 SDR 底图与增益图，兼容的查看器可恢复高光；不支持 HDR 的查看器显示 SDR 底图。HDR 屏幕本身不代表相册一定兼容 Ultra HDR。

- 原始尺寸、JPEG 质量 95；输出后缀 `_SDR.jpg` / `_HDR.jpg`，重名自动编号。
- 保留拍摄时间、机型和常见曝光参数，应用照片方向后将方向标记重置为 1。
- GPS 默认移除，可选保留。不会复制 MakerNotes、旧缩略图或源 HDR 容器元数据。
- SDR 原片不会制造 HDR；双输出模式仅生成普通 JPEG。
- 未知色彩先报错，只有确认原片为松下 HLG 时才启用单张「按松下 HLG 处理」。PQ、Log、RAW 和视频不在首版范围内。
- 单张失败后继续下一张。取消会在当前编解码步骤结束后生效，并清理当前图片未完成输出；已完成的其他图片保留。
- Mac 导入先显示文件名，后台逐项读取元数据和内嵌缩略图；不再为队列缩略图逐张解码全尺寸照片。
- 预览为 SDR 色调映射结果，不是手机 HDR 显示模拟。队列小缩略图由系统生成。

## 构建 macOS 版

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

## Windows 版（1.2.0）

支持 Windows 10（1809+）/11 x64。便携版完整解压后运行 `HlgBridge.exe`，保留同目录 `_internal` 文件夹；运行时无需安装 Python、Homebrew 或系统 HEVC 扩展。支持文件 / 文件夹拖入、批量转换、SDR 预览、取消、Exif/GPS 开关、重名自动编号和同一套应用图标。

Windows 使用 PySide6 Widgets 界面、pillow-heif/libheif 的 10/12 位解码、NumPy 浮点色彩处理，以及与 Mac 共用的 libultrahdr 原生封装。HLG 经 BT.2100 逆 OETF 与 1000-nit / gamma 1.2 的 OOTF 转到线性 BT.2020（参考白 203 nits），再执行相同的「机内转换近似」曲线；不会提前降成 8 位。两套解码器和色彩管理存在小差异，不承诺逐像素相同。

Windows 另提供「主体明亮」「保留高光」两种可移植观感；「保留高光」不调用 Apple 系统映射。Mac 界面和原有三种模式保持独立。

### 下载和自行构建

安装包统一放在 [GitHub Releases](https://github.com/Dora-z/HlgBridge/releases)。[GitHub Actions → Build Windows](https://github.com/Dora-z/HlgBridge/actions/workflows/windows.yml) 每次相关源码更新会在 Windows runner 上构建、运行测试和打包，开发构建也可在对应运行的 Artifacts 中下载。

自行构建需要 Windows、Python 3.12 x64、CMake 3.24+、Git 和 Visual Studio 2022 C++ Build Tools（含 Windows SDK），在项目根目录运行：

```powershell
./Scripts/build-windows.ps1
```

脚本在项目 `.build/windows-venv` 创建隔离环境、编译 HDR DLL、执行 11 组引擎测试，再检查源码和打包后的 Qt 应用能解码合成的 10 位 HEIF、导出双格式并恢复 HDR，以及后台批处理和窗口关闭。最终 ZIP 位于 `dist/`；无需 Python 的用户只需下载便携包。该版本未作 Windows 代码签名。

Windows 源码命令行用法（先安装 `Windows/requirements.txt` 并构建 HDR DLL）：

```powershell
$env:PYTHONPATH = "Windows"
$env:HLGBRIDGE_CODEC = "$PWD/.build/windows-native/Release/hlgcodec.dll"
python -m hlgbridge C:/Photos C:/Converted
python -m hlgbridge C:/Photos C:/Converted --mode sdr --tone camera
python -m hlgbridge C:/Converted/photo_HDR.jpg --verify
```

本机用同一张 L10 原片验证可移植引擎，机内 JPEG 对照的平均 RGB 差约 3.5/255（Mac 版为 3.6/255，同一校准样本）；两种输出均保持 5408 × 3608，HDR 增益图可完整解码。照片和参考 JPEG 不进入 GitHub 或 CI；云端只使用合成图。

### macOS 命令行

```sh
dist/hlgbridge-cli /path/to/photos /path/to/output
dist/hlgbridge-cli /path/to/photo.HIF /path/to/output --sdr --exposure -0.5
dist/hlgbridge-cli /path/to/photo.HIF /path/to/output --sdr --camera
dist/hlgbridge-cli /path/to/photo.HIF /path/to/output --sdr --standard
dist/hlgbridge-cli /path/to/photo.HIF /path/to/output --sdr --subject
dist/hlgbridge-cli /path/to/photo.HIF /path/to/output --hdr --keep-gps
dist/hlgbridge-cli --verify /path/to/photo_HDR.jpg
```

`--assume-hlg` 对本次任务所有未知色彩照片生效，仅在明确来源时使用。命令行批次有失败时以非零状态退出。

## 转换原理

ImageIO 读取色彩配置和拍摄信息，Core Image 以扩展线性 BT.2020、半精度浮点处理，不提前截断为 8 位。

HLG 的 SDR 输出提供四种观感：

- **自然 · 保留高光（默认）**：在目标线性 sRGB 色域中使用连续软肩曲线 `2Y / (1 + 2Y)`，并压缩越界的高亮色度，避免固定阈值截白。
- **机内转换近似（可选，偏亮）**：依据一组 DC-L10 HLG 与机内 JPEG 的对应像素得到经验曲线。在线性 BT.2020 中，亮度 `Y = 0.2627R + 0.6780G + 0.0593B`，目标亮度 `min(3.30Y / (1 + 2.10Y), 1)`，再以亮度比缩放 RGB。两个全局系数用于提亮主体并压缩高光，没有从单张照片拟合白平衡或颜色矩阵。室内人物照片可能偏亮，不能视为松下算法的精确复刻。
- **系统映射**：macOS 15 的 `CIToneMapHeadroom`，目标 headroom 为 1。
- **主体明亮**：系统映射后额外抬升暗部及中间调，强度可调，保持黑白端点和中性色，高亮超出色域时压缩饱和度。

四种结果都先生成线性半精度 SDR 中间图像，明确标记 headroom 为 1，再转成带 ICC 配置的 8 位 sRGB JPEG，避免从 HDR 滤镜图直接导出到 sRGB 时再次改变亮度。预览使用相同路径。-3 到 +3 EV 的曝光补偿和所有观感只影响 HLG 的 SDR 输出与 HDR 文件的 SDR 底图，不改变原始 HDR 目标像素；SDR 原片直接走正常色彩转换。

HDR 路径将原始线性 HDR 像素和**已经编码的同一张 SDR JPEG**传给 libultrahdr，生成多通道增益图（1/2 分辨率，质量 95）。启用 XMP 与 ISO 21496-1 两种增益图元数据。不会将 HDR 成品再交给普通 JPEG 编码器，以免丢失增益图。

HLG 默认参考峰值为 1000 nits，线性参考白为 203 nits；优先使用 Core Image 解析出的 content headroom。SDR 色调映射是显示适配，不保证重现相机所有屏幕设置或厂商相册风格。

每张照片逐一处理、及时释放解码内存；首版拒绝超过 1 亿像素的输入。20MP HDR 编码仍可能使用数百 MB 至超过 1GB 内存。

## 验证和兼容性

测试通过独立 Swift 可执行检查器运行，不依赖仅完整 Xcode 提供的 XCTest。自动测试使用运行时生成的合成 HEIF，不包含个人照片。目前 11 组检查覆盖双输出、增益图解码、SDR 底图一致性、方向、Exif、GPS、未知配置、损坏文件、重名、取消、无写入权限、灰阶单调、中性色、最终 JPEG/预览不会再次压暗，以及自然模式高光和曝光补偿。

| 环境 | 状态 |
|---|---|
| macOS 15.6 / Intel | 本地构建与测试环境 |
| Panasonic DC-L10 / 固件 1.2 / 10 位 BT.2100 HLG | 已确认系统解码支持；双格式全分辨率输出与 HDR 解码已验证；原片不入库 |
| 小米 13 / HyperOS 4.0.0.32 / 相册 5.4.2.10-0907-cn | **待实机验收，未宣称 HDR 适配成功** |
| Apple Silicon | 源码支持，待独立构建验证 |
| Windows 10（1809+）/11 x64 | Windows runner 编译、11 组引擎测试及打包应用自检已通过；最新构建见 Actions |

手机验收：用不会压缩或重编码的文件传输方式复制两种 JPEG，先确认 SDR 的亮度、色彩和方向正常，再观察 HDR 成品在相册中是否触发高动态显示；同时检查拍摄日期排序。分享平台可能移除增益图，应另行验证。

## 项目结构

- `HlgCore`：检测、色彩处理、元数据和安全输出。
- `CHDR`：libultrahdr 的 C 接口封装。
- `HlgBridge`：SwiftUI 界面与批处理任务。
- `HlgCLI`：Mac 批处理和 HDR 解码验证工具。
- `Windows/`：Windows 界面、可移植色彩引擎、原生 DLL 构建与测试。

第三方声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。个人照片、生成图片、应用包和构建缓存不提交到仓库。

## 为什么与相机屏幕不同？

相机屏幕上的 `MON MODE2` 表示启用了 HLG 显示辅助。松下说明 MODE2 优先主体亮度，MODE1 优先天空等高亮区域。系统默认色调映射并不等于这两种厂商显示转换。[官方说明](https://eww.pavc.panasonic.co.jp/dscoi/DC-L10/html/DC-L10_DVQP3497_eng/0100.html)

拍屏照片受相机屏幕亮度、拍摄手机曝光和白平衡影响，不能当作绝对色彩基准。这里使用同一张 HEIF 在相机内通过「回放 → 处理图像 → HEIF 转 JPEG」生成的文件进行校准。[相机转换说明](https://eww.pavc.panasonic.co.jp/dscoi/DC-L10/html/DC-L10_DVQP3497_eng/0110.html)

### 1.1 版的机内 JPEG 对照

在同一对 5408 × 3608 的原片和机内 JPEG 上，以 1200 × 801、sRGB 8 位比较完整画面的对应像素（RGB 通道平均绝对误差，范围 0–255）：

| 版本 / 模式 | 平均差值 | 95% 的通道误差不超过 |
|---|---:|---:|
| 旧版系统映射 | 68.780 | 101 |
| 旧版主体明亮 | 27.665 | 56 |
| 1.1 版机内转换近似 | 3.639 | 12 |

这是同一组校准样本的对照，不能代表其他照片的独立准确率。JPEG 量化、色度抽样、厂商处理和高光裁剪也会导致差异。两种输出均保持全分辨率，HDR 文件可完整解码，含 XMP/ISO 两种增益图标记。个人参考原片与成品不进入仓库。

可在本机对自己的图片复现比较：

```sh
swift Scripts/compare-reference.swift /path/to/camera.jpg /path/to/export_SDR.jpg
```

原生界面交互检查尚未完成（当前电脑控制权限未授予），小米相册 HDR 显示仍待实机验收。

## 应用图标

图标使用暖色光弧连接灰暗与明亮的照片卡片。源文件为 `Assets/AppIcon.png`，由内置 image_gen 生成，设计提示词保存在 `Assets/AppIcon.prompt.txt`。`Scripts/build-icon.sh` 生成 16–1024 像素的标准 macOS 图标尺寸和 `.icns`；应用构建时自动打包并写入 `CFBundleIconFile`。图标更新包含在 1.1.1 版中。

## 1.2 版：导入速度与高光修正

Mac 队列先显示全部文件名，元数据和内嵌缩略图随后更新，可以在缩略图加载期间开始转换；清空队列会取消后续加载，旧任务不会把已清空的照片加回来。本机 SD 卡目录的 39 张 HIF 实测：文件列表约 0.045 秒出现，全部元数据和内嵌缩略图约 2.8 秒完成，速度随介质变化。

默认自然模式使用柔和高光压缩，Mac 和 Windows 均支持 -3 到 +3 EV 的 SDR 曝光补偿；机内近似仍可选，但可能使室内照片偏亮。用用户反馈的室内原片检查，旧机内近似中约 9.40% 的像素三通道均达到 250/255 以上，新自然模式为 0%。这只是该样本的亮部统计，无法恢复原片中已经丢失的信息。原始 HDR 目标不受 SDR 观感和曝光补偿影响。
