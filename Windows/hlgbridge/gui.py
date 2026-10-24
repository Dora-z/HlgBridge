from __future__ import annotations
from dataclasses import replace
import io
from pathlib import Path
import sys
from PySide6.QtCore import QCoreApplication, QEvent, QObject, QRunnable, QThread, QThreadPool, Qt, Signal, Slot
from PySide6.QtGui import QCloseEvent, QDragEnterEvent, QDropEvent, QIcon, QImage, QPixmap
from PySide6.QtWidgets import (QApplication, QCheckBox, QComboBox, QFileDialog, QHBoxLayout,
    QLabel, QMainWindow, QMessageBox, QProgressBar, QPushButton, QSlider, QSplitter,
    QTreeWidget, QTreeWidgetItem, QVBoxLayout, QWidget)
from .core import Cancellation, Cancelled, Options, convert, inspect, preview, scan
from .codec import bundle_root


class BatchWorker(QObject):
    update = Signal(int, str)
    done = Signal(int, int, int)

    def __init__(self, paths, output, options, assumptions, cancellation):
        super().__init__()
        self.paths, self.output, self.options = paths, output, options
        self.assumptions, self.cancellation = assumptions, cancellation

    @Slot()
    def run(self):
        success = failed = completed = 0
        for index, path in enumerate(self.paths):
            try:
                self.cancellation.check()
                options = replace(self.options, assume_hlg=path in self.assumptions)
                files, note = convert(path, self.output, options, self.cancellation,
                                      lambda stage: self.update.emit(index, stage + "…"))
                success += 1
                self.update.emit(index, note or f"已导出 {len(files)} 个文件")
            except Cancelled:
                self.update.emit(index, "已取消")
                break
            except Exception as exc:
                failed += 1
                self.update.emit(index, f"失败：{exc}")
            completed += 1
        self.done.emit(success, failed, completed)


class PreviewSignals(QObject):
    ready = Signal(int, bytes, str)


class PreviewTask(QRunnable):
    def __init__(self, request, path, options):
        super().__init__()
        self.signals = PreviewSignals()
        self.request, self.path, self.options = request, path, options
        self.cancelled = False

    def run(self):
        if self.cancelled:
            return
        try:
            image = preview(self.path, self.options)
            data = io.BytesIO()
            image.save(data, format="PNG")
            self.signals.ready.emit(self.request, data.getvalue(), "SDR 预览 · 导出保留原始尺寸")
        except Exception as exc:
            self.signals.ready.emit(self.request, b"", str(exc))


class Window(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("HlgBridge · Windows")
        self.resize(1120, 780)
        self.setMinimumSize(850, 680)
        self.setAcceptDrops(True)
        icon = bundle_root() / "Assets" / "AppIcon.ico"
        self.setWindowIcon(QIcon(str(icon if icon.is_file() else icon.with_suffix(".png"))))
        self.paths: list[Path] = []
        self.assumptions: set[Path] = set()
        self.running = False
        self.closing = False
        self.output: Path | None = None
        self.pixmap = None
        self.preview_id = 0
        self.preview_task = None
        self.pool = QThreadPool(self)
        self.pool.setMaxThreadCount(1)
        root = QWidget()
        self.setCentralWidget(root)
        layout = QVBoxLayout(root)
        layout.setContentsMargins(24, 20, 24, 20)
        header = QHBoxLayout()
        title = QLabel("HlgBridge")
        title.setStyleSheet("font-size: 28px; font-weight: 650;")
        header.addWidget(title)
        header.addStretch()
        header.addWidget(QLabel("照片仅在本机处理"))
        layout.addLayout(header)
        subtitle = QLabel("让 HLG 照片，在更多屏幕上自然呈现")
        subtitle.setStyleSheet("color: #737373; margin-bottom: 12px;")
        layout.addWidget(subtitle)
        split = QSplitter()
        layout.addWidget(split, 1)
        left = QWidget()
        left_layout = QVBoxLayout(left)
        left_layout.setContentsMargins(0, 0, 12, 0)
        buttons = QHBoxLayout()
        self.add_button = QPushButton("添加照片…")
        self.folder_button = QPushButton("添加文件夹…")
        self.clear_button = QPushButton("清空")
        for button in [self.add_button, self.folder_button, self.clear_button]:
            buttons.addWidget(button)
        left_layout.addLayout(buttons)
        self.tree = QTreeWidget()
        self.tree.setHeaderLabels(["照片", "色彩 / 尺寸", "状态"])
        self.tree.setColumnWidth(0, 130)
        self.tree.setColumnWidth(1, 160)
        self.tree.setRootIsDecorated(False)
        self.tree.setAlternatingRowColors(True)
        self.tree.setToolTip("也可直接拖入 HIF、HEIF、HEIC 照片或文件夹")
        left_layout.addWidget(self.tree)
        left_layout.addWidget(QLabel("支持 HIF · HEIF · HEIC，可拖入文件夹"))
        split.addWidget(left)
        right = QWidget()
        right_layout = QVBoxLayout(right)
        right_layout.setContentsMargins(12, 0, 0, 0)
        self.canvas = QLabel("拖入照片，然后选择一张预览")
        self.canvas.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.canvas.setMinimumHeight(220)
        self.canvas.setStyleSheet("background: #171a20; color: #a6abb4; border-radius: 12px;")
        right_layout.addWidget(self.canvas, 1)
        self.preview_status = QLabel("SDR 预览，不模拟手机 HDR 显示")
        self.preview_status.setWordWrap(True)
        right_layout.addWidget(self.preview_status)
        self.assume = QCheckBox("按松下 HLG 处理所选照片（确认来源后启用）")
        right_layout.addWidget(self.assume)
        self.tone = QComboBox()
        for label, value in [("自然 · 保留高光（默认）", "natural"), ("机内转换近似（偏亮）", "camera"), ("主体明亮", "subject"), ("保留高光", "highlight")]:
            self.tone.addItem(label, value)
        right_layout.addWidget(QLabel("SDR 观感"))
        right_layout.addWidget(self.tone)
        strength_row = QHBoxLayout()
        self.strength_label = QLabel("主体提亮 65%")
        self.strength = QSlider(Qt.Orientation.Horizontal)
        self.strength.setRange(0, 100)
        self.strength.setValue(65)
        strength_row.addWidget(self.strength_label)
        strength_row.addWidget(self.strength)
        right_layout.addLayout(strength_row)
        self.strength.setEnabled(False)
        exposure_row = QHBoxLayout()
        self.exposure_label = QLabel("SDR 曝光 +0.0 EV")
        self.exposure = QSlider(Qt.Orientation.Horizontal)
        self.exposure.setRange(-30, 30)
        self.exposure_reset = QPushButton("重置")
        exposure_row.addWidget(self.exposure_label)
        exposure_row.addWidget(self.exposure)
        exposure_row.addWidget(self.exposure_reset)
        right_layout.addLayout(exposure_row)
        description = QLabel("自然模式柔和压缩亮部；机内近似基于单张室外照片，室内可能偏亮。")
        description.setWordWrap(True)
        description.setStyleSheet("color: #737373; font-size: 12px;")
        right_layout.addWidget(description)
        self.mode = QComboBox()
        for label, value in [("同时导出普通 / HDR JPEG", "both"), ("普通 JPEG", "sdr"), ("HDR JPEG", "hdr")]:
            self.mode.addItem(label, value)
        right_layout.addWidget(QLabel("输出格式"))
        right_layout.addWidget(self.mode)
        output_row = QHBoxLayout()
        self.output_label = QLabel("尚未选择输出目录")
        self.output_label.setWordWrap(True)
        self.output_button = QPushButton("选择目录…")
        output_row.addWidget(self.output_label, 1)
        output_row.addWidget(self.output_button)
        right_layout.addLayout(output_row)
        self.gps = QCheckBox("保留 GPS 位置（默认移除）")
        right_layout.addWidget(self.gps)
        right_layout.addWidget(QLabel("原始尺寸 · JPEG 质量 95 · 保留原片"))
        split.addWidget(right)
        split.setSizes([470, 600])
        footer = QHBoxLayout()
        self.status = QLabel("所有照片仅在本机处理")
        self.status.setWordWrap(True)
        footer.addWidget(self.status, 1)
        self.start_button = QPushButton("开始转换")
        self.start_button.setObjectName("primary")
        self.start_button.setEnabled(False)
        self.cancel_button = QPushButton("取消")
        self.cancel_button.setEnabled(False)
        footer.addWidget(self.cancel_button)
        footer.addWidget(self.start_button)
        layout.addLayout(footer)
        self.progress = QProgressBar()
        self.progress.setValue(0)
        layout.addWidget(self.progress)
        self.add_button.clicked.connect(self.choose_files)
        self.folder_button.clicked.connect(self.choose_folder)
        self.clear_button.clicked.connect(self.clear)
        self.output_button.clicked.connect(self.choose_output)
        self.tree.currentItemChanged.connect(self.selected)
        self.tone.currentIndexChanged.connect(self.tone_changed)
        self.strength.valueChanged.connect(lambda value: self.strength_label.setText(f"主体提亮 {value}%"))
        self.strength.sliderReleased.connect(self.update_preview)
        self.exposure.valueChanged.connect(lambda value: self.exposure_label.setText(f"SDR 曝光 {value / 10:+.1f} EV"))
        self.exposure.sliderReleased.connect(self.update_preview)
        self.exposure_reset.clicked.connect(self.reset_exposure)
        self.assume.toggled.connect(self.assume_changed)
        self.start_button.clicked.connect(self.run_batch)
        self.cancel_button.clicked.connect(self.cancel)

    def options(self):
        return Options(mode=self.mode.currentData(), tone=self.tone.currentData(),
                       strength=self.strength.value() / 100, exposure=self.exposure.value() / 10, keep_gps=self.gps.isChecked())

    def reset_exposure(self):
        self.exposure.setValue(0)
        self.update_preview()

    def choose_files(self):
        paths, _ = QFileDialog.getOpenFileNames(self, "选择照片", "", "HEIF 照片 (*.hif *.heif *.heic *.HIF *.HEIF *.HEIC)")
        self.add_paths(paths)

    def choose_folder(self):
        path = QFileDialog.getExistingDirectory(self, "选择照片文件夹")
        if path:
            self.add_paths([path])

    def choose_output(self):
        path = QFileDialog.getExistingDirectory(self, "选择输出目录")
        if path:
            self.output = Path(path)
            self.output_label.setText(path)
            self.refresh_controls()

    def add_paths(self, values):
        if self.running:
            return
        known = set(self.paths)
        for path in scan(values):
            if path in known:
                continue
            known.add(path)
            try:
                info = inspect(path)
                label = f"{info.profile} · {info.size[0]} × {info.size[1]}"
                state = "等待转换"
            except Exception as exc:
                label, state = "无法读取", f"失败：{exc}"
            row = QTreeWidgetItem([path.name, label, state])
            row.setToolTip(0, str(path))
            row.setData(0, Qt.ItemDataRole.UserRole, path)
            self.tree.addTopLevelItem(row)
            self.paths.append(path)
        self.status.setText(f"已加入 {len(self.paths)} 张照片")
        self.refresh_controls()
        if self.tree.currentItem() is None and self.paths:
            self.tree.setCurrentItem(self.tree.topLevelItem(0))

    def clear(self):
        self.preview_id += 1
        if self.preview_task:
            self.preview_task.cancelled = True
        self.paths.clear()
        self.assumptions.clear()
        self.tree.clear()
        self.pixmap = None
        self.canvas.clear()
        self.canvas.setText("拖入照片，然后选择一张预览")
        self.preview_status.setText("SDR 预览，不模拟手机 HDR 显示")
        self.refresh_controls()

    def selected(self, *_):
        row = self.tree.currentItem()
        self.assume.blockSignals(True)
        self.assume.setChecked(bool(row and row.data(0, Qt.ItemDataRole.UserRole) in self.assumptions))
        self.assume.blockSignals(False)
        self.update_preview()

    def assume_changed(self, enabled):
        row = self.tree.currentItem()
        if row:
            path = row.data(0, Qt.ItemDataRole.UserRole)
            self.assumptions.add(path) if enabled else self.assumptions.discard(path)
            self.update_preview()

    def tone_changed(self):
        self.strength.setEnabled(not self.running and self.tone.currentData() == "subject")
        self.update_preview()

    def update_preview(self):
        row = self.tree.currentItem()
        if not row:
            return
        self.preview_id += 1
        if self.preview_task:
            self.preview_task.cancelled = True
        path = row.data(0, Qt.ItemDataRole.UserRole)
        options = replace(self.options(), assume_hlg=path in self.assumptions)
        task = PreviewTask(self.preview_id, path, options)
        task.signals.ready.connect(self.preview_ready)
        self.preview_task = task
        self.preview_status.setText("正在生成预览…")
        self.pool.start(task)

    @Slot(int, bytes, str)
    def preview_ready(self, request, data, message):
        if request != self.preview_id:
            return
        self.preview_status.setText(message)
        if data:
            self.pixmap = QPixmap.fromImage(QImage.fromData(data))
            self.show_pixmap()
            row = self.tree.currentItem()
            if row:
                row.setIcon(0, QIcon(self.pixmap))
        else:
            self.pixmap = None
            self.canvas.setText("无法生成预览")

    def show_pixmap(self):
        if self.pixmap:
            self.canvas.setPixmap(self.pixmap.scaled(self.canvas.size(), Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation))

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.show_pixmap()

    def refresh_controls(self):
        for control in [self.add_button, self.folder_button, self.clear_button, self.tone, self.mode,
                        self.output_button, self.gps, self.assume, self.exposure, self.exposure_reset]:
            control.setEnabled(not self.running)
        self.strength.setEnabled(not self.running and self.tone.currentData() == "subject")
        self.start_button.setEnabled(not self.running and bool(self.paths) and self.output is not None)
        self.cancel_button.setEnabled(self.running)

    def run_batch(self):
        if self.running or self.output is None:
            return
        self.running = True
        self.refresh_controls()
        self.progress.setRange(0, len(self.paths))
        self.progress.setValue(0)
        self.cancellation = Cancellation()
        self.thread = QThread(self)
        self.worker = BatchWorker(list(self.paths), self.output, self.options(), set(self.assumptions), self.cancellation)
        self.worker.moveToThread(self.thread)
        self.thread.started.connect(self.worker.run)
        self.worker.update.connect(self.batch_update)
        self.worker.done.connect(self.batch_done)
        self.worker.done.connect(self.thread.quit)
        self.worker.done.connect(self.worker.deleteLater)
        self.thread.finished.connect(self.thread_finished)
        self.thread.start()

    @Slot(int, str)
    def batch_update(self, index, message):
        self.tree.topLevelItem(index).setText(2, message)
        self.status.setText(f"{index + 1} / {len(self.paths)} · {message}")
        self.progress.setValue(index)

    @Slot(int, int, int)
    def batch_done(self, success, failed, completed):
        self.progress.setValue(completed)
        self.status.setText(f"完成 {success} 张 · 失败 {failed} 张 · 未处理 {len(self.paths) - completed} 张")

    @Slot()
    def thread_finished(self):
        thread = self.thread
        thread.wait()
        self.thread = None
        self.worker = None
        thread.deleteLater()
        self.running = False
        self.refresh_controls()
        if self.closing:
            self.close()

    def cancel(self):
        if self.running:
            self.cancellation.cancel()
            self.status.setText("正在取消，等待当前编解码步骤结束…")
            self.cancel_button.setEnabled(False)

    def closeEvent(self, event: QCloseEvent):
        if self.running:
            self.closing = True
            self.cancel()
            event.ignore()
        else:
            if self.preview_task:
                self.preview_task.cancelled = True
            self.pool.waitForDone()
            event.accept()

    def dragEnterEvent(self, event: QDragEnterEvent):
        if not self.running and event.mimeData().hasUrls():
            event.acceptProposedAction()

    def dropEvent(self, event: QDropEvent):
        self.add_paths(url.toLocalFile() for url in event.mimeData().urls() if url.isLocalFile())
        event.acceptProposedAction()


_application = None

def create_application():
    global _application
    app = QApplication.instance() or QApplication(sys.argv)
    _application = app
    app.setApplicationName("HlgBridge")
    app.setStyle("Fusion")
    app.setStyleSheet("""
        QWidget { font-family: 'Segoe UI', 'Microsoft YaHei UI', sans-serif; font-size: 13px; }
        QMainWindow { background: #f7f6f2; }
        QPushButton { padding: 7px 14px; border: 1px solid #d3d3d3; border-radius: 6px; background: white; }
        QPushButton:hover { background: #fff0df; }
        QPushButton:disabled { color: #aaa; background: #eee; }
        QPushButton#primary { background: #ed862b; color: white; border-color: #ed862b; font-weight: bold; }
        QComboBox { padding: 6px; border: 1px solid #d3d3d3; border-radius: 5px; background: white; }
        QTreeWidget { border: 1px solid #ddd; border-radius: 8px; background: white; alternate-background-color: #faf9f7; }
        QProgressBar { border: 1px solid #ddd; border-radius: 3px; text-align: center; max-height: 15px; }
        QProgressBar::chunk { background: #ed862b; }
    """)
    return app


def main():
    app = create_application()
    window = Window()
    window.show()
    result = app.exec()
    dispose_window(window, app)
    return result


def dispose_window(window, app):
    """Destroy widgets and join workers while QApplication is still alive."""
    window.pool.waitForDone()
    window.close()
    window.deleteLater()
    QCoreApplication.sendPostedEvents(None, QEvent.Type.DeferredDelete)
    app.processEvents()
