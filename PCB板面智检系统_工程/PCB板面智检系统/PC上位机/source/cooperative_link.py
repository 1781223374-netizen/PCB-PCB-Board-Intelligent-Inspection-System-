"""PC inspection owns the verdict; the FPGA is forced into live capture mode."""
from dataclasses import dataclass
import socket,time
from camera_core import Receiver,Assembler,Frame,STALE_SECONDS
from aoi_protocol import HELLO,STOP,SET_MODE,decode_status,newer
from aoi_link import ControlClient

class StreamGuard:
    def __init__(self,send,nonce=None):
        self.client=ControlClient(send,nonce);self.phase='idle';self.ready=False
        self.reason='等待 FPGA 采集握手';self.epoch=0;self.last_source=None;self.source_at=0.
        self.warm_base=None;self.retry_at=0.
    def block(self,reason,phase=None):
        if self.ready:self.epoch+=1
        self.ready=False;self.reason=reason
        if phase:self.phase=phase
    def connect(self,now):
        self.block('正在连接 FPGA，关闭独立检测','hello')
        self.epoch+=1;self.last_source=None;self.warm_base=None;self.source_at=0.
        self.client.connect(now);self.retry_at=now+2.
    def accept(self,status,now):
        event=self.client.accept(status,now)
        if not event:return
        if event[0]=='reset':
            self.block('FPGA 已复位，正在重新建立采集模式','idle');self.retry_at=now+1.;return
        if self.last_source is not None and self.last_source!=status.source_id and not newer(status.source_id,self.last_source):
            self.block('相机源计数重置，重新确认实时采集','stop')
        if self.last_source!=status.source_id:
            self.last_source=status.source_id;self.source_at=now
        if event[0]=='ack':
            op,code=event[1:]
            if code:
                self.block('FPGA 采集设置未确认：应答 '+str(code),'retry');self.retry_at=now+2.;return
            if op==HELLO:self.phase='stop'
            elif op==STOP:self.phase='mode'
            elif op==SET_MODE:
                if status.mode or status.flags&4:
                    self.block('等待 FPGA 退出独立检测并释放冻结图','stop')
                else:
                    self.phase='warming';self.warm_base=status.source_id
                    self.reason='独立检测已关闭，等待新的实时相机帧'
        if self.phase=='ready' and (status.mode or status.flags&4):
            self.block('检测到板端切回独立模式，暂停 PC 检测并恢复采集','stop')
    def tick(self,now):
        if self.phase=='idle' and now>=self.retry_at:self.connect(now)
        event=self.client.tick(now)
        if event:
            self.block('控制通道未确认，暂停检测并重新握手','retry');self.retry_at=now+2.
        if (self.phase=='retry' or self.phase=='hello' and not self.client.connected) and not self.client.pending and now>=self.retry_at:
            self.connect(now)
        if not self.client.connected:return
        if self.phase in ('stop','mode') and not self.client.pending:
            self.client.issue(STOP if self.phase=='stop' else SET_MODE,mode=False if self.phase=='mode' else None,now=now)
        s=self.client.status
        if s is None:return
        if self.phase=='ready' and now-self.source_at>2.:
            self.block('相机源帧未更新，暂停检测；请返回实时拍摄','warming')
            self.warm_base=s.source_id
        if self.phase=='warming':
            if s.mode or s.flags&4:
                self.block('板端仍在独立检测，正在重新关闭','stop');return
            delta=(s.source_id-(self.warm_base if self.warm_base is not None else s.source_id))&0xffffffff
            if 3<=delta<0x80000000 and now-self.source_at<=2. and now-self.client.last_status<=2.5:
                self.ready=True;self.phase='ready';self.reason='FPGA 纯采集已确认 · 判定由 PC 执行'
    def snapshot(self,now):
        s=self.client.status
        return dict(ready=self.ready,phase=self.phase,reason=self.reason,epoch=self.epoch,
                    source_id=self.last_source,source_age=now-self.source_at if self.last_source is not None else None,
                    fpga_mode=s.mode if s else None,boot_id=s.boot_id if s else None)

@dataclass(frozen=True)
class GuardedFrame(Frame):
    capture_epoch:int=0
    observed_source_id:int=0

class CooperativeReceiver(Receiver):
    cooperative=True
    def __init__(self,settings,on_frame,remote_port=6002):
        super().__init__(settings,on_frame)
        self.remote_port=remote_port
        self.stats.update(control_required=True,control_ready=False,control_epoch=0,
                          control_reason='等待 FPGA 握手',control_phase='idle',
                          status_packets=0,invalid_status=0,forwarded=0,source_repeats=0)
    def run(self):
        sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);self.socket=sock
        try:
            if hasattr(socket,'SO_EXCLUSIVEADDRUSE'):sock.setsockopt(socket.SOL_SOCKET,socket.SO_EXCLUSIVEADDRUSE,1)
            sock.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,8*1024*1024)
            sock.bind((self.config.bind,self.config.port));sock.settimeout(.02)
            peer=(self.config.source or '192.168.137.2',self.remote_port)
            guard=StreamGuard(lambda data:sock.sendto(data,peer))
            with self.lock:self.stats['listening']=True
            start=time.monotonic();nbytes=nframes=0;raw_frames=0
            was_ready=False;last_forwarded_source=None
            while not self.stop_event.is_set():
                now=time.monotonic();guard.tick(now);state=guard.snapshot(now)
                if state['ready']!=was_ready:
                    self.assembler=Assembler();last_forwarded_source=None;was_ready=state['ready']
                with self.lock:
                    self.stats.update(control_ready=state['ready'],control_epoch=state['epoch'],
                      control_reason=state['reason'],control_phase=state['phase'],control_state=state)
                try:data,addr=sock.recvfrom(65535)
                except socket.timeout:
                    self.assembler.expire()
                    with self.lock:
                        if now-self.stats['last_packet']>STALE_SECONDS:self.stats.update(mbps=0.,fps=0.)
                    continue
                except ConnectionResetError:continue
                except OSError:
                    if self.stop_event.is_set():break
                    raise
                now=time.monotonic()
                if addr!=peer:
                    with self.lock:self.stats['ignored']+=1
                    continue
                if data[:4]==b'AOST':
                    try:status=decode_status(data)
                    except ValueError:
                        with self.lock:self.stats['invalid_status']+=1
                        continue
                    guard.accept(status,now)
                    with self.lock:self.stats['status_packets']+=1
                    continue
                if data[:4]!=b'SCAM':
                    with self.lock:self.stats['ignored']+=1
                    continue
                before=self.assembler.invalid
                frame=self.assembler.feed(data,addr,now)
                accepted=self.assembler.invalid==before
                if accepted:nbytes+=len(data)
                if frame:raw_frames+=1;nframes+=1
                with self.lock:
                    if accepted:
                        self.stats['packets']+=1;self.stats['bytes']+=len(data)
                        self.stats.update(last_packet=now,sender=f'{addr[0]}:{addr[1]}')
                    self.stats.update(frames=raw_frames,invalid=self.assembler.invalid,
                        dropped=self.assembler.frames_dropped,duplicates=self.assembler.duplicates)
                    if now-start>=1:
                        self.stats.update(mbps=nbytes*8/(now-start)/1e6,fps=nframes/(now-start))
                        start=now;nbytes=nframes=0
                if not frame or not guard.ready:continue
                sid=guard.last_source
                if sid==last_forwarded_source:
                    with self.lock:self.stats['source_repeats']+=1
                    continue
                last_forwarded_source=sid
                forwarded=GuardedFrame(frame.meta,frame.rgb565,frame.source,frame.received,frame.wall_time,guard.epoch,sid)
                with self.lock:
                    self.stats['last_frame']=now;self.stats['forwarded']+=1
                self.on_frame(forwarded)
        except Exception as exc:
            with self.lock:self.error=f'{self.config.bind}:{self.config.port} · {exc}'
        finally:
            sock.close()
            with self.lock:self.stats.update(listening=False,control_ready=False)

