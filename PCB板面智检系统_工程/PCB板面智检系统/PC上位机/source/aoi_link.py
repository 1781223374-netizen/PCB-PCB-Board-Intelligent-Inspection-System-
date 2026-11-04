"""A single socket receives SCAM images/AOST readback and sends AOI commands."""
from collections import OrderedDict
from dataclasses import dataclass
import queue,secrets,socket,threading,time
from camera_core import Assembler
from aoi_protocol import *

@dataclass
class Pending:
    op:int;seq:int;packet:bytes;started:float;last_sent:float;attempts:int=1

class ControlClient:
    def __init__(self,send,nonce=None):
        self.send=send;self.nonce=nonce or (lambda:secrets.randbelow(0xffffffff)+1)
        self.client=0;self.cookie=0;self.boot=0;self.ack_seq=0;self.pending=None
        self.status=None;self.last_status=0.;self.connected=False;self.faulted=False;self.last_status_seq=None
    def connect(self,now=None):
        now=time.monotonic() if now is None else now
        self.client=self.nonce();self.cookie=0;self.boot=0;self.ack_seq=0;self.status=None
        self.connected=False;self.faulted=False;self.last_status_seq=None
        packet=command(HELLO,self.client,1)
        self.pending=Pending(HELLO,1,packet,now,now);self.send(packet)
    def issue(self,op,params=None,mode=None,now=None):
        if not self.connected or self.faulted:raise ValueError('请先连接 FPGA 控制通道')
        if self.pending:raise ValueError('上一条指令尚未确认')
        now=time.monotonic() if now is None else now
        seq=self.ack_seq+1
        if seq>=2**32:raise ValueError('命令序号已用完，请重新连接')
        packet=command(op,self.client,seq,self.cookie,params,mode)
        self.pending=Pending(op,seq,packet,now,now);self.send(packet)
    def accept(self,status,now=None):
        now=time.monotonic() if now is None else now
        if self.connected and status.client==0 and status.cookie==0 and status.boot_id==0:
            self.connected=False;self.faulted=True;self.pending=None
            return ('reset','FPGA 已复位，请重新连接并核对模板')
        if self.faulted or status.client!=self.client or status.cookie==0 or status.boot_id==0:return None
        handshaking=self.pending is not None and self.pending.op==HELLO
        if not handshaking and (status.cookie!=self.cookie or status.boot_id!=self.boot):return None
        if self.last_status_seq is not None and not newer(status.status_seq,self.last_status_seq):return None
        if handshaking:
            if status.ack_seq!=1 or status.ack_op!=HELLO or status.ack_code!=0:return None
            self.cookie=status.cookie;self.boot=status.boot_id
        self.status=status;self.last_status_seq=status.status_seq;self.last_status=now;self.connected=True
        if self.pending and status.ack_seq==self.pending.seq and status.ack_op==self.pending.op:
            op=self.pending.op;self.ack_seq=status.ack_seq;self.pending=None
            return ('ack',op,status.ack_code)
        return ('status',)
    def tick(self,now=None):
        now=time.monotonic() if now is None else now
        if self.pending:
            if now-self.pending.started>=5:
                op=self.pending.op;self.pending=None;self.connected=False;self.faulted=True
                return ('timeout',op,'指令未确认；FPGA 可能已执行。请重新连接并读取状态。')
            if now-self.pending.last_sent>=.5:
                self.send(self.pending.packet);self.pending.last_sent=now;self.pending.attempts+=1
        if self.connected and now-self.last_status>2.5:
            self.connected=False
            return ('stale','控制状态超时，当前判定不可用；请检查连接')
        return None

class UdpLink(threading.Thread):
    def __init__(self,bind,port,host,remote_port=6002):
        super().__init__(daemon=True,name='fpga-aoi-udp')
        self.bind=bind;self.port=port;self.peer=(host,remote_port)
        self.events=queue.Queue();self.outbox=queue.Queue();self.stop_event=threading.Event();self.sock=None
        self.lock=threading.Lock();self.frames=OrderedDict();self.latest=None;self.assembler=Assembler()
        self.stats=dict(images=0,image_packets=0,status_packets=0,invalid_status=0,ignored=0,error='',listening=False)
    def send(self,data):self.outbox.put(bytes(data))
    def stop(self):
        self.stop_event.set()
        if self.sock:
            try:self.sock.close()
            except OSError:pass
    def clear_images(self):
        with self.lock:self.frames.clear();self.latest=None;self.assembler=Assembler()
    def frame(self,fid):
        with self.lock:return self.frames.get(fid)
    def latest_frame(self):
        with self.lock:return self.latest
    def snapshot(self):
        with self.lock:return dict(self.stats,dropped=self.assembler.frames_dropped,invalid_images=self.assembler.invalid)
    def run(self):
        sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);self.sock=sock
        try:
            if hasattr(socket,'SO_EXCLUSIVEADDRUSE'):sock.setsockopt(socket.SOL_SOCKET,socket.SO_EXCLUSIVEADDRUSE,1)
            sock.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,8*1024*1024)
            sock.bind((self.bind,self.port));sock.settimeout(.015)
            with self.lock:self.stats['listening']=True
            while not self.stop_event.is_set():
                while not self.outbox.empty():sock.sendto(self.outbox.get_nowait(),self.peer)
                try:data,addr=sock.recvfrom(65535)
                except socket.timeout:
                    with self.lock:self.assembler.expire()
                    continue
                if addr!=self.peer:
                    with self.lock:self.stats['ignored']+=1
                    continue
                if data[:4]==b'AOST':
                    try:status=decode_status(data)
                    except ValueError:
                        with self.lock:self.stats['invalid_status']+=1
                        continue
                    with self.lock:self.stats['status_packets']+=1
                    self.events.put(('status',status,time.monotonic()))
                elif data[:4]==b'SCAM':
                    with self.lock:
                        self.stats['image_packets']+=1
                        frame=self.assembler.feed(data,addr)
                        if frame:
                            self.frames[frame.meta.frame_id]=frame;self.latest=frame;self.stats['images']+=1
                            while len(self.frames)>24:self.frames.popitem(last=False)
        except OSError as exc:
            if not self.stop_event.is_set():
                with self.lock:self.stats['error']=str(exc)
                self.events.put(('error',str(exc)))
        finally:
            with self.lock:self.stats['listening']=False
            sock.close()

def paired_frame(link,status,not_before=0.):
    if not status.terminal or not status.flags&4 or status.paired_run!=status.run_id or status.paired_image==0:return None
    frame=link.frame(status.paired_image)
    if frame is None or frame.received<not_before or (frame.meta.width,frame.meta.height)!=(1024,600):return None
    return frame
