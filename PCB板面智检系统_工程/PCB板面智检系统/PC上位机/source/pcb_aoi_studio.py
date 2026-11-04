"""PCB AOI Studio 1.0: SCAM live receiver, reference inspection and PCB viewing."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from dataclasses import asdict
from datetime import datetime
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import queue
import sys
import time
import traceback

import cv2
import numpy as np
from PySide6.QtCore import Qt, QTimer, QRectF
from PySide6.QtGui import QColor, QFont, QFontDatabase, QImage, QPainter, QPen
from PySide6.QtWidgets import (QApplication, QCheckBox, QComboBox, QDoubleSpinBox,
    QFileDialog, QFormLayout, QGroupBox, QHBoxLayout, QLabel, QLineEdit, QMainWindow,
    QMessageBox, QProgressBar, QPushButton, QScrollArea, QSlider, QSpinBox,
    QSplitter, QTabWidget, QTableWidget, QTableWidgetItem, QVBoxLayout, QWidget,
    QHeaderView, QSizePolicy)

from camera_core import Receiver, Settings, Frame
from cooperative_link import CooperativeReceiver
from image_enhance import Enhancer, MODES
from inspection import Parameters, BoardSession
from pcb_aoi_core import TemplateMatcher

VERSION = '1.6.0'
STATE_NAMES = {'ok': 'OK', 'ng': 'NG', 'review': '待复核', 'invalid': '检测无效'}


def atomic_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix+'.tmp')
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    temp.replace(path)


def write_png(path, bgr):
    ok, buf = cv2.imencode('.png', bgr)
    if not ok:
        raise OSError('PNG 编码失败')
    Path(path).write_bytes(buf.tobytes())


def template_valid(tm):
    if (tm.tpl is None or tm.ref_bgr is None or tm.S.shape != (3, 3)
            or not np.isfinite(tm.S).all() or abs(np.linalg.det(tm.S)) < 1e-12
            or tm.tpl.shape[:2] != tm.mask.shape
            or tm.tpl.shape[1] != 1180 or not (200 <= tm.canon_h <= 1400)
            or not tm.core.any()):
        raise ValueError('模板数据不完整或板面掩膜无效，请重新标定')
    return tm


class CompactStatus(QLabel):
    """Keep complete status text available while reserving one compact row."""
    def __init__(self, text='', parent=None):
        super().__init__(parent)
        self.setWordWrap(False)
        self.setMinimumWidth(0)
        self.setSizePolicy(QSizePolicy.Policy.Ignored, QSizePolicy.Policy.Preferred)
        self.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        self.setText(text)

    def setText(self, text):
        super().setText(text)
        self.setToolTip(text)


class OperationProgress(QProgressBar):
    def setFormat(self, text):
        super().setFormat(text)
        self.setVisible(text not in ('实时预览', '等待操作'))


class ImageView(QWidget):
    def __init__(self):
        super().__init__()
        self.setMinimumSize(360, 260)
        self.image = None
        self.regions = []
        self.boxes = True
        self.confirmed_boxes = []
        self.focus_roi = None

    def set_image(self, rgb, regions, boxes, confirmed_boxes=()):
        rgb = np.ascontiguousarray(rgb)
        self.image = QImage(rgb.data, rgb.shape[1], rgb.shape[0], rgb.strides[0],
                            QImage.Format.Format_RGB888).copy()
        self.regions, self.boxes = regions, boxes
        self.confirmed_boxes = confirmed_boxes
        self.update()

    def paintEvent(self, event):
        p = QPainter(self)
        p.fillRect(self.rect(), QColor('#080f1b'))
        if self.image is None:
            p.setPen(QColor('#a4b6cc'))
            p.drawText(self.rect(), Qt.AlignmentFlag.AlignCenter,
                       '等待图像')
            return
        w, h = self.image.width(), self.image.height()
        scale = min(self.width()/w, self.height()/h)
        ox, oy = (self.width()-w*scale)/2, (self.height()-h*scale)/2
        p.drawImage(QRectF(ox, oy, w*scale, h*scale), self.image)
        if self.focus_roi:
            x,y,rw,rh=self.focus_roi
            p.setPen(QPen(QColor('#38bdf8'),2,Qt.PenStyle.DashLine))
            p.drawRect(QRectF(ox+x*w*scale,oy+y*h*scale,rw*w*scale,rh*h*scale))
            p.drawText(int(ox+x*w*scale),max(14,int(oy+y*h*scale)-5),'AF ROI')
        if self.boxes:
            p.setFont(QFont('Microsoft YaHei', 10))
            for i, region in enumerate(self.regions, 1):
                confirmed = any(max(abs(a-b) for a, b in zip(region.bbox, box)) < 2
                                for box in self.confirmed_boxes)
                p.setPen(QPen(QColor('#ff6464' if confirmed else '#ffbf55'), 2))
                x1, y1, x2, y2 = region.bbox
                p.drawRect(QRectF(ox+x1*scale, oy+y1*scale, (x2-x1)*scale, (y2-y1)*scale))
                p.drawText(int(ox+x1*scale), max(14, int(oy+y1*scale)-5),
                           f'{"确认" if confirmed else "候选"} {i} '+({'scratch':'细线','material':'材质','structure':'局部结构'}.get(getattr(region,'kind','legacy'),'')))


class Studio(QMainWindow):
    def __init__(self, data_dir, bind=None, port=None, source=None, listen=True, template=None,
                 require_control=None, remote_port=None, receiver_factory=None):
        super().__init__()
        self.root = Path(data_dir)
        self.root.mkdir(parents=True, exist_ok=True)
        for name in ['templates', 'records', 'exports']:
            (self.root/name).mkdir(exist_ok=True)
        try:
            self.saved = json.loads((self.root/'settings.json').read_text(encoding='utf-8'))
        except (OSError, ValueError):
            self.saved = {}
        self.require_control_setting=require_control
        self.receiver_factory=receiver_factory or Receiver
        self.remote_port_setting=remote_port
        self._capture_blocked=False
        self.tm = None
        self.template_path = None
        self.template_hash = ''
        self.frames = queue.Queue(maxsize=2)
        self.rx = None
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix='aoi-algorithm')
        self.pending = None
        self.generation = 0
        self.mode = 'preview'
        self.session = None
        self.current = None
        self.shown = None
        self.last_result = None
        self.last_submitted = None
        self.cal_tm = None
        self.cal_need = 15
        self.cal_deadline = 0
        self.processing_ms = 0.0
        self.inspected_frames = 0
        self.cal_info = None
        self.learn_tm = None
        self.learn_path = None
        self.closed = False
        self.recorded = set()
        self.enhancer = Enhancer()
        self.last_render = 0.0
        self.setWindowTitle(f'PCB AOI Studio {VERSION} · FPGA采集 / PC检测')
        self.resize(1440, 900)
        self.setMinimumSize(960, 640)
        self._build_ui(bind, port, source)
        self.parameter_timer = QTimer(self)
        self.parameter_timer.setSingleShot(True)
        self.parameter_timer.setInterval(450)
        self.parameter_timer.timeout.connect(self._parameters_applied)
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.tick)
        self.timer.start(50)
        if listen:
            self.start_receiver()
        wanted = template or self.saved.get('template')
        if wanted:
            wanted=Path(wanted)
            if not wanted.is_absolute():wanted=self.root/wanted
            if not wanted.is_file():wanted=self.root/'templates'/wanted.name
            if wanted.is_file():self._request_load(wanted)
        self.refresh_controls()

    def _button(self, text, callback, name=''):
        button = QPushButton(text)
        if name:
            button.setObjectName(name)
        button.clicked.connect(callback)
        return button

    def _number(self, value, low, high, step=1, decimals=0):
        number = QDoubleSpinBox() if decimals else QSpinBox()
        if decimals:
            number.setDecimals(decimals)
        number.setRange(low, high)
        number.setSingleStep(step)
        number.setValue(value)
        number.setMinimumWidth(100)
        return number

    def _build_ui(self, bind, port, source):
        center = QWidget()
        outer = QVBoxLayout(center)
        outer.setContentsMargins(10, 8, 10, 6)
        outer.setSpacing(6)
        # Keep capture guard and algorithm status objects for their original
        # update paths; long setup explanations no longer occupy preview space.
        self.capture_label = QLabel(center)
        self.capture_label.hide()
        self.algorithm_label = QLabel(center)
        self.algorithm_label.hide()
        bar = QHBoxLayout()
        bar.setSpacing(6)
        self.cal_button = self._button('标定模板', self.calibrate_clicked, 'primary')
        self.start_button = self._button('开始检测', self.start_inspection, 'success')
        self.start_button.setMinimumWidth(112)
        self.stop_button = self._button('停止 / 预览', self.stop_operation)
        self.load_button = self._button('加载模板', self.choose_template)
        self.export_button = self._button('保存画面', self.export_clicked)
        for button in [self.cal_button, self.start_button, self.stop_button, self.load_button, self.export_button]:
            bar.addWidget(button)
        bar.addStretch()
        self.link = CompactStatus('未连接')
        self.link.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
        self.link.setMaximumWidth(330)
        bar.addWidget(self.link, 1)
        self.parameters_button = QPushButton('收起参数')
        self.parameters_button.setToolTip('显示或收起检测参数、模板与接收设置')
        self.parameters_button.setCheckable(True)
        self.parameters_button.setChecked(True)
        self.parameters_button.toggled.connect(self._toggle_parameters)
        bar.addWidget(self.parameters_button)
        outer.addLayout(bar)
        self.verdict = CompactStatus('预览 · 请标定或加载模板')
        self.verdict.setObjectName('verdict')
        self.verdict.setFixedHeight(34)
        outer.addWidget(self.verdict)
        split = QSplitter(Qt.Orientation.Horizontal)
        self.preview_splitter = split
        split.setChildrenCollapsible(False)
        left = QWidget()
        ll = QVBoxLayout(left)
        ll.setContentsMargins(0, 0, 0, 0)
        ll.setSpacing(6)
        self.frame_caption = CompactStatus('实时预览')
        self.frame_caption.hide()
        self.view = ImageView()
        ll.addWidget(self.view, 1)
        viewbar = QHBoxLayout()
        viewbar.addWidget(QLabel('观察模式'))
        self.view_mode = QComboBox()
        for key, label in MODES.items():
            self.view_mode.addItem(label, key)
        index = self.view_mode.findData(self.saved.get('view_mode', 'detail'))
        self.view_mode.setCurrentIndex(max(0, index))
        viewbar.addWidget(self.view_mode)
        viewbar.addWidget(QLabel('强度'))
        self.strength = QSlider(Qt.Orientation.Horizontal)
        self.strength.setRange(1, 7)
        self.strength.setValue(max(1, min(7, int(self.saved.get('strength', 3)))))
        self.strength.setMaximumWidth(150)
        viewbar.addWidget(self.strength)
        self.strength_label = QLabel(str(self.strength.value()))
        viewbar.addWidget(self.strength_label)
        self.compare = QCheckBox('原图对照')
        self.compare.setChecked(bool(self.saved.get('compare', False)))
        self.show_boxes = QCheckBox('候选框')
        self.show_boxes.setChecked(True)
        self.show_coverage = QCheckBox('覆盖区')
        self.show_coverage.setChecked(bool(self.saved.get('show_coverage', True)))
        viewbar.addWidget(self.compare)
        viewbar.addWidget(self.show_boxes)
        viewbar.addWidget(self.show_coverage)
        viewbar.addStretch()
        viewbar.addWidget(self.frame_caption, 1)
        self.frame_caption.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
        self.frame_caption.show()
        ll.addLayout(viewbar)
        self.progress = OperationProgress()
        self.progress.setFixedHeight(18)
        self.progress.setRange(0, 1000)
        self.progress.setValue(0)
        self.progress.setFormat('等待操作')
        ll.addWidget(self.progress)
        self.image_stats = QLabel('增强仅影响观察和增强图导出；检测始终使用原始帧及模板绑定的预处理。')
        self.image_stats.setWordWrap(True)
        self.image_stats.setStyleSheet("color:#92a9c2; font-size:11px;")
        split.addWidget(left)
        tabs = QTabWidget()
        self.option_tabs = tabs
        tabs.setMinimumWidth(310)
        tabs.setMaximumWidth(370)
        options = QWidget()
        ol = QVBoxLayout(options)
        group = QGroupBox('单帧差分阈值')
        form = QFormLayout(group)
        self.automatic = QCheckBox('自动阈值')
        self.automatic.setToolTip('中位数 + k × MAD；k 越大，候选越少')
        self.automatic.setChecked(self.saved.get('automatic', True))
        form.addRow(self.automatic)
        self.k = self._number(self.saved.get('k', 6.5), .1, 20, .5, 1)
        self.threshold = self._number(self.saved.get('threshold', 25), 1, 255, 1, 1)
        self.area = self._number(self.saved.get('min_area', 120), 1, 100000, 20)
        self.peak = self._number(self.saved.get('min_peak', 16), 0, 255, 1, 1)
        for label, widget in [('灵敏度 k', self.k), ('手动差分阈值', self.threshold),
                              ('最小面积（px）', self.area), ('最小差异峰值', self.peak)]:
            form.addRow(label, widget)
        note = QLabel('k / 阈值越大，候选越少；降低可能增加误报。')
        note.setWordWrap(True)
        form.addRow(note)
        ol.addWidget(group)
        group = QGroupBox('本板时序确认')
        form = QFormLayout(group)
        self.window = self._number(self.saved.get('window_s', 20), 2, 180, 1, 1)
        self.confirm = self._number(self.saved.get('confirm_s', 15), 1, 179, 1, 1)
        self.confirm_area = self._number(self.saved.get('confirm_area', 160), 1, 100000, 20)
        self.confirm_peak = self._number(self.saved.get('confirm_peak', 22), 0, 255, 1, 1)
        for label, widget in [('有效观察（秒）', self.window), ('确认持续（秒）', self.confirm),
                              ('确认面积（px）', self.confirm_area), ('确认最小峰值', self.confirm_peak)]:
            form.addRow(label, widget)
        note = QLabel('换板后请再次点击“开始检测”。每次点击都会清空上一板结果。')
        note.setWordWrap(True)
        form.addRow(note)
        ol.addWidget(group)
        self.metrics = QLabel('当前候选 0 处 · 本板确认 0 处\n有效帧 0 · 无效帧 0')
        self.metrics.setWordWrap(True)
        ol.addWidget(self.metrics)
        self.table = QTableWidget(0, 4)
        self.table.setHorizontalHeaderLabels(['持续 s', '命中', '面积', '峰值'])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        self.table.verticalHeader().hide()
        self.table.setMinimumHeight(90)
        self.table.setMaximumHeight(180)
        ol.addWidget(self.table)
        ol.addWidget(self.image_stats)
        ol.addStretch()
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setWidget(options)
        tabs.addTab(scroll, '检测')
        management = QWidget()
        ml = QVBoxLayout(management)
        group = QGroupBox('模板标定')
        form = QFormLayout(group)
        self.template_name = QLineEdit('F103_正面')
        self.cal_count = self._number(15, 5, 60, 5)
        form.addRow('模板名称 / 板面', self.template_name)
        form.addRow('采集有效帧', self.cal_count)
        self.template_label = QLabel('尚未标定 / 加载模板')
        self.template_label.setWordWrap(True)
        form.addRow(self.template_label)
        self.template_thumb = QLabel()
        self.template_thumb.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.template_thumb.setMinimumHeight(120)
        form.addRow(self.template_thumb)
        form.addRow(self._button('另存模板', self.save_template_as))
        self.good_button = self._button('添加另一块良品样本（5 帧）', self.learn_clicked)
        self.clear_good_button = self._button('清空正常波动样本', self.clear_learning)
        form.addRow(self.good_button)
        form.addRow(self.clear_good_button)
        ml.addWidget(group)
        group = QGroupBox('图像接收（以太网 / 后续无线）')
        form = QFormLayout(group)
        self.bind = QComboBox()
        self.bind.setEditable(True)
        self.bind.addItems(['0.0.0.0', '192.168.137.1'])
        self.bind.setCurrentText(bind or self.saved.get('bind', '192.168.137.1'))
        self.port = self._number(port or self.saved.get('port', 16001), 1, 65535)
        self.source = QLineEdit(source if source is not None else self.saved.get('source', '' if self.require_control_setting is False else '192.168.137.2'))
        self.source.setPlaceholderText('FPGA 地址，例如 192.168.137.2')
        form.addRow('本机监听地址', self.bind)
        form.addRow('UDP 端口', self.port)
        form.addRow('FPGA 地址', self.source)
        self.remote_port=self._number(self.remote_port_setting or self.saved.get('remote_port',6002),1,65535)
        form.addRow('FPGA 端口',self.remote_port)
        self.manage_capture=QCheckBox('自动关闭 FPGA 独立检测（推荐）')
        self.manage_capture.setChecked(self.saved.get('require_control',False) if self.require_control_setting is None else self.require_control_setting)
        form.addRow(self.manage_capture)
        form.addRow(self._button('应用并重新接收', self.start_receiver))
        text = QLabel('自动模式会握手、停止板端检测、切到相机模式，并确认实时源帧更新。仅旧纯图传固件或离线回放可取消自动管理。无线桥接仍需实际验证。')
        text.setWordWrap(True)
        form.addRow(text)
        ml.addWidget(group)
        self.record_label = QLabel('结果自动保存到 data/records；模板自动保存到 data/templates。')
        self.record_label.setWordWrap(True)
        ml.addWidget(self.record_label)
        ml.addStretch()
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setWidget(management)
        tabs.addTab(scroll, '模板 / 接收')
        suppression = QWidget()
        sl = QVBoxLayout(suppression)
        group = QGroupBox('绿油板颜色兼容 · 实验功能')
        form = QFormLayout(group)
        self.surface_mode = QCheckBox('启用颜色兼容')
        self.surface_mode.setToolTip('允许铜箔黄/灰及绿油深浅差异，分开检测细线与材质变化')
        self.surface_mode.setChecked(self.saved.get('surface_mode', True))
        form.addRow(self.surface_mode)
        self.scratch_min_length = self._number(self.saved.get('scratch_min_length',18),8,200,1,1)
        self.scratch_response = self._number(self.saved.get('scratch_response',2.5),.5,30,.25,2)
        self.small_structure_response=self._number(self.saved.get('small_structure_response',12),3,100,1,1)
        self.structure_tolerance = self._number(self.saved.get('structure_tolerance',2),0,8,1)
        self.mask_mount_holes = QCheckBox('屏蔽安装孔内部')
        self.mask_mount_holes.setToolTip('排除自动定位的角部安装孔内部，检测覆盖区可见')
        self.mask_mount_holes.setChecked(self.saved.get('mask_mount_holes',True))
        form.addRow('细线长度（px）',self.scratch_min_length)
        form.addRow('细线响应',self.scratch_response)
        form.addRow('细小异物响应',self.small_structure_response)
        form.addRow('边缘容差（px）',self.structure_tolerance)
        form.addRow(self.mask_mount_holes)
        note = QLabel('兼容模式不把单纯色差直接判NG。线状异常按长度/连续性确认，不受块状异物面积门槛限制。仅以变色表现的污染、结构边缘附近细线仍需人工复核；孔内部不参与表面检验。关闭后恢复传统灰度算法。')
        note.setWordWrap(True);form.addRow(note);sl.addWidget(group)
        group = QGroupBox('边缘与配准')
        form = QFormLayout(group)
        self.edge_margin = self._number(self.saved.get('edge_margin', 12), 8, 80, 2)
        form.addRow('板边保护（px）', self.edge_margin)
        note = QLabel('保护带内不参与表面比对，画面会显示检测覆盖边界。检测板边崩缺需要单独的轮廓检测。')
        note.setWordWrap(True)
        form.addRow(note)
        self.refine = QCheckBox('精配准（≤2 px）')
        self.refine.setChecked(self.saved.get('refine', False))
        form.addRow(self.refine)
        sl.addWidget(group)
        group = QGroupBox('多组良品正常波动')
        form = QFormLayout(group)
        self.use_variation = QCheckBox('正常波动模型（≥3组）')
        self.use_variation.setChecked(self.saved.get('use_variation', True))
        form.addRow(self.use_variation)
        self.variation_cap = self._number(self.saved.get('variation_cap', 30), 0, 100, 2, 1)
        form.addRow('局部阈值增加上限', self.variation_cap)
        self.normal_label = QLabel('当前 0 组。先标定良品，再在“模板 / 接收”添加其他确认良品。')
        self.normal_label.setWordWrap(True)
        form.addRow(self.normal_label)
        note = QLabel('正反面分别采样。只添加确认良品，模型不会自动吸收待测板。高波动位置会放宽容差，也可能降低该处细小缺陷的灵敏度。')
        note.setWordWrap(True)
        form.addRow(note)
        sl.addWidget(group)
        sl.addStretch()
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setWidget(suppression)
        tabs.addTab(scroll, '误报抑制')
        split.addWidget(tabs)
        split.setStretchFactor(0, 1)
        split.setStretchFactor(1, 0)
        split.setSizes([1100, 350])
        outer.addWidget(split, 1)
        self.message = CompactStatus('')
        self.message.setFixedHeight(20)
        self.message.setStyleSheet('color:#92a9c2; font-size:11px;')
        outer.addWidget(self.message)
        self.setCentralWidget(center)
        self.view_mode.currentIndexChanged.connect(self.render)
        self.strength.valueChanged.connect(self.render)
        self.compare.toggled.connect(self.render)
        self.show_boxes.toggled.connect(self.render)
        self.show_coverage.toggled.connect(self.render)
        self.automatic.toggled.connect(self._parameter_changed)
        for w in [self.k, self.threshold, self.area, self.peak, self.window,
                  self.confirm, self.confirm_area, self.confirm_peak, self.edge_margin, self.variation_cap, self.scratch_min_length, self.scratch_response, self.small_structure_response, self.structure_tolerance]:
            w.valueChanged.connect(self._parameter_changed)
        self.refine.toggled.connect(self._parameter_changed)
        self.use_variation.toggled.connect(self._parameter_changed)
        self.surface_mode.toggled.connect(self._parameter_changed)
        self.mask_mount_holes.toggled.connect(self._parameter_changed)
        self._threshold_controls()

    def _toggle_parameters(self, visible):
        self.option_tabs.setVisible(visible)
        self.parameters_button.setText('收起参数' if visible else '显示参数')

    def _threshold_controls(self):
        compatible=self.surface_mode.isChecked()
        self.algorithm_label.setText('检测：绿油色差兼容（实验） · 细线按长度、细小亮异物按结构、块状异常按面积确认 · 切换见“误报抑制”' if compatible else '检测：传统灰度模板差分 · 参数含全板灰度阈值及面积筛选')
        self.automatic.setEnabled(not compatible)
        self.k.setEnabled(not compatible and self.automatic.isChecked())
        self.threshold.setEnabled(not compatible and not self.automatic.isChecked())
        self.peak.setEnabled(not compatible);self.confirm_peak.setEnabled(not compatible)
        self.use_variation.setEnabled(True);self.variation_cap.setEnabled(not compatible)
        for widget in (self.scratch_min_length,self.scratch_response,self.small_structure_response,self.structure_tolerance,self.mask_mount_holes):widget.setEnabled(compatible)
        if hasattr(self,'tm') and self.tm is not None:
            count=len(self.tm.raw_good_groups) if compatible else len(self.tm.normal_groups)
            self.normal_label.setText(f'颜色兼容良品{count}组，满3组采用结构/材质正常范围。' if compatible else f'当前{count}组，满3组启用正常波动容差。')

    def parameters(self):
        return Parameters(k=self.k.value(), min_area=self.area.value(), min_peak=self.peak.value(),
            fixed_threshold=None if self.automatic.isChecked() else self.threshold.value(),
            window_s=self.window.value(), confirm_s=self.confirm.value(),
            confirm_area=self.confirm_area.value(), confirm_peak=self.confirm_peak.value(),
            edge_margin=self.edge_margin.value(), refine=self.refine.isChecked(),
            use_variation=self.use_variation.isChecked(), variation_cap=self.variation_cap.value(),
            surface_mode=self.surface_mode.isChecked(),scratch_min_length=self.scratch_min_length.value(),
            scratch_response=self.scratch_response.value(),structure_tolerance=self.structure_tolerance.value(),
            mask_mount_holes=self.mask_mount_holes.isChecked(),small_structure_response=self.small_structure_response.value()).validate()

    def _parameter_changed(self):
        self._threshold_controls()
        if hasattr(self, 'parameter_timer'):
            if self.mode in ('learning', 'learning_setup'):
                self.stop_operation()
                self.message.setText('采样参数已改变，本组采集已取消；请重新添加确认良品。')
            # Invalidate pending work immediately; restart only after editing settles.
            if self.mode == 'inspect':
                self.generation += 1
                self.mode = 'parameter_wait'
                self.session = None
                self.last_result = None
                self.verdict.setText('参数已修改 · 等待应用后重新开始本板检测')
            self.parameter_timer.start()

    def _parameters_applied(self):
        if self.mode == 'parameter_wait':
            self.start_inspection()
        else:
            self.persist_settings()

    def persist_settings(self):
        data = {'bind': self.bind.currentText().strip(), 'port': self.port.value(),
            'source': self.source.text().strip(), 'require_control': self.manage_capture.isChecked(),
            'remote_port':self.remote_port.value(), 'view_mode': self.view_mode.currentData(),
            'strength': self.strength.value(), 'compare': self.compare.isChecked(),
            'automatic': self.automatic.isChecked(), 'k': self.k.value(),
            'threshold': self.threshold.value(), 'min_area': self.area.value(), 'min_peak': self.peak.value(),
            'window_s': self.window.value(), 'confirm_s': self.confirm.value(),
            'confirm_area': self.confirm_area.value(), 'confirm_peak': self.confirm_peak.value(),
            'edge_margin': self.edge_margin.value(), 'refine': self.refine.isChecked(),
            'use_variation': self.use_variation.isChecked(), 'variation_cap': self.variation_cap.value(),
            'surface_mode':self.surface_mode.isChecked(),'scratch_min_length':self.scratch_min_length.value(),
            'scratch_response':self.scratch_response.value(),'small_structure_response':self.small_structure_response.value(),'structure_tolerance':self.structure_tolerance.value(),
            'mask_mount_holes':self.mask_mount_holes.isChecked(),
            'show_coverage': self.show_coverage.isChecked(),
            'template': str(self.template_path) if self.template_path else ''}
        try:
            atomic_json(self.root/'settings.json', data)
        except OSError as exc:
            self.message.setText(f'设置保存失败：{exc}')

    def enqueue(self, frame):
        try:
            self.frames.put_nowait(frame)
        except queue.Full:
            try:
                self.frames.get_nowait()
            except queue.Empty:
                pass
            try:
                self.frames.put_nowait(frame)
            except queue.Full:
                pass

    def start_receiver(self):
        try:
            config = Settings(bind=self.bind.currentText().strip(), port=self.port.value(),
                              source=self.source.text().strip()).validate()
        except ValueError as exc:
            self.message.setText(f'网络参数无效：{exc}')
            return
        self.stop_operation()
        if self.rx:
            self.rx.stop()
            self.rx.join(timeout=.5)
        while not self.frames.empty():
            try:
                self.frames.get_nowait()
            except queue.Empty:
                break
        self.current = self.shown = None
        self._capture_blocked=False
        self.rx = (CooperativeReceiver(config,self.enqueue,self.remote_port.value()) if self.manage_capture.isChecked()
                   else self.receiver_factory(config,self.enqueue))
        self.rx.start()
        self.message.setText(f'正在监听 {config.bind}:{config.port}。若端口被占用，请先关闭旧接收程序。')
        self.persist_settings()

    def capture_ready(self,frame=None):
        if not self.rx or not getattr(self.rx,'cooperative',False):return True
        state=self.rx.snapshot()
        return (bool(state.get('control_ready')) and not state.get('error')
                and (frame is None or getattr(frame,'capture_epoch',None)==state.get('control_epoch')))

    def fresh(self):
        return (self.current is not None and time.monotonic()-self.current[0].received < 2.5
                and self.capture_ready(self.current[0]))

    def _check_capture_guard(self):
        if not self.rx or not getattr(self.rx,'cooperative',False):
            self.capture_label.setText('纯图传 / 回放模式 · 最终判定来自 PC；请确认板端未运行独立检测。')
            return
        state=self.rx.snapshot();ready=bool(state.get('control_ready')) and not state.get('error')
        self.capture_label.setText('FPGA采集：'+state.get('control_reason','等待握手')+' · 检测算法：PC 1.1')
        if ready:
            if self._capture_blocked:self.message.setText('实时采集已恢复；请手动开始新一板检测。')
            self._capture_blocked=False
            return
        if self._capture_blocked:return
        self._capture_blocked=True
        reason=state.get('control_reason','采集模式未确认')
        if self.mode=='inspect' and self.session:
            self.generation+=1
            self.session.invalidate('FPGA采集通道未就绪：'+reason)
            self.finish_inspection()
        elif self.mode not in ('loading','preview'):
            self.stop_operation()
            self.verdict.setText('PC 未判定 · FPGA 实时采集未就绪')
        self.current=None
        while not self.frames.empty():
            try:self.frames.get_nowait()
            except queue.Empty:break
        self.view.regions=[];self.view.confirmed_boxes=[];self.view.update()
        self.message.setText(reason)

    def stop_operation(self):
        self.generation += 1
        self.mode, self.session, self.last_result = 'preview', None, None
        self.last_submitted = None
        self.table.setRowCount(0)
        self.metrics.setText('当前候选 0 处 · 本板确认 0 处\n有效帧 0 · 无效帧 0')
        self.progress.setValue(0)
        self.progress.setFormat('实时预览')
        self.verdict.setText('仅预览 · 点击“开始检测”进行新一块板的检测')
        if self.current:
            self.shown = self.current
            self.render()
        self.refresh_controls()

    def calibrate_clicked(self):
        if not self.fresh():
            self.message.setText('尚未收到新鲜的完整图像，暂时不能标定。')
            return
        answer = QMessageBox.question(self, '标定良品模板',
            f'请放入同板型、同一面的确认良品，保持板子和光照稳定。\n'
            f'将采集 {self.cal_count.value()} 个有效帧，并自动保存为新模板。')
        if answer == QMessageBox.StandardButton.Yes:
            self.begin_calibration()

    def begin_calibration(self):
        self.stop_operation()
        self.mode = 'calibrate'
        self.cal_need = self.cal_count.value()
        self.cal_tm = TemplateMatcher()
        self.cal_tm.start_calibration(self.cal_need)
        self.cal_deadline = time.monotonic()+90
        self.verdict.setText('正在标定良品模板 · 请保持静止')
        self.progress.setFormat('标定：0 帧')
        self.refresh_controls()

    def start_inspection(self):
        try:
            params = self.parameters()
        except ValueError as exc:
            self.mode = 'preview'
            self.verdict.setText('检测参数无效')
            self.message.setText(str(exc))
            return
        if self.tm is None or not self.fresh():
            self.mode = 'preview'
            self.message.setText('请先标定/加载模板，并确认已收到实时图像。')
            return
        if self.current[1].shape != self.tm.ref_bgr.shape:
            self.message.setText('当前图像分辨率与模板不一致，请在当前分辨率重新标定。')
            return
        self.stop_operation()
        self.session = BoardSession(params, time.monotonic())
        self.mode = 'inspect'
        self.verdict.setStyleSheet('color: #fbbf24')
        self.verdict.setText(f'观察中 · 本板 {self.session.id} · 等待有效检测')
        self.message.setText('请保持本板静止。换下一块板时，请重新点击“开始检测”。')
        self.persist_settings()
        self.refresh_controls()

    def choose_template(self):
        filename, _ = QFileDialog.getOpenFileName(self, '加载良品模板', str(self.root/'templates'), '模板 (*.npz)')
        if filename:
            if self.pending:
                self.message.setText('正在完成上一项计算，请稍后再加载模板。')
                return
            self._request_load(Path(filename))

    def _request_load(self, path):
        self.stop_operation()
        self.mode = 'loading'
        self.verdict.setText('正在加载模板…')
        self._submit('load', None, lambda: (template_valid(TemplateMatcher.load(path)), path))

    def save_template_as(self):
        if self.tm is None or self.pending:
            self.message.setText('请先完成标定/加载，等待当前计算结束。')
            return
        filename, _ = QFileDialog.getSaveFileName(self, '另存模板', str(self.root/'templates'/'良品模板.npz'), '模板 (*.npz)')
        if filename:
            path = Path(filename).with_suffix('.npz')
            try:
                self.tm.save(path, self.tm.label)
                self.message.setText(f'模板已保存：{path}')
            except Exception as exc:
                self.message.setText(f'模板保存失败：{exc}')

    def _submit(self, kind, sample, function):
        def run():
            started = time.perf_counter()
            return function(), (time.perf_counter()-started)*1000
        self.pending = (self.executor.submit(run), self.generation, kind, sample)

    def _work_calibration(self, tm, image, path):
        done, count, need = tm.feed_calibration(image)
        if done:
            template_valid(tm)
            consistency = tm.consistency or {}
            if not math.isfinite(consistency.get('p90', math.inf)) or consistency['p90'] > 10:
                raise ValueError('标定帧差异较大，请固定板子/光照后重新标定。原模板已保留。')
            tm.label = path.stem
            temp = path.with_suffix('.tmp.npz')
            tm.save(temp, tm.label)
            temp.replace(path)
        return done, count, need, tm, path

    def learn_clicked(self):
        if not self.tm or not self.fresh() or self.pending:
            self.message.setText('请先加载模板，并等待当前计算完成。')
            return
        if QMessageBox.question(self, '添加确认良品',
            '请放入同板型同一面的另一块确认良品。将采集 5 个有效帧，\n'
            '作为一组正常样本保存到新模型文件，不覆盖原模板。\n\n'
            '请勿用待测缺陷板添加样本；连续拍同一块不能代表板间差异。') == QMessageBox.StandardButton.Yes:
            self.begin_learning()

    def begin_learning(self):
        self.stop_operation()
        self.mode = 'learning_setup'
        self.cal_deadline = time.monotonic()+90
        self.learn_params = self.parameters()
        source = self.template_path
        self.learn_path = self.root/'templates'/f'良品波动模型_{datetime.now():%Y%m%d_%H%M%S}.npz'
        def setup():
            tm = TemplateMatcher.load(source)
            tm.start_good_sampling(5)
            return tm
        self._submit('learning_setup', None, setup)
        self.verdict.setText('准备正常样本采集 · 请保持良品静止')

    def clear_learning(self):
        if not self.tm or self.pending:
            return
        if QMessageBox.question(self, '清空波动模型', '保留初始模板，清空后续正常波动样本，并另存新文件？') != QMessageBox.StandardButton.Yes:
            return
        self.stop_operation()
        self.mode = 'loading'
        source = self.template_path
        path = self.root/'templates'/f'基础模板_{datetime.now():%Y%m%d_%H%M%S}.npz'
        def work():
            tm = TemplateMatcher.load(source)
            tm.clear_normal_groups()
            tm.save(path, path.stem)
            return tm, path
        self._submit('load', None, work)

    def _work_learning(self, tm, image, path, params):
        done, count, need = tm.feed_good_sample(image, label=f'确认良品 {datetime.now():%m-%d %H:%M:%S}',
            edge_margin=params.edge_margin, refine=params.refine)
        if done:
            tm.label = path.stem
            temp = path.with_suffix('.tmp.npz')
            tm.save(temp, tm.label)
            temp.replace(path)
        return done, count, need, tm, path

    def _template_ready(self, tm, path):
        self.tm, self.template_path = tm, Path(path)
        self.template_hash = hashlib.sha256(self.template_path.read_bytes()).hexdigest()
        c = tm.consistency or {}
        count = len(tm.normal_groups)
        self.normal_label.setText(f'当前 {count} 组正常样本，'
            + ('逐位置正常波动模型已就绪。' if count >= 3 else '满 3 组后启用逐位置容差。'))
        self.template_label.setText(f'{self.template_path.stem}\n{tm.n_frames} 帧 · 一致性 '
            f'{c.get("median", 0):.1f} / {c.get("p90", 0):.1f}\n'
            f'输入 {tm.ref_bgr.shape[1]} × {tm.ref_bgr.shape[0]} · 检测预处理增强 {"开" if tm.enhance else "关"}')
        rgb = cv2.cvtColor(tm.tpl, cv2.COLOR_BGR2RGB)
        image = QImage(rgb.data, rgb.shape[1], rgb.shape[0], rgb.strides[0], QImage.Format.Format_RGB888).copy()
        from PySide6.QtGui import QPixmap
        self.template_thumb.setPixmap(QPixmap.fromImage(image).scaled(285, 145,
            Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation))
        if tm.raw_tpl is None:
            self.template_label.setText(self.template_label.text()+'\n旧模板：兼容通道使用单张参考帧，建议当前工况重新标定。')
        self._threshold_controls()
        self.mode = 'preview'
        self.verdict.setStyleSheet('')
        self.verdict.setText('模板已就绪 · 换入待测板后点击“开始检测”')
        self.message.setText(f'模板：{path}。模板与当前板面必须一致。')
        self.persist_settings()

    def _poll_work(self):
        if not self.pending or not self.pending[0].done():
            return
        future, generation, kind, sample = self.pending
        self.pending = None
        if generation != self.generation:
            try:
                future.result()
            except Exception:
                pass
            return
        try:
            result, duration = future.result()
            if kind in ('inspect','calibrate','learning') and sample and not self.capture_ready(sample[0]):
                if kind=='inspect' and self.session:
                    self.session.invalidate('采集状态已改变，丢弃迟到计算结果')
                    self.finish_inspection()
                else:
                    self.stop_operation();self.message.setText('采集状态已改变，请恢复实时图像后重新操作。')
                return
            if kind == 'load':
                self._template_ready(*result)
            elif kind == 'learning_setup':
                self.learn_tm = result
                self.mode = 'learning'
                self.verdict.setText('采集确认良品样本 · 0 / 5 帧')
            elif kind in ('calibrate', 'learning'):
                done, count, need, tm, path = result
                self.progress.setValue(round(1000*count/need))
                self.progress.setFormat(f'{"正常样本" if kind == "learning" else "标定"}：{count} / {need} 帧')
                if done:
                    self.cal_info = tm.consistency
                    self._template_ready(tm, path)
            elif kind == 'inspect':
                self.processing_ms = duration
                self.inspected_frames += 1
                self.last_result = result
                self.shown = sample
                frame = sample[0]
                if time.monotonic()-frame.received > 2.5:
                    self.session.invalidate('检测结果帧已过期，请检查接收或处理速度')
                else:
                    self.session.update(result, frame.received, (frame.source, frame.meta.frame_id, frame.received))
                self._show_session()
                self.render()
                if self.session.state != 'running':
                    self.finish_inspection()
        except Exception as exc:
            self.message.setText(f'处理失败：{exc}')
            if self.session and self.mode == 'inspect':
                self.session.invalidate(f'处理失败：{exc}')
                self.finish_inspection()
            else:
                self.mode = 'preview'
                self.verdict.setText('本次操作失败 · 原模板保留，请检查后重试')
            self._error_log()
        self.refresh_controls()

    def _show_session(self):
        session = self.session
        count = len(self.last_result.regions) if self.last_result and self.last_result.ok else 0
        self.metrics.setText(f'当前候选 {count} 处 · 本板确认 {len(session.confirmed)} 处\n'
            f'有效帧 {session.total_valid} · 无效帧 {session.invalid_frames}')
        self.progress.setValue(min(1000, round(1000*session.valid_s/session.params.window_s)))
        self.progress.setFormat(f'有效观察 {session.valid_s:.1f} / {session.params.window_s:.0f} 秒')
        if self.last_result and self.last_result.ok:
            self.verdict.setText(f'观察中 · 当前 {count} 处候选 · 尚未形成最终判定')
        else:
            self.verdict.setText('对齐失败 / 板面覆盖不足 · 本帧不计入有效观察')
        self.table.setRowCount(min(20, len(session.tracks)))
        for row, tr in enumerate(sorted(session.tracks, key=lambda t: -(t.last-t.first))[:20]):
            for col, value in enumerate([f'{tr.last-tr.first:.1f}', tr.hits, tr.area, f'{tr.peak:.1f}']):
                self.table.setItem(row, col, QTableWidgetItem(str(value)))

    def finish_inspection(self):
        if not self.session or self.session.state == 'running':
            return
        session = self.session
        self.generation += 1
        self.mode = 'finished'
        state = STATE_NAMES[session.state]
        color = '#fb7185' if session.state == 'ng' else '#4ade80' if session.state == 'ok' else '#fbbf24'
        self.verdict.setStyleSheet(f'color: {color}')
        suffix = f' · 确认 {len(session.confirmed)} 处异常' if session.state == 'ng' else ''
        self.verdict.setText(f'本板最终：{state}{suffix} · 结果画面已冻结')
        self.frame_caption.setText('本板结果画面 · 点击“开始检测 / 下一板”会清空本板结果')
        self.message.setText(session.reason or '本板检测完成。放入下一块板后，再次点击“开始检测”。')
        if session.id not in self.recorded:
            self.recorded.add(session.id)
            try:
                self.save_record()
            except Exception as exc:
                self.message.setText(f'本板结果保存失败：{exc}。请检查保存目录；当前画面仍可手动导出。')
                self._error_log()
        self.refresh_controls()

    def save_record(self):
        session = self.session
        name = f'{datetime.now():%Y%m%d_%H%M%S}_{session.id}'
        folder = self.root/'records'/name
        folder.mkdir()
        sample = self.shown or self.current
        rec = {'version': VERSION, 'board_id': session.id, 'time': datetime.now().isoformat(timespec='seconds'),
            'state': STATE_NAMES[session.state], 'reason': session.reason,
            'template': str(self.template_path), 'template_sha256': self.template_hash,
            'decision_source':'PC Surface13 / BoardSession13' if session.params.surface_mode else 'PC Legacy11 / BoardSession13',
            'capture_control':self.rx.snapshot().get('control_state') if self.rx else None,
            'parameters': asdict(session.params), 'valid_seconds': round(session.valid_s, 3),
            'valid_frames': session.total_valid, 'invalid_frames': session.invalid_frames,
            'confirmed': session.confirmed, 'review_candidates': session.review_evidence,
            'view': self.view_settings(), 'record_folder': name}
        if sample:
            frame, bgr = sample
            write_png(folder/'原始帧.png', bgr)
            if self.last_result and self.last_result.coverage_mask is not None:
                write_png(folder/'检测覆盖区.png', self.last_result.coverage_mask)
            rgb = self.enhancer.apply(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB),
                                       self.view_mode.currentData(), self.strength.value())
            annotated = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
            for region in (self.last_result.regions if self.last_result and self.last_result.ok else []):
                x1, y1, x2, y2 = [round(v) for v in region.bbox]
                cv2.rectangle(annotated, (x1, y1), (x2, y2), (64, 64, 255), 2)
            write_png(folder/'增强候选图.png', annotated)
            rec.update(frame_id=frame.meta.frame_id, sender=frame.source,
                       frame_wall_time=frame.wall_time, width=frame.meta.width, height=frame.meta.height,
                       candidates=[asdict(r) for r in (self.last_result.regions if self.last_result and self.last_result.ok else [])])
        atomic_json(folder/'result.json', rec)
        with (self.root/'records'/'台账.jsonl').open('a', encoding='utf-8') as f:
            f.write(json.dumps(rec, ensure_ascii=False)+'\n')
        table = self.root/'records'/'台账.csv'
        exists = table.exists()
        with table.open('a', newline='', encoding='utf-8-sig') as f:
            writer = csv.writer(f)
            if not exists:
                writer.writerow(['时间', '板号', '结果', '确认数', '有效秒', '有效帧', '无效帧', '模板', '记录目录'])
            writer.writerow([rec['time'], session.id, rec['state'], len(session.confirmed),
                rec['valid_seconds'], session.total_valid, session.invalid_frames,
                str(self.template_path), name])
        self.record_label.setText(f'最新记录：{rec["state"]}\n{folder}')

    def view_settings(self):
        return {'mode': self.view_mode.currentData(), 'level': self.strength.value(),
                'compare': self.compare.isChecked()}

    def export_clicked(self):
        if not self.shown:
            self.message.setText('尚无可保存画面。')
            return
        try:
            self.export_frame()
        except Exception as exc:
            self.message.setText(f'画面保存失败：{exc}')

    def export_frame(self):
        frame, bgr = self.shown
        folder = self.root/'exports'/datetime.now().strftime('%Y%m%d_%H%M%S_%f')
        folder.mkdir()
        write_png(folder/'原始帧.png', bgr)
        enhanced = self.enhancer.apply(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB),
                                      self.view_mode.currentData(), self.strength.value())
        write_png(folder/'增强图.png', cv2.cvtColor(enhanced, cv2.COLOR_RGB2BGR))
        atomic_json(folder/'settings.json', {'view': self.view_settings(),
            'parameters': asdict(self.parameters()), 'frame_id': frame.meta.frame_id,
            'sender': frame.source, 'template': str(self.template_path),
            'regions': [asdict(r) for r in (self.last_result.regions if self.last_result and self.last_result.ok else [])]})
        self.message.setText(f'原图、完整增强图和参数已保存：{folder}')
        return folder

    def render(self):
        self.strength_label.setText(str(self.strength.value()))
        if self.shown is None:
            return
        frame, bgr = self.shown
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        enhanced = self.enhancer.apply(rgb, self.view_mode.currentData(), self.strength.value())
        if self.compare.isChecked():
            enhanced[:, :rgb.shape[1]//2] = rgb[:, :rgb.shape[1]//2]
            enhanced[:, rgb.shape[1]//2:rgb.shape[1]//2+1] = (56, 189, 248)
        if self.show_coverage.isChecked() and self.last_result and self.last_result.ok and self.last_result.coverage_mask is not None:
            coverage = self.last_result.coverage_mask
            outside = coverage == 0
            enhanced[outside] = (enhanced[outside].astype(np.float32)*.55).astype(np.uint8)
            contours, _ = cv2.findContours(coverage, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            cv2.drawContours(enhanced, contours, -1, (56, 189, 248), 1)
        regions = self.last_result.regions if self.last_result and self.last_result.ok else []
        confirmed = [r['box'] for r in self.session.confirmed] if self.session else []
        self.view.set_image(enhanced, regions, self.show_boxes.isChecked(), confirmed)
        if self.mode != 'finished':
            text = '检测结果帧' if self.mode == 'inspect' else '实时预览'
            self.frame_caption.setText(f'{text} · {frame.meta.width} × {frame.meta.height} · 帧 {frame.meta.frame_id}'
                + (' · 左侧原图 / 右侧增强' if self.compare.isChecked() else ''))
        if self.last_result and self.last_result.ok:
            r = self.last_result
            if r.surface_info:
                q=r.surface_info
                self.image_stats.setText(f'配准 {r.align_inliers} 内点 / {r.align_err:.2f}px · 算法 {self.processing_ms:.0f}ms/帧\n'
                    f'颜色兼容：细线{q["line_count"]} / 局部结构{q["small_count"]} / 材质{q["material_count"]} · 结构响应≥{r.thr:g} · 良品模型{q["normal_groups"]}组 · 孔内部排除{q["holes"]}处')
            else:
                self.image_stats.setText(f'配准 {r.align_inliers} 内点 / {r.align_err:.2f} px · '
                    f'阈值 {r.thr:.1f}–{r.threshold_max:.1f} · 算法 {self.processing_ms:.0f} ms/帧\n'
                    f'橙：候选；红：确认；蓝线内：检测区。精配准 {"已采用" if r.refined else "未采用"} · 正常组 {r.normal_groups}')
        else:
            self.image_stats.setText('增强只影响观察；检测使用原始帧及模板绑定的预处理。')

    def refresh_controls(self):
        available = self.fresh()
        busy_mode = self.mode in ('calibrate', 'loading', 'learning_setup', 'learning')
        self.cal_button.setEnabled(available and not busy_mode)
        self.start_button.setEnabled(available and self.tm is not None and not busy_mode)
        self.start_button.setText('检测下一板' if self.mode == 'finished' else '开始检测')
        self.load_button.setEnabled(not busy_mode and self.pending is None)
        self.good_button.setEnabled(available and self.tm is not None and not busy_mode and self.pending is None)
        self.clear_good_button.setEnabled(self.tm is not None and not busy_mode and self.pending is None)
        self.export_button.setEnabled(self.shown is not None)
        self.cal_count.setEnabled(self.mode != 'calibrate')
        self.template_name.setEnabled(self.mode != 'calibrate')

    def tick(self):
        try:
            self._check_capture_guard()
            self._poll_work()
            latest = None
            while True:
                try:
                    latest = self.frames.get_nowait()
                except queue.Empty:
                    break
            if latest and not self.capture_ready(latest):latest=None
            if latest:
                self.current = (latest, cv2.cvtColor(latest.rgb(), cv2.COLOR_RGB2BGR))
                if self.mode in ('preview', 'calibrate', 'loading', 'learning_setup', 'learning', 'parameter_wait'):
                    self.shown = self.current
                    self.render()
            now = time.monotonic()
            if self.rx:
                s = self.rx.snapshot()
                if s['error']:
                    self.link.setText('接收失败')
                    self.message.setText(f'{s["error"]}。端口占用时请关闭旧接收程序，再应用接收设置。')
                elif now-s['last_frame'] < 3:
                    self.link.setText(f'{s["sender"]} · 接收 {s["fps"]:.1f} fps · 完整 {s["frames"]} · 丢帧 {s["dropped"]}')
                else:
                    self.link.setText(f'监听 {self.port.value()} · 等待完整图像')
            if self.mode == 'inspect':
                if not self.fresh():
                    self.session.invalidate('图像流中断，未作 OK/NG 判定')
                self.session.check_timeout(now)
                if self.session.state != 'running':
                    self.finish_inspection()
            elif self.mode in ('calibrate', 'learning', 'learning_setup') and now > self.cal_deadline:
                self.stop_operation()
                self.message.setText('标定超时，请确认良品板可见、光照稳定、图像流正常。')
            if self.pending is None and self.fresh() and self.mode in ('calibrate', 'learning', 'inspect'):
                frame, bgr = self.current
                key = (frame.source, frame.meta.frame_id, frame.received)
                if key != self.last_submitted:
                    self.last_submitted = key
                    sample = (frame, bgr.copy())
                    if self.mode == 'calibrate':
                        clean = ''.join(c for c in self.template_name.text() if c.isalnum() or c in '_-')[:48] or '良品'
                        path = self.root/'templates'/f'{clean}_{datetime.now():%Y%m%d_%H%M%S}.npz'
                        tm = self.cal_tm
                        self._submit('calibrate', sample,
                            lambda tm=tm, image=sample[1], path=path: self._work_calibration(tm, image, path))
                    elif self.mode == 'learning':
                        tm, path, params = self.learn_tm, self.learn_path, self.learn_params
                        self._submit('learning', sample,
                            lambda tm=tm, image=sample[1], path=path, p=params: self._work_learning(tm, image, path, p))
                    else:
                        params, tm = self.session.params, self.tm
                        self._submit('inspect', sample,
                            lambda tm=tm, image=sample[1], p=params: tm.detect(image, k=p.k,
                                min_area=p.min_area, min_peak=p.min_peak, fixed_threshold=p.fixed_threshold,
                                edge_margin=p.edge_margin, refine=p.refine, use_variation=p.use_variation,
                                variation_cap=p.variation_cap,surface_mode=p.surface_mode,
                                scratch_min_length=p.scratch_min_length,scratch_response=p.scratch_response,
                                structure_tolerance=p.structure_tolerance,mask_mount_holes=p.mask_mount_holes,small_structure_response=p.small_structure_response))
            self.refresh_controls()
        except Exception as exc:
            self.message.setText(f'界面处理失败：{exc}')
            self._error_log()

    def _error_log(self):
        with (self.root/'errors.log').open('a', encoding='utf-8') as f:
            f.write(f'\n{datetime.now().isoformat()}\n{traceback.format_exc()}')

    def diagnostic(self):
        return {'version': VERSION, 'mode': self.mode, 'template': str(self.template_path),
            'received': self.rx.snapshot() if self.rx else {}, 'inspected_frames': self.inspected_frames,
            'processing_ms': self.processing_ms, 'verdict': self.verdict.text(),
            'message': self.message.text(), 'session': {
                'id': self.session.id, 'state': self.session.state, 'valid_frames': self.session.total_valid,
                'valid_seconds': self.session.valid_s, 'confirmed': self.session.confirmed}
                if self.session else None}

    def closeEvent(self, event):
        self.closed = True
        self.timer.stop()
        self.generation += 1
        self.persist_settings()
        if self.rx:
            self.rx.stop()
            self.rx.join(timeout=.5)
        self.executor.shutdown(wait=False, cancel_futures=True)
        event.accept()


STYLE = '''
QMainWindow, QWidget { background: #0e1727; color: #dce6f4; font-family: "Microsoft YaHei"; font-size: 12px; }
QLabel#title { font-size: 18px; font-weight: 650; color: #f0f6ff; }
QLabel#verdict { background: #18273e; padding: 6px 10px; border-radius: 6px; font-size: 14px; font-weight: 600; }
QPushButton { background: #253954; border: 1px solid #365172; border-radius: 6px; padding: 6px 10px; }
QPushButton:hover { background: #344f71; }
QPushButton:disabled { color: #75869e; background: #172238; border-color: #243348; }
QPushButton#primary { background: #1c55ae; border-color: #3475d8; }
QPushButton#success { background: #16754f; border-color: #27946b; }
QGroupBox { border: 1px solid #2b405d; border-radius: 6px; margin-top: 12px; padding: 12px 6px 6px; }
QGroupBox::title { subcontrol-origin: margin; left: 10px; color: #92caff; }
QLineEdit, QComboBox, QSpinBox, QDoubleSpinBox { background: #192a42; border: 1px solid #365172; border-radius: 4px; padding: 5px; }
QComboBox QAbstractItemView { background: #192a42; selection-background-color: #315d89; }
QTabWidget::pane { border: 1px solid #263a55; }
QTabBar::tab { padding: 7px 10px; background: #18273e; }
QTabBar::tab:selected { background: #2c496d; }
QTableWidget { background: #122037; gridline-color: #293d58; border: 0; }
QHeaderView::section { background: #223650; border: 0; padding: 5px; }
QProgressBar { border: 0; background: #1b2e47; text-align: center; min-height: 16px; border-radius: 4px; font-size:11px; }
QProgressBar::chunk { background: #246da0; border-radius: 5px; }
QScrollArea { border: 0; }
QCheckBox { spacing: 6px; }
QSlider::groove:horizontal { height: 5px; background: #34506e; }
QSlider::handle:horizontal { background: #38bdf8; width: 12px; margin: -5px 0; border-radius: 6px; }
'''


def configure_application(app):
    # One inspection worker already runs beside the receiver and Qt. Limiting
    # OpenCV avoids CPU oversubscription and makes live latency match the tests.
    cv2.setNumThreads(2)
    # Explicit registration also supports Windows offscreen rendering, whose
    # platform plugin does not always enumerate installed fonts automatically.
    font_path = Path(os.environ.get('SystemRoot', r'C:\Windows'))/'Fonts'/'msyh.ttc'
    if font_path.exists():
        QFontDatabase.addApplicationFont(str(font_path))
    app.setFont(QFont('Microsoft YaHei', 10))
    app.setStyle('Fusion')
    app.setStyleSheet(STYLE)


def main():
    parser = argparse.ArgumentParser(description='PCB AOI Studio · 模板检测与以太网图像接收')
    parser.add_argument('--bind')
    parser.add_argument('--port', type=int)
    parser.add_argument('--source')
    parser.add_argument('--remote-port',type=int)
    parser.add_argument('--legacy-stream',action='store_true',help='旧纯图传固件或离线回放，不发送板端控制指令')
    parser.add_argument('--template')
    parser.add_argument('--data-dir', type=Path)
    parser.add_argument('--no-listen', action='store_true')
    parser.add_argument('--test-inspect', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--auto-exit', type=float, default=0, help=argparse.SUPPRESS)
    parser.add_argument('--status-json', type=Path, help=argparse.SUPPRESS)
    parser.add_argument('--screenshot', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.test_inspect and (args.bind!='127.0.0.1' or args.source!='127.0.0.1'):
        parser.error('--test-inspect is restricted to loopback verification')
    base = Path(sys.executable).parent if getattr(sys, 'frozen', False) else Path(__file__).resolve().parent.parent
    app = QApplication(sys.argv[:1])
    configure_application(app)
    window = Studio(args.data_dir or base/'data', args.bind, args.port, args.source,
                    not args.no_listen, args.template,require_control=False if args.legacy_stream else None,remote_port=args.remote_port)
    window.show()
    if args.test_inspect:
        test_timer=QTimer(window)
        def inspect_once():
            if window.tm is not None and window.fresh() and window.mode=='preview':
                test_timer.stop()
                window.confirm.setValue(2)
                window.window.setValue(5)
                QTimer.singleShot(600,window.start_inspection)
        test_timer.timeout.connect(inspect_once);test_timer.start(100)
    if args.auto_exit:
        def finish():
            if args.status_json:
                atomic_json(args.status_json, window.diagnostic())
            if args.screenshot:
                window.grab().save(str(args.screenshot))
            window.close()
        QTimer.singleShot(round(args.auto_exit*1000), finish)
    return app.exec()


if __name__ == '__main__':
    raise SystemExit(main())
