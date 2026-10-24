# 第三方依赖

## Google libultrahdr

- 来源：https://github.com/google/libultrahdr
- 版本：v2.0.2 / e5f5a022fe96fc4dc2ee35c19f733a50df807abe
- Copyright The Android Open Source Project
- 上游提供 Apache-2.0 或 MIT 双许可证。本项目分发时包含两份上游许可证。

## libjpeg-turbo

- 来源：https://github.com/libjpeg-turbo/libjpeg-turbo
- 版本：3.1.0（由上述 libultrahdr 构建固定）
- 上游采用 IJG、BSD 风格及 zlib 等许可证，具体适用范围见其 LICENSE.md 和 README.ijg。
- 二进制包的 Contents/Resources/Licenses 包含完整上游声明。

Apple 的 SwiftUI、Core Image、ImageIO 和 ColorSync 是系统框架，不随本项目重新分发。


## Windows 版依赖

- PySide6-Essentials / Qt / shiboken6 6.12.0：https://doc.qt.io/qtforpython-6/licenses.html，动态库随应用分发，包含上游 LGPL/GPL/商业授权选项及组件声明；本项目未修改 Qt。
- Pillow 13.0.0：https://github.com/python-pillow/Pillow（HPND / MIT-CMU 等上游声明）。
- pillow-heif 1.8.1：https://github.com/bigcat88/pillow_heif（BSD-3-Clause）；wheel 包含 libheif 及 HEVC 编解码组件，其各自许可证以 wheel 内附声明为准。源码：https://github.com/strukturag/libheif、https://github.com/strukturag/libde265、https://bitbucket.org/multicoreware/x265_git。
- NumPy 2.3.5：https://github.com/numpy/numpy（BSD-3-Clause 及 wheel 内附组件声明）。
- piexif 1.1.3：https://github.com/hMatoba/Piexif（MIT）。
- PyInstaller 6.22.3：https://github.com/pyinstaller/pyinstaller（GPL-2.0-or-later，带应用分发例外；仅用于打包）。

Windows 便携包的 `_internal/Licenses` 收集所安装发行包的原始许可证及 libultrahdr / libjpeg-turbo 声明。对应上游源码链接见上文；动态库可在解压目录中替换。确切依赖版本见 `Windows/requirements*.txt`。
