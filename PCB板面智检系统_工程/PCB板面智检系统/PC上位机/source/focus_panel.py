"""Per-channel lift commissioning and PC autofocus UI; no automatic arming."""
from concurrent.futures import ThreadPoolExecutor
from dataclasses import asdict
from datetime import datetime
from pathlib import Path
import json,queue,threading,time
from PySide6.QtCore import Qt,QTimer,QPointF,QRectF
from PySide6.QtGui import QPainter,QPen,QColor,QPolygonF
from PySide6.QtWidgets import QWidget,QVBoxLayout,QHBoxLayout,QFormLayout,QGroupBox,QLabel,QPushButton,QCheckBox,QSpinBox,QDoubleSpinBox
from autofocus import FocusSettings,ServoLink,FocusSearch,FocusError,Cancelled
from focus_protocol import Command

class FocusCurve(QWidget):
    def __init__(self):super().__init__();self.points=[];self.setMinimumHeight(150)
    def paintEvent(self,event):
        p=QPainter(self);p.fillRect(self.rect(),QColor('#080f1b'));p.setPen(QColor('#92caff'))
        if not self.points:p.drawText(self.rect(),Qt.AlignmentFlag.AlignCenter,'等待清晰度采样');return
        points=sorted(self.points,key=lambda q:q['pulse_us']);lo=points[0]['pulse_us'];hi=max(lo+1,points[-1]['pulse_us']);top=max(1e-9,max(q['score'] for q in points))
        area=QRectF(35,18,max(10,self.width()-48),max(10,self.height()-42));p.drawRect(area)
        polygon=QPolygonF([QPointF(area.left()+(q['pulse_us']-lo)/(hi-lo)*area.width(),area.bottom()-q['score']/top*area.height()) for q in points])
        p.setPen(QPen(QColor('#38bdf8'),2));p.drawPolyline(polygon)
        for point in polygon:p.drawEllipse(point,2,2)
        p.drawText(3,14,f'{top:.3g}');p.drawText(35,self.height()-5,str(lo));p.drawText(max(35,self.width()-90),self.height()-5,f'{hi} µs')

class FocusPanel(QWidget):
    def __init__(self,studio):
        super().__init__();self.studio=studio;self.link=None;self.search=None;self.future=None;self.label='';self.cancel_event=threading.Event();self.updates=queue.Queue();self.closed=False
        self.executor=ThreadPoolExecutor(max_workers=1,thread_name_prefix=f'focus-{studio.channel.id}')
        try:self.saved=json.loads((studio.root/'servo.json').read_text(encoding='utf-8'))
        except (OSError,ValueError):self.saved={}
        layout=QVBoxLayout(self)
        note=QLabel('MG996R普通定位型 · CEP9/F19信号，CEP40共地，舵机外部供电。脉宽是指令值，不是实际高度。上电不自动使能或归零。');note.setWordWrap(True);layout.addWidget(note)
        self.status=QLabel('尚未查询舵机控制状态；需要V26.5固件');self.status.setWordWrap(True);layout.addWidget(self.status)
        self.message=QLabel('先确认机构行程，再配置和使能；自动对焦使用原始图像。');self.message.setWordWrap(True)
        group=QGroupBox('机构行程 / PWM');form=QFormLayout(group)
        def integer(name,default,minimum,maximum,step=1):
            widget=QSpinBox();widget.setRange(minimum,maximum);widget.setSingleStep(step);widget.setValue(int(self.saved.get(name,default)));return widget
        self.lower=integer('lower',500,500,2499,10);self.upper=integer('upper',2500,501,2500,10);self.initial=integer('start',1500,500,2500,10);self.slew=integer('slew',5,1,20)
        for title,widget in [('下限（µs）',self.lower),('上限（µs）',self.upper),('首次使能脉宽（µs）',self.initial),('每20ms变化（µs）',self.slew)]:form.addRow(title,widget)
        self.confirm=QCheckBox('已确认定位型舵机及上述机械安全行程');form.addRow(self.confirm)
        buttons=QHBoxLayout();self.query_button=QPushButton('查询状态');self.configure_button=QPushButton('配置行程');buttons.addWidget(self.query_button);buttons.addWidget(self.configure_button);form.addRow(buttons)
        buttons=QHBoxLayout();self.arm_button=QPushButton('使能 / 保持');self.disable_button=QPushButton('关闭PWM / 注意防坠');buttons.addWidget(self.arm_button);buttons.addWidget(self.disable_button);form.addRow(buttons)
        layout.addWidget(group)
        group=QGroupBox('手动微调');form=QFormLayout(group);self.target=integer('target',1500,500,2500,10);self.jog=integer('jog',10,1,100)
        form.addRow('目标脉宽（µs）',self.target);form.addRow('微调步长（µs）',self.jog)
        row=QHBoxLayout();self.minus_button=QPushButton('− 微调');self.move_button=QPushButton('执行目标');self.plus_button=QPushButton('＋ 微调')
        for b in (self.minus_button,self.move_button,self.plus_button):row.addWidget(b)
        form.addRow(row);layout.addWidget(group)
        group=QGroupBox('自动对焦 / 粗扫 + 细扫');form=QFormLayout(group)
        self.search_lower=integer('search_lower',500,500,2499,10);self.search_upper=integer('search_upper',2500,501,2500,10)
        self.coarse=integer('coarse',250,10,1000,10);self.fine=integer('fine',50,5,500,5)
        self.settle=QDoubleSpinBox();self.settle.setRange(.2,5);self.settle.setSingleStep(.1);self.settle.setValue(float(self.saved.get('settle',.5)))
        self.samples=integer('samples',3,2,7);self.discard=integer('discard',1,1,5)
        for title,widget in [('搜索起点（µs）',self.search_lower),('搜索终点（µs）',self.search_upper),('粗扫步长（µs）',self.coarse),('细扫步长（µs）',self.fine),('机械稳定等待（秒）',self.settle),('每点取样帧数',self.samples),('每点丢弃新帧数',self.discard)]:form.addRow(title,widget)
        roi=self.saved.get('roi',[.35,.35,.3,.3]);self.roi=[]
        for index,name in enumerate(('ROI X（%）','ROI Y（%）','ROI 宽（%）','ROI 高（%）')):
            widget=QSpinBox();widget.setRange(0 if index<2 else 5,95 if index<2 else 100);widget.setValue(round(float(roi[index])*100));widget.valueChanged.connect(self.update_roi);self.roi.append(widget);form.addRow(name,widget)
        self.af_button=QPushButton('自动对焦');self.af_button.setObjectName('success');form.addRow(self.af_button)
        self.stop_button=QPushButton('停止运动 / 保持当前PWM');form.addRow(self.stop_button)
        note=QLabel('搜索期间保持板子、灯光与镜头调焦环固定。峰值落在边界或无法复现时不会报告成功。停止保持不会回零；断电、复位或关闭PWM后不能依赖保持力，升降台需有防坠措施。');note.setWordWrap(True);form.addRow(note)
        layout.addWidget(group);self.curve=FocusCurve();layout.addWidget(self.curve);layout.addWidget(self.message);layout.addStretch()
        self.action_buttons=[self.query_button,self.configure_button,self.arm_button,self.disable_button,self.minus_button,self.move_button,self.plus_button,self.af_button]
        self.parameter_widgets=self.findChildren(QSpinBox)+self.findChildren(QDoubleSpinBox)+[self.confirm]
        self.query_button.clicked.connect(lambda:self.run('查询状态',lambda:self.ensure_link().request(Command.QUERY)))
        self.configure_button.clicked.connect(self.configure);self.arm_button.clicked.connect(self.arm)
        self.disable_button.clicked.connect(self.disable_output)
        self.move_button.clicked.connect(lambda:self.manual_move(self.target.value()))
        self.minus_button.clicked.connect(lambda:self.jog_move(-1));self.plus_button.clicked.connect(lambda:self.jog_move(1))
        self.af_button.clicked.connect(self.autofocus);self.stop_button.clicked.connect(self.cancel)
        self.timer=QTimer(self);self.timer.timeout.connect(self.poll);self.timer.start(80)
    @property
    def busy(self):return self.future is not None
    def ensure_link(self):
        if self.link is None:
            self.link=ServoLink(self.studio.channel.id,self.studio.channel.source,self.studio.bind.currentText(),
                lambda:(self.studio.rx.snapshot().get('servo_status') if self.studio.rx else None),
                lambda message:self.updates.put({'error':message}),port=self.studio.remote_port.value())
        return self.link
    def settings(self,search=False):
        lower=self.search_lower.value() if search else self.lower.value();upper=self.search_upper.value() if search else self.upper.value()
        if not self.lower.value()<=lower<upper<=self.upper.value():raise ValueError('搜索范围必须在已确认的机械行程内')
        start=max(lower,min(upper,self.initial.value())) if search else self.initial.value()
        return FocusSettings(lower,upper,start,self.slew.value(),self.coarse.value(),self.fine.value(),self.settle.value(),self.samples.value(),self.discard.value(),tuple(w.value()/100 for w in self.roi)).validate(search=search)
    def save(self):
        values={name:getattr(self,name).value() for name in ('lower','upper','slew','target','jog','search_lower','search_upper','coarse','fine','settle','samples','discard')};values['start']=self.initial.value();values['roi']=[w.value()/100 for w in self.roi]
        path=self.studio.root/'servo.json';temp=path.with_suffix('.tmp');temp.write_text(json.dumps(values,ensure_ascii=False,indent=2),encoding='utf-8');temp.replace(path)
    def guard_motion(self):
        if not self.confirm.isChecked():raise FocusError('请先确认定位型舵机和机械安全行程')
        studio=self.studio;owner=studio.multi_owner
        if studio.pending or studio.mode not in ('preview','finished') or (owner and owner.busy_channel(studio.channel.id)):raise FocusError('请先结束当前检测/标定操作，再调整升降台')
        studio.invalidate_stage('舵机使能或运动指令')
    def run(self,label,work,motion=False):
        if self.busy:return
        try:
            if motion:self.guard_motion()
            self.cancel_event=threading.Event();self.label=label
            def task():
                try:return work()
                finally:
                    if self.cancel_event.is_set() and self.link and self.link.armed:
                        try:self.link.hold()
                        except Exception:pass
            self.future=self.executor.submit(task);self.message.setText(label+'…')
            for b in self.action_buttons:b.setEnabled(False)
            for w in self.parameter_widgets:w.setEnabled(False)
        except Exception as exc:self.message.setText(str(exc))
    def configure(self):
        if not self.confirm.isChecked():self.message.setText('请先确认定位型舵机和安全行程');return
        try:settings=self.settings();self.save()
        except Exception as exc:self.message.setText(str(exc));return
        self.run('配置行程',lambda:self.ensure_link().configure(settings))
    def arm(self):
        if not self.link or not self.link.token:self.message.setText('请先查询并配置行程');return
        self.run('使能保持',lambda:self.link.arm(),motion=True)
    def manual_move(self,target):
        if not self.link or not self.link.armed:self.message.setText('请先配置并使能舵机');return
        if not self.link.config.lower<=target<=self.link.config.upper:self.message.setText('目标超出已配置的机械行程');return
        self.run('手动移动',lambda:self.link.move(target,self.cancel_event),motion=True)
    def disable_output(self):
        self.studio.invalidate_stage('关闭PWM，实际高度需要重新确认')
        self.run('关闭PWM',lambda:self.ensure_link().disable())
    def jog_move(self,direction):
        state=self.link.latest() if self.link else None
        if state:self.target.setValue(state.applied+direction*self.jog.value());self.manual_move(self.target.value())
        else:self.message.setText('请先查询、配置并使能舵机')
    def autofocus(self):
        try:
            if not self.link or not self.link.armed:raise FocusError('请先配置并使能舵机')
            if not self.studio.fresh():raise FocusError('尚无新鲜图像，不能自动对焦')
            p=self.settings(search=True)
            if (self.lower.value(),self.upper.value(),self.slew.value())!=(self.link.config.lower,self.link.config.upper,self.link.config.slew):raise FocusError('行程参数已修改，请重新配置后再搜索')
            self.save();self.search=FocusSearch(self.link,lambda:self.studio.current,p,self.updates.put);self.curve.points=[];self.curve.update()
            self.run('自动对焦',self.search.run,motion=True)
        except Exception as exc:self.message.setText(str(exc))
    def cancel(self):
        self.cancel_event.set()
        if self.search:self.search.cancel.set()
        self.message.setText('正在停止；保持当前PWM，不自动回零')
        if not self.busy and self.link and self.link.armed:self.run('停止保持',self.link.hold)
    def update_roi(self):
        if len(self.roi)!=4:return
        self.studio.view.focus_roi=tuple(w.value()/100 for w in self.roi) if self.isVisible() and not self.studio.compare.isChecked() else None;self.studio.view.update()
    def showEvent(self,event):super().showEvent(event);self.update_roi()
    def hideEvent(self,event):super().hideEvent(event);self.studio.view.focus_roi=None;self.studio.view.update()
    def poll(self):
        if self.closed:return
        while True:
            try:value=self.updates.get_nowait()
            except queue.Empty:break
            if 'error' in value:
                self.message.setText(value['error']);self.cancel_event.set()
                self.studio.invalidate_stage('舵机控制中断：'+value['error'])
                if self.search:self.search.cancel.set()
            elif value.get('phase')=='sampled':
                self.curve.points=value['points'];self.curve.update();self.message.setText(f"采样 {value['pulse']}µs · 清晰度 {value['score']:.4f} · 已测{len(value['points'])}点")
            else:self.message.setText(f"移动到 {value.get('pulse','')}µs，等待PWM与机械稳定")
        if self.link:
            state=self.link.latest()
            if state:
                age=time.monotonic()-state.received
                mode='失联保持，需手动重新使能' if state.lease_lost else '已使能' if state.enabled else 'PWM关闭'
                self.status.setText(f'设备{state.board} · {mode}\nPWM指令 {state.applied} → {state.target}µs；反馈更新{age:.1f}秒前')
        if self.future is not None and self.future.done():
            future,self.future=self.future,None
            for b in self.action_buttons:b.setEnabled(True)
            for w in self.parameter_widgets:w.setEnabled(True)
            try:
                result=future.result()
                if isinstance(result,dict) and result.get('result')=='focused':
                    folder=self.studio.root/'focus_records';folder.mkdir(exist_ok=True);path=folder/f'AF_{datetime.now():%Y%m%d_%H%M%S_%f}.json';path.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
                    self.target.setValue(result['best_pulse_us']);self.message.setText(f"对焦完成 · 最佳脉宽 {result['best_pulse_us']}µs · 清晰度 {result['score']:.4f}。检测前请重新标定模板。")
                else:self.message.setText(self.label+'完成；PWM状态仅为指令反馈')
            except Exception as exc:
                self.message.setText(str(exc))
                if self.label=='自动对焦' and self.search:
                    folder=self.studio.root/'focus_records';folder.mkdir(exist_ok=True)
                    path=folder/f'AF_{datetime.now():%Y%m%d_%H%M%S_%f}.json'
                    path.write_text(json.dumps({'result':'cancelled' if isinstance(exc,Cancelled) else 'failed','reason':str(exc),'settings':asdict(self.search.p),'points':self.search.points,'position_feedback':False},ensure_ascii=False,indent=2),encoding='utf-8')
            self.search=None
        if hasattr(self,'fixed_message'):self.fixed_message.setText(self.message.text())
    def shutdown(self):
        if self.closed:return
        self.closed=True;self.timer.stop();self.cancel_event.set()
        if self.search:self.search.cancel.set()
        if self.link:self.link.shutdown()
        self.executor.shutdown(wait=False,cancel_futures=True)
