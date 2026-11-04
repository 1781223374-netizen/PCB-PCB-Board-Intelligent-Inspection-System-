"""Three independently bound SCAM channels; Surface13 inspection is unchanged."""
from __future__ import annotations
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
import argparse,json,os,sys,time
import hashlib
import cv2
from PySide6.QtCore import Qt,QTimer
from PySide6.QtGui import QPixmap,QImage
from PySide6.QtWidgets import (QApplication,QMainWindow,QWidget,QVBoxLayout,QHBoxLayout,
    QGridLayout,QLabel,QPushButton,QTabWidget,QDialog,QComboBox,QLineEdit,QFormLayout,QScrollArea)
from pcb_aoi_studio import Studio,configure_application,atomic_json,CompactStatus
from pcb_aoi_core import TemplateMatcher
from multi_receiver import ProcessReceiver
from detection_worker import calculate,DetectorExecutor
from focus_panel import FocusPanel
from network_setup import NetworkService,NetworkProfile,load_json,save_json,elevated_entry

VERSION='1.6.0'

@dataclass(frozen=True)
class Channel:
    id:int
    source:str
    port:int
    mac:str

CHANNELS=tuple(Channel(i,f'192.168.137.{i+1}',16000+i,f'02:23:45:67:89:{170+i:02X}') for i in (1,2,3))

class RouterDialog(QDialog):
    def __init__(self,owner):
        super().__init__(owner)
        self.owner=owner;self.service=NetworkService(owner.root/'network')
        self.executor=ThreadPoolExecutor(max_workers=1,thread_name_prefix='network-setup')
        self.future=None;self.operation='';self.setWindowTitle('TL-WDR8690 路由器接收设置');self.resize(680,420)
        layout=QVBoxLayout(self)
        hint=QLabel('先连接路由器的 5GHz 主 Wi-Fi，再扫描网卡。配置只添加演示地址和本程序三路入站规则，不替换 DHCP、网关或 DNS。不会自动切换 Wi-Fi。')
        hint.setWordWrap(True);layout.addWidget(hint)
        form=QFormLayout();self.ssid=QLineEdit('TP-LINK_AF9E');self.adapters=QComboBox();form.addRow('当前路由器 Wi-Fi 名称',self.ssid);form.addRow('接收网卡',self.adapters);layout.addLayout(form)
        try:
            saved=NetworkProfile.load(self.service.profile_path);self.ssid.setText(saved.ssid);self.saved_guid=saved.adapter_guid
        except Exception:self.saved_guid=''
        self.details=QLabel('尚未扫描');self.details.setWordWrap(True);layout.addWidget(self.details)
        row=QHBoxLayout();self.scan=QPushButton('扫描网卡');self.apply=QPushButton('配置并重新接收');self.restore=QPushButton('恢复本程序配置')
        for b in (self.scan,self.apply,self.restore):row.addWidget(b)
        layout.addLayout(row);self.message=QLabel('PC 接收：192.168.137.1；UDP 16001 / 16002 / 16003。');self.message.setWordWrap(True);layout.addWidget(self.message);layout.addStretch()
        self.scan.clicked.connect(lambda:self.submit('scan',self.service.inventory))
        self.apply.clicked.connect(self.apply_clicked);self.restore.clicked.connect(self.restore_clicked)
        self.timer=QTimer(self);self.timer.timeout.connect(self.poll);self.timer.start(100)

    def submit(self,operation,work):
        if self.future:return
        self.operation=operation;self.future=self.executor.submit(work)
        for b in (self.scan,self.apply,self.restore):b.setEnabled(False)
        self.message.setText('正在扫描…' if operation=='scan' else '正在执行；如出现 Windows 管理员授权提示，请确认本程序。')

    def apply_clicked(self):
        try:profile=NetworkProfile(self.ssid.text().strip(),self.adapters.currentData() or '').validate()
        except ValueError as exc:self.message.setText(str(exc));return
        if not profile.adapter_guid:self.message.setText('请先扫描并选择网卡。');return
        save_json(self.service.profile_path,profile.__dict__)
        # Receiver sockets belong to worker PIDs. Release our three ports before
        # the elevated helper checks for an unrelated application's port use.
        self.owner.stop_receivers()
        handle=int(self.winId());self.submit('apply',lambda:self.service.apply(profile,handle))

    def restore_clicked(self):
        self.owner.stop_receivers()
        handle=int(self.winId());self.submit('restore',lambda:self.service.restore(handle))

    def poll(self):
        if not self.future or not self.future.done():return
        future,self.future=self.future,None
        for b in (self.scan,self.apply,self.restore):b.setEnabled(True)
        try:
            value=future.result()
            if self.operation=='scan':
                self.adapters.clear()
                for a in value['adapters']:
                    if a['up']:
                        ips=', '.join(x['ip'] for x in a['addresses']);self.adapters.addItem(f"{a['name']} · {a.get('ssid','')} · {ips}",a['guid'])
                index=self.adapters.findData(self.saved_guid)
                if index>=0:self.adapters.setCurrentIndex(index)
                self.details.setText('选择当前路由器所在的无线网卡。网卡已有 192.168.137.1 时会复用；若地址在其它网卡，会提示冲突。')
                self.message.setText('扫描完成；尚未修改网络。')
            elif self.operation=='apply':
                self.owner.restart_receivers();self.message.setText('配置完成，已重新监听三个通道；收到真实完整帧后才会显示在线。')
            else:self.message.setText('恢复完成。' if value.get('restored') else '恢复未完成：'+'；'.join(value.get('errors',[])))
        except Exception as exc:
            if self.operation=='apply':self.owner.restart_receivers()
            self.message.setText(str(exc))

    def closeEvent(self,event):
        if self.future:
            self.message.setText('网络操作尚未结束，请等待结果后关闭。');event.ignore();return
        self.timer.stop();self.executor.shutdown(wait=False,cancel_futures=True);event.accept()

class ChannelStudio(Studio):
    def __init__(self,root,channel,bind,listen=True,owner=None):
        self.channel=channel;self.multi_owner=owner;self._startup_loading=True;self._loading_from_startup=False
        try:self.stage_template_dirty=bool(load_json(Path(root)/'stage_state.json',{}).get('needs_template',False))
        except (OSError,ValueError,AttributeError):self.stage_template_dirty=True
        super().__init__(root,bind=bind,port=channel.port,source=channel.source,listen=listen,require_control=False,receiver_factory=lambda config,callback:ProcessReceiver(config,callback,channel.id))
        self.setWindowFlags(Qt.WindowType.Widget)
        self.bind.setEnabled(False);self.port.setEnabled(False);self.source.setReadOnly(True)
        self.remote_port.setEnabled(False)
        self.manage_capture.setChecked(False);self.manage_capture.setEnabled(False)
        self.manage_capture.setText('图传模式 · 通道固定')
        self.setMinimumSize(960,560)
        self.focus_panel=FocusPanel(self);scroll=QScrollArea();scroll.setWidgetResizable(True);scroll.setWidget(self.focus_panel)
        focus_page=QWidget();focus_layout=QVBoxLayout(focus_page);focus_layout.setContentsMargins(0,0,0,0)
        self.focus_stop_button=QPushButton('停止本通道升降 / 保持PWM');self.focus_stop_button.setStyleSheet('background:#7f1d1d; border:1px solid #b91c1c;')
        self.focus_stop_button.clicked.connect(self.focus_panel.cancel);focus_layout.addWidget(self.focus_stop_button)
        self.focus_panel.fixed_message=QLabel('先确认行程，再配置和使能');self.focus_panel.fixed_message.setWordWrap(True);focus_layout.addWidget(self.focus_panel.fixed_message)
        focus_layout.addWidget(scroll,1);self.option_tabs.addTab(focus_page,'升降 / 对焦')
        self.compare.toggled.connect(self.focus_panel.update_roi)
        self._startup_loading=False

    def start_inspection(self):
        if getattr(self,'focus_panel',None) and self.focus_panel.busy:
            self.message.setText('升降台操作尚未结束，请等待或停止后检测');return
        if self.stage_template_dirty:
            self.message.setText('升降位置已改变，请重新标定或加载适合当前高度的模板');return
        owner=self.multi_owner
        if owner and owner.busy_channel(self.channel.id):
            if self.mode not in ('preview','finished'):
                self.message.setText('请先停止本通道当前操作，再加入检测队列。');return
            if self.channel.id not in owner.compute_queue:owner.compute_queue.append(self.channel.id)
            self.verdict.setText('检测已排队 · 其他通道接收继续工作')
            self.message.setText('等待当前通道完成后，使用本通道当时最新的图像开始检测；“停止”可取消排队。')
            self.refresh_controls();return
        super().start_inspection()

    def stop_operation(self):
        if self.multi_owner:self.multi_owner.cancel_request(self.channel.id)
        super().stop_operation()

    def refresh_controls(self):
        super().refresh_controls()
        if self.multi_owner and self.channel.id in self.multi_owner.compute_queue:
            self.start_button.setText('已排队 · 等待检测');self.start_button.setEnabled(False)

    def calibrate_clicked(self):
        if self.focus_panel.busy:self.message.setText('请等待升降台操作结束后标定');return
        if self.multi_owner and self.multi_owner.busy_channel(self.channel.id):
            self.message.setText('另一通道正在计算，请待其完成后再标定；各路接收仍在继续。');return
        super().calibrate_clicked()

    def learn_clicked(self):
        if self.focus_panel.busy:self.message.setText('请等待升降台操作结束');return
        if self.multi_owner and self.multi_owner.busy_channel(self.channel.id):
            self.message.setText('另一通道正在计算，请待其完成后再添加良品。');return
        super().learn_clicked()

    def _template_ready(self,tm,path):
        startup=self.mode=='loading' and self._loading_from_startup
        super()._template_ready(tm,path)
        if not startup:
            self.stage_template_dirty=False
            atomic_json(self.root/'stage_state.json',{'needs_template':False})
        elif self.stage_template_dirty:self.verdict.setText('升降后模板待重新确认 · 请重新标定或手动加载当前高度模板')
        self._loading_from_startup=False

    def invalidate_stage(self,reason):
        self.stop_operation();self.stage_template_dirty=True
        atomic_json(self.root/'stage_state.json',{'needs_template':True,'reason':reason})
        self.verdict.setText('升降位置已改变或未确认 · 检测前请重新标定或加载当前高度模板')

    def _request_load(self,path):
        if getattr(self,'focus_panel',None) and self.focus_panel.busy:
            self.message.setText('升降台操作期间不能切换模板');return
        self._loading_from_startup=getattr(self,'_startup_loading',False)
        super()._request_load(path)

    def closeEvent(self,event):
        if getattr(self,'focus_panel',None):self.focus_panel.shutdown()
        super().closeEvent(event)

    def diagnostic(self):
        result=super().diagnostic();result['stage_needs_template']=self.stage_template_dirty
        result['focus_busy']=self.focus_panel.busy;result['servo_armed_by_pc']=bool(self.focus_panel.link and self.focus_panel.link.armed)
        return result

    def render(self):
        # Hidden tabs still inspect full-resolution frames. Avoid enhancing and
        # copying three full-size display images on the Qt thread every frame.
        if self.isVisible():
            super().render()
        else:self._render_dirty=True

    def _submit(self,kind,sample,function):
        # Build immutable reference features while loading/calibrating, before
        # the live-frame freshness clock starts. Detection math is unchanged.
        use_variation=self.use_variation.isChecked()
        if kind in ('load','calibrate','learning'):
            original=function
            def prepared():
                value=original()
                tm=value[0] if kind=='load' else value[3] if value[0] else None
                if isinstance(tm,TemplateMatcher):
                    # Surface features are needed only by the isolated detector.
                    # Three unused full reference copies in the UI waste memory.
                    if self.multi_owner:
                        path=value[1] if kind=='load' else value[4]
                        digest=hashlib.sha256(Path(path).read_bytes()).hexdigest()
                        prepared=self.multi_owner.detector.submit(calculate,str(Path(path).resolve()),digest,None,None,use_variation).result()
                        self.multi_owner.detector_pid=prepared['pid']
                        self.multi_owner.detector_info=prepared
                return value
            function=prepared
        elif kind=='inspect' and self.multi_owner:
            p=self.session.params
            keys=('k','min_area','min_peak','fixed_threshold','edge_margin','refine','use_variation','variation_cap','surface_mode','scratch_min_length','scratch_response','structure_tolerance','mask_mount_holes','small_structure_response')
            parameters={key:getattr(p,key) for key in keys}
            path=str(self.template_path.resolve());digest=self.template_hash;image=sample[1]
            function=lambda:self.multi_owner.detector.detect(path,digest,image,parameters,p.use_variation)
        super()._submit(kind,sample,function)

class MultiStudio(QMainWindow):
    def __init__(self,root,bind='192.168.137.1',channels=CHANNELS,listen=True):
        super().__init__();self.root=Path(root);self.root.mkdir(parents=True,exist_ok=True)
        # Establish the bounded policy once. Creating another channel must not
        # reconfigure OpenCV while an existing inspection worker is active.
        cv2.setNumThreads(2)
        self.bind=bind;self.channels=channels;self.listen=listen;self.studios={};self.previews={};self.states={};self.network_dialog=None;self.compute_queue=[]
        self.detector=DetectorExecutor();self.detector_pid=None;self.detector_info={}
        self.setWindowTitle(f'PCB AOI Studio {VERSION}');self.setMinimumSize(1040,680)
        screen=QApplication.primaryScreen()
        area=screen.availableGeometry() if screen else None
        self.resize(min(1500,max(1040,area.width()-24)) if area else 1500,
                    min(960,max(680,area.height()-56)) if area else 960)
        if area:self.move(area.x()+max(0,(area.width()-self.width())//2),area.y()+max(0,(area.height()-self.height()-32)//2))
        host=QWidget();outer=QVBoxLayout(host)
        outer.setContentsMargins(10,8,10,6);outer.setSpacing(6)
        head=QHBoxLayout();head.setSpacing(8)
        title=QLabel('PCB AOI');title.setObjectName('title');head.addWidget(title)
        self.start_all_button=QPushButton('全部检测');self.start_all_button.setObjectName('success');self.start_all_button.clicked.connect(self.start_all)
        self.stop_all_button=QPushButton('全部停止');self.stop_all_button.clicked.connect(self.stop_all)
        self.start_all_button.setToolTip('开始检测已就绪通道；换板后再次点击')
        self.stop_all_button.setToolTip('停止全部检测和升降操作，保持当前PWM，继续接收图像')
        head.addWidget(self.start_all_button);head.addWidget(self.stop_all_button);head.addStretch()
        setup=QPushButton('网络设置');setup.setToolTip('路由器 / 无线接收设置');setup.clicked.connect(self.router_settings);head.addWidget(setup)
        outer.addLayout(head)
        self.tabs=QTabWidget();outer.addWidget(self.tabs,1);self.setCentralWidget(host)
        self.notice=CompactStatus('')
        self.notice.setFixedHeight(20);self.notice.setStyleSheet('color:#92a9c2; font-size:11px;')
        outer.addWidget(self.notice)
        overview=QWidget();grid=QGridLayout(overview);self.tabs.addTab(overview,'总览')
        for channel in channels:
            card=QWidget();column=QVBoxLayout(card);name=QLabel(f'通道 {channel.id}');name.setObjectName('title');column.addWidget(name)
            address=QLabel(f'{channel.source} · {channel.port}');address.setToolTip(f'MAC {channel.mac}');column.addWidget(address)
            image=QLabel('等待设备连接 · 尚无完整图像');image.setMinimumSize(300,220);image.setAlignment(Qt.AlignmentFlag.AlignCenter);image.setStyleSheet('background:#080f1b; border:1px solid #2b405d');column.addWidget(image,1);self.previews[channel.id]=image
            state=QLabel('等待完整图像；尚未检测');state.setWordWrap(True);column.addWidget(state);self.states[channel.id]=state
            buttons=QHBoxLayout();detail=QPushButton('进入通道');detail.clicked.connect(lambda checked=False,i=channel.id:self.tabs.setCurrentIndex(i));buttons.addWidget(detail)
            reconnect=QPushButton('重新连接');reconnect.clicked.connect(lambda checked=False,i=channel.id:self.reconnect(i));buttons.addWidget(reconnect);column.addLayout(buttons)
            grid.addWidget(card,0,channel.id-1)
            studio=ChannelStudio(self.root/f'channel_{channel.id:02}',channel,self.bind,self.listen,owner=self)
            self.studios[channel.id]=studio;self.tabs.addTab(studio,f'通道 {channel.id}')
        # All channels are permanent. Old 1.4 enabled=[1] settings must not hide
        # the now-complete channel 2/3 pages or suppress their receivers.
        self.summary_timer=QTimer(self);self.summary_timer.timeout.connect(self.refresh_overview);self.summary_timer.start(500)
        self.tabs.currentChanged.connect(self.show_channel)
        self.refresh_overview()

    def show_channel(self,index):
        if index in self.studios:QTimer.singleShot(0,self.studios[index].render)

    def busy_channel(self,exclude=None):
        return next((i for i,s in self.studios.items() if i!=exclude and (s.mode in ('inspect','calibrate','loading','learning_setup','learning') or s.focus_panel.busy)),None)

    def cancel_request(self,id):
        if id in self.compute_queue:self.compute_queue.remove(id)

    def reconnect(self,id):
        self.studios[id].start_receiver()
        self.previews[id].setPixmap(QPixmap());self.previews[id].setText('正在重新连接 · 等待完整图像')

    def start_all(self):
        started=[];skipped=[]
        for id,studio in self.studios.items():
            if studio.tm is None or not studio.fresh() or studio.mode not in ('preview','finished'):
                skipped.append(str(id));continue
            studio.start_inspection()
            if studio.mode=='inspect' or id in self.compute_queue:started.append(str(id))
            else:skipped.append(str(id))
        self.notice.setText(('已提交通道 '+', '.join(started)+'；按顺序检测。' if started else '没有可开始检测的通道。')+
            (' 通道 '+', '.join(skipped)+' 尚未就绪，请查看对应页面的图像、模板和当前操作。' if skipped else ''))

    def stop_all(self):
        self.compute_queue.clear()
        for studio in self.studios.values():studio.focus_panel.cancel();studio.stop_operation()
        self.notice.setText('全部检测已停止；升降台停止请求已提交，保持当前PWM，三路继续接收。')

    def refresh_overview(self):
        if self.compute_queue and self.busy_channel() is None:
            id=self.compute_queue.pop(0)
            if id in self.studios:self.studios[id].start_inspection()
        for c in self.channels:
            studio=self.studios.get(c.id)
            stats=studio.rx.snapshot() if studio.rx else {}
            live=time.monotonic()-stats.get('last_frame',0)<3
            connection='在线' if live else '等待完整图像'
            verdict=studio.verdict.text() if studio.session else ('预览 / 未开始检测' if studio.current else '尚无画面 / 未开始检测')
            if c.id in self.compute_queue:verdict='已排队 · 等待检测'
            self.states[c.id].setText(f"{connection} · 实收 {(stats.get('fps',0) if live else 0):.1f}fps · 丢帧 {stats.get('dropped',0)}\n{verdict}")
            if stats.get('error'):self.states[c.id].setText('接收失败：'+stats['error'])
            sample=studio.shown or studio.current
            if sample:
                bgr=sample[1];h,w=bgr.shape[:2];scale=min(480/w,270/h)
                thumb=cv2.resize(bgr,(round(w*scale),round(h*scale)),interpolation=cv2.INTER_AREA)
                for region in (studio.last_result.regions if studio.last_result and studio.last_result.ok else []):
                    x,y,x1,y1=[round(v*scale) for v in region.bbox]
                    cv2.rectangle(thumb,(x,y),(x1,y1),(64,64,255),1)
                rgb=cv2.cvtColor(thumb,cv2.COLOR_BGR2RGB)
                qimage=QImage(rgb.data,rgb.shape[1],rgb.shape[0],rgb.strides[0],QImage.Format.Format_RGB888).copy()
                self.previews[c.id].setPixmap(QPixmap.fromImage(qimage).scaled(self.previews[c.id].size(),Qt.AspectRatioMode.KeepAspectRatio,Qt.TransformationMode.SmoothTransformation))

    def stop_receivers(self):
        for studio in self.studios.values():
            studio.focus_panel.cancel()
            studio.stop_operation()
            if studio.rx:studio.rx.stop();studio.rx.join(timeout=1);studio.rx=None

    def restart_receivers(self):
        self.bind='192.168.137.1'
        for studio in self.studios.values():studio.bind.setCurrentText(self.bind);studio.start_receiver()

    def router_settings(self):
        if self.network_dialog is None:self.network_dialog=RouterDialog(self)
        self.network_dialog.show();self.network_dialog.raise_()

    def diagnostic(self):
        return {'version':VERSION,'bind':self.bind,'opencv_threads':cv2.getNumThreads(),'detector_pid':self.detector_pid,'detector_info':self.detector_info,'inspection_schedule':'serial','queued':list(self.compute_queue),'enabled':sorted(self.studios),'channels':{str(i):s.diagnostic() for i,s in self.studios.items()}}

    def closeEvent(self,event):
        if self.network_dialog and self.network_dialog.future:event.ignore();return
        self.summary_timer.stop()
        for studio in self.studios.values():studio.close()
        self.detector.shutdown(wait=False,cancel_futures=True)
        if self.network_dialog:self.network_dialog.close()
        event.accept()

def main():
    parser=argparse.ArgumentParser(description='PCB AOI 三通道工作台')
    parser.add_argument('--data-dir',type=Path);parser.add_argument('--bind',default='192.168.137.1');parser.add_argument('--no-listen',action='store_true')
    parser.add_argument('--network-helper',type=Path,help=argparse.SUPPRESS)
    parser.add_argument('--auto-exit',type=float,default=0,help=argparse.SUPPRESS);parser.add_argument('--status-json',type=Path,help=argparse.SUPPRESS);parser.add_argument('--screenshot',type=Path,help=argparse.SUPPRESS)
    parser.add_argument('--test-loopback-base',type=int,help=argparse.SUPPRESS)
    parser.add_argument('--test-inspect',action='store_true',help=argparse.SUPPRESS)
    parser.add_argument('--test-focus-port',type=int,help=argparse.SUPPRESS)
    args=parser.parse_args()
    if args.network_helper:return elevated_entry(args.network_helper)
    if (args.test_loopback_base is not None or args.test_inspect or args.test_focus_port is not None) and (args.bind!='127.0.0.1' or args.test_loopback_base is None or not 1024<=args.test_loopback_base<=65533):
        parser.error('verification options require 127.0.0.1 and an explicit valid port base')
    if args.test_focus_port is not None and (args.test_inspect or not 1024<=args.test_focus_port<=65535):parser.error('invalid or conflicting loopback focus verification options')
    base=Path(sys.executable).parent if getattr(sys,'frozen',False) else Path(__file__).resolve().parents[1]
    app=QApplication(sys.argv[:1]);configure_application(app)
    channels=CHANNELS if args.test_loopback_base is None else tuple(Channel(i,'127.0.0.1',args.test_loopback_base+i-1,CHANNELS[i-1].mac) for i in (1,2,3))
    window=MultiStudio(args.data_dir or base/'data',args.bind,channels=channels,listen=not args.no_listen);window.show()
    if args.test_inspect:
        test_timer=QTimer(window)
        def start_test():
            if all(s.tm is not None and s.fresh() and s.mode=='preview' for s in window.studios.values()):
                test_timer.stop()
                for s in window.studios.values():s.window.setValue(8);s.confirm.setValue(2)
                QTimer.singleShot(600,window.start_all)
        test_timer.timeout.connect(start_test);test_timer.start(100)
    if args.test_focus_port is not None:
        # Restricted to the explicit localhost verification path above. Normal
        # launches never configure or arm a servo automatically.
        s=window.studios[1];p=s.focus_panel;s.remote_port.setValue(args.test_focus_port)
        p.lower.setValue(1300);p.upper.setValue(1700);p.initial.setValue(1500);p.slew.setValue(20)
        p.search_lower.setValue(1300);p.search_upper.setValue(1700);p.coarse.setValue(200);p.fine.setValue(100)
        p.samples.setValue(2);p.discard.setValue(1);p.settle.setValue(.2);p.confirm.setChecked(True)
        window.tabs.setCurrentIndex(1);s.option_tabs.setCurrentIndex(s.option_tabs.count()-1)
        focus_timer=QTimer(window);focus_stage=[0]
        def advance_focus_test():
            if not s.fresh() or p.busy:return
            stage=focus_stage[0]
            if stage==0:p.query_button.click()
            elif stage==1:
                if not p.link or not p.link.latest():focus_timer.stop();return
                p.configure_button.click()
            elif stage==2:
                if not p.link or not p.link.token or not p.link.latest().configured:focus_timer.stop();return
                p.arm_button.click()
            elif stage==3:
                if not p.link.armed:focus_timer.stop();return
                p.af_button.click();focus_timer.stop()
            focus_stage[0]+=1
        focus_timer.timeout.connect(advance_focus_test);focus_timer.start(100)
    if args.auto_exit:
        def finish():
            if args.status_json:atomic_json(args.status_json,window.diagnostic())
            if args.screenshot:window.grab().save(str(args.screenshot))
            window.close()
        QTimer.singleShot(round(args.auto_exit*1000),finish)
    return app.exec()

if __name__=='__main__':raise SystemExit(main())
