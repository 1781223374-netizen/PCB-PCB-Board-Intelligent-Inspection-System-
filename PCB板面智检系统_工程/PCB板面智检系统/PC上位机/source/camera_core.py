"""SCAM v1 transport and local persistence; independent of the desktop UI."""
from __future__ import annotations

from collections import OrderedDict
from dataclasses import asdict, dataclass, fields
from datetime import datetime
import csv
import ipaddress
import json
import math
from pathlib import Path
import queue
import socket
import sqlite3
import struct
import threading
import time
import uuid

import numpy as np
from PIL import Image

VERSION = '2.3.0-pcb'
STREAM_RATES = (2,6,8,10,12,15,20)

def rate_command(fps: int) -> bytes:
    if type(fps) is not int or fps not in STREAM_RATES:
        raise ValueError('图传档位必须为 2、6、8、10、12、15 或 20 fps')
    return b'SFPS'+bytes((1,fps,fps^255,0xA5))

def send_rate(fps: int, host: str, port: int=6002):
    ipaddress.IPv4Address(host)
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sock:
        if host=='192.168.137.2':
            # The demo alias is SkipAsSource so normal internet traffic keeps
            # its DHCP source. Board control explicitly uses the demo address.
            try:sock.bind(('192.168.137.1',0))
            except OSError:pass
        sock.sendto(rate_command(fps),(host,port))
HEADER_FMT = '!4sBBHIHHHHIIHH'
HEADER_STRUCT = struct.Struct(HEADER_FMT)
HEADER_LEN = 32
CHUNK = 1408
STALE_SECONDS = 3.0
COCO_EN = ['person','bicycle','car','motorcycle','airplane','bus','train','truck','boat','traffic light','fire hydrant','stop sign','parking meter','bench','bird','cat','dog','horse','sheep','cow','elephant','bear','zebra','giraffe','backpack','umbrella','handbag','tie','suitcase','frisbee','skis','snowboard','sports ball','kite','baseball bat','baseball glove','skateboard','surfboard','tennis racket','bottle','wine glass','cup','fork','knife','spoon','bowl','banana','apple','sandwich','orange','broccoli','carrot','hot dog','pizza','donut','cake','chair','couch','potted plant','bed','dining table','toilet','tv','laptop','mouse','remote','keyboard','cell phone','microwave','oven','toaster','sink','refrigerator','book','clock','vase','scissors','teddy bear','hair drier','toothbrush']
COCO_ZH = ['人','自行车','汽车','摩托车','飞机','公交车','火车','卡车','船','红绿灯','消防栓','停止标志','停车计时器','长椅','鸟','猫','狗','马','羊','牛','大象','熊','斑马','长颈鹿','背包','雨伞','手提包','领带','行李箱','飞盘','滑雪板','单板滑雪','球','风筝','棒球棒','棒球手套','滑板','冲浪板','网球拍','瓶子','酒杯','杯子','叉子','刀','勺子','碗','香蕉','苹果','三明治','橙子','西兰花','胡萝卜','热狗','披萨','甜甜圈','蛋糕','椅子','沙发','盆栽','床','餐桌','马桶','电视','笔记本电脑','鼠标','遥控器','键盘','手机','微波炉','烤箱','烤面包机','水槽','冰箱','书','时钟','花瓶','剪刀','泰迪熊','吹风机','牙刷']


def class_name(index: int) -> str:
    return '全部 80 类' if index == 127 else COCO_ZH[index] if 0 <= index < 80 else '未知类别'


@dataclass
class Settings:
    bind: str = '0.0.0.0'
    port: int = 16001
    source: str = ''
    auto_start: bool = True
    sound: bool = True
    alarm_capture: bool = True
    cooldown: float = 3.0
    record_fps: float = 2.0
    stream_fps: int = 8

    def validate(self):
        rate_command(self.stream_fps)
        ipaddress.IPv4Address(self.bind)
        if self.source:
            ipaddress.IPv4Address(self.source)
        if type(self.port) is not int or not 1 <= self.port <= 65535:
            raise ValueError('端口必须为 1–65535 的整数')
        for key in ['auto_start','sound','alarm_capture']:
            if type(getattr(self,key)) is not bool:
                raise ValueError('开关设置无效')
        if not math.isfinite(self.cooldown) or not 0 <= self.cooldown <= 60:
            raise ValueError('报警冷却必须为 0–60 秒')
        if not math.isfinite(self.record_fps) or not 0.5 <= self.record_fps <= 30:
            raise ValueError('录像帧率必须为 0.5–30 fps')
        return self

    @classmethod
    def load(cls, path: Path):
        if not path.exists():
            return cls()
        data = json.loads(path.read_text(encoding='utf-8'))
        return cls(**{f.name:data[f.name] for f in fields(cls) if f.name in data}).validate()

    def save(self, path: Path):
        self.validate()
        path.parent.mkdir(parents=True, exist_ok=True)
        temp = path.with_suffix('.tmp')
        temp.write_text(json.dumps(asdict(self),ensure_ascii=False,indent=2),encoding='utf-8')
        temp.replace(path)


@dataclass(frozen=True)
class FrameMeta:
    frame_id: int
    width: int
    height: int
    flags: int
    target_class: int
    total_bytes: int
    packet_count: int

    @property
    def armed(self): return bool(self.flags & 1)
    @property
    def active(self): return bool(self.flags & 2)

    @property
    def stream_fps(self):
        rate=(self.flags>>8)&255
        return rate if rate in STREAM_RATES else 0


@dataclass(frozen=True)
class Frame:
    meta: FrameMeta
    rgb565: bytes
    source: str = ''
    received: float = 0.0
    wall_time: float = 0.0

    def rgb(self):
        px = np.frombuffer(self.rgb565,dtype='<u2').reshape(self.meta.height,self.meta.width)
        rgb = np.empty((*px.shape,3),dtype=np.uint8)
        # Match the existing receiver's RGB565 expansion exactly.
        rgb[:,:,0] = (px >> 11) << 3
        rgb[:,:,1] = ((px >> 5) & 63) << 2
        rgb[:,:,2] = (px & 31) << 3
        return rgb

    def image(self): return Image.fromarray(self.rgb())


class Assembler:
    """Bounded, source-isolated reassembly with strict offset/length validation."""
    def __init__(self):
        self.partials = OrderedDict()
        self.completed = OrderedDict()
        self.frames_ok = self.frames_dropped = self.invalid = self.duplicates = 0
        self.last_maintenance = -math.inf

    def expire(self, now=None):
        now = time.monotonic() if now is None else now
        self.last_maintenance = now
        for key in [k for k,v in self.partials.items() if now-v['started'] > 2.0]:
            del self.partials[key]
            self.frames_dropped += 1
        for key in [k for k,t in self.completed.items() if now-t > 4.0]:
            del self.completed[key]

    def feed(self, data: bytes, source=('127.0.0.1',6002), now=None):
        now = time.monotonic() if now is None else now
        # At 20 fps there are 17,460 packets/s. Expiring the entire recent-frame
        # table for every packet wastes receive time and grows with frame rate.
        if now-self.last_maintenance>=.1:self.expire(now)
        if len(data) < 32:
            self.invalid += 1
            return None
        magic,version,fmt,flags,fid,w,h,idx,count,offset,total,n,reserved = HEADER_STRUCT.unpack_from(data)
        expected_count = (total+CHUNK-1)//CHUNK
        target = reserved & 127
        if (magic != b'SCAM' or version != 1 or fmt != 1 or not 1 <= w <= 4096 or not 1 <= h <= 2160
            or total != w*h*2 or total > 16*1024*1024 or count != expected_count or not 0 <= idx < count
            or offset != idx*CHUNK or n != min(CHUNK,total-offset) or len(data) != 32+n
            or not (target < 80 or target == 127)):
            self.invalid += 1
            return None
        key = (source,fid)
        if key in self.completed:
            self.duplicates += 1
            return None
        signature = (w,h,count,total)
        item = self.partials.get(key)
        if item and now-item['started']>2.0:
            del self.partials[key];self.frames_dropped+=1;item=None
        if item and item['signature'] != signature:
            self.invalid += 1
            return None
        if item is None:
            while len(self.partials) >= 3:
                self.partials.popitem(last=False)
                self.frames_dropped += 1
            item = dict(started=now,signature=signature,packets={},meta_idx=-1,flags=flags,target=target)
            self.partials[key] = item
        payload = data[32:]
        if idx in item['packets']:
            self.duplicates += 1
            if item['packets'][idx] != payload: self.invalid += 1
            return None
        item['packets'][idx] = payload
        # The existing board updates metadata live. Use the highest packet index,
        # rather than arrival order, so reordered packets cannot undo alarm flags.
        if idx > item['meta_idx']:
            item.update(meta_idx=idx,flags=flags,target=target)
        if len(item['packets']) != count:
            return None
        raw = b''.join(item['packets'][i] for i in range(count))
        del self.partials[key]
        self.completed[key] = now
        while len(self.completed)>128: self.completed.popitem(last=False)
        self.frames_ok += 1
        return Frame(FrameMeta(fid,w,h,item['flags'],item['target'],total,count),raw,
                     f'{source[0]}:{source[1]}',now,time.time())


class AlarmTracker:
    def __init__(self, cooldown=3.0):
        self.cooldown = cooldown
        self.reset()

    def reset(self):
        self.active=False; self.last_alarm=-math.inf; self.last_frame=-math.inf; self.identity=None

    def accept(self, frame: Frame):
        now=frame.received
        identity=(frame.source,frame.meta.target_class)
        if now-self.last_frame>STALE_SECONDS or identity!=self.identity:
            self.active=False
        active=frame.meta.armed and frame.meta.active and frame.meta.target_class<80
        fire=active and not self.active and now-self.last_alarm>=self.cooldown
        self.active=active;self.last_frame=now;self.identity=identity
        if fire:self.last_alarm=now
        return fire


class Receiver(threading.Thread):
    def __init__(self, settings: Settings, on_frame, packet_hook=None):
        super().__init__(daemon=True,name='camera-udp')
        self.config=settings; self.on_frame=on_frame; self.packet_hook=packet_hook; self.stop_event=threading.Event()
        self.assembler=Assembler();self.lock=threading.Lock();self.error='';self.socket=None
        self.stats=dict(packets=0,bytes=0,frames=0,dropped=0,invalid=0,duplicates=0,mbps=0.,fps=0.,
                        last_packet=0.,last_frame=0.,sender='',listening=False,ignored=0)

    def snapshot(self):
        with self.lock:return dict(self.stats,error=self.error)

    def stop(self):
        self.stop_event.set()
        if self.socket:
            try:self.socket.close()
            except OSError:pass

    def run(self):
        sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        self.socket=sock
        try:
            # Exclusive bind surfaces a second viewer using the same port.
            if hasattr(socket,'SO_EXCLUSIVEADDRUSE'):sock.setsockopt(socket.SOL_SOCKET,socket.SO_EXCLUSIVEADDRUSE,1)
            sock.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,8*1024*1024)
            sock.bind((self.config.bind,self.config.port));sock.settimeout(.2)
            with self.lock:self.stats['listening']=True
            start=time.monotonic();nbytes=nframes=0;peer=None;peer_since=0.
            while not self.stop_event.is_set():
                try:data,addr=sock.recvfrom(65535)
                except socket.timeout:
                    self.assembler.expire()
                    with self.lock:
                        self.stats['dropped']=self.assembler.frames_dropped
                        if time.monotonic()-self.stats['last_packet']>STALE_SECONDS:self.stats.update(mbps=0.,fps=0.)
                    continue
                except OSError:
                    if self.stop_event.is_set():break
                    raise
                now=time.monotonic()
                last_complete=max(self.stats['last_frame'],peer_since)
                if peer and now-last_complete>STALE_SECONDS:
                    peer=None
                if (self.config.source and addr[0]!=self.config.source) or (peer and addr!=peer):
                    with self.lock:self.stats['ignored']+=1
                    continue
                if self.packet_hook is not None and self.packet_hook(data,addr,now):continue
                prior_invalid=self.assembler.invalid
                frame=self.assembler.feed(data,addr,now)
                valid=self.assembler.invalid==prior_invalid
                accepted=valid and len(data)>=32 and data[:4]==b'SCAM'
                if accepted:
                    if peer is None:peer=addr;peer_since=now
                    nbytes+=len(data)
                if frame:
                    nframes+=1
                with self.lock:
                    if accepted:
                        self.stats['packets']+=1;self.stats['bytes']+=len(data)
                        self.stats.update(last_packet=now,sender=f'{addr[0]}:{addr[1]}')
                    if frame:self.stats['last_frame']=now
                    self.stats.update(frames=self.assembler.frames_ok,dropped=self.assembler.frames_dropped,
                                      invalid=self.assembler.invalid,duplicates=self.assembler.duplicates)
                    if now-start>=1:
                        self.stats.update(mbps=nbytes*8/(now-start)/1e6,fps=nframes/(now-start))
                        start=now;nbytes=nframes=0
                if frame:self.on_frame(frame)
        except Exception as exc:
            with self.lock:self.error=f'{self.config.bind}:{self.config.port} · {exc}'
        finally:
            sock.close()
            with self.lock:self.stats['listening']=False


class Storage:
    def __init__(self, root: Path):
        self.root=root;root.mkdir(parents=True,exist_ok=True)
        self.lock=threading.RLock()
        self.db=sqlite3.connect(root/'studio.db',check_same_thread=False)
        self.db.row_factory=sqlite3.Row
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.executescript('''CREATE TABLE IF NOT EXISTS media(
         id TEXT PRIMARY KEY,time TEXT,kind TEXT,path TEXT,frame_id INTEGER,width INTEGER,height INTEGER,bytes INTEGER);
         CREATE TABLE IF NOT EXISTS events(id TEXT PRIMARY KEY,time TEXT,class_id INTEGER,frame_id INTEGER,
         source TEXT,shot TEXT,acked INTEGER DEFAULT 0);
         CREATE INDEX IF NOT EXISTS events_time ON events(time);''')
        self.db.commit()

    def capture(self, frame: Frame, alarm=False):
        now=datetime.now();folder=self.root/'captures'/now.strftime('%Y-%m-%d');folder.mkdir(parents=True,exist_ok=True)
        path=folder/f'{"ALARM" if alarm else "SHOT"}_{now:%H%M%S_%f}.png'
        frame.image().save(path)
        self.add_media(path,'alarm' if alarm else 'photo',frame)
        return path

    def add_media(self,path,kind,frame):
        with self.lock:
            self.db.execute('INSERT INTO media VALUES(?,?,?,?,?,?,?,?)',(uuid.uuid4().hex,datetime.now().isoformat(timespec='seconds'),
                kind,str(path),frame.meta.frame_id,frame.meta.width,frame.meta.height,path.stat().st_size))
            self.db.commit()

    def alarm(self,frame,capture=True):
        shot=str(self.capture(frame,True)) if capture else ''
        event=dict(id=uuid.uuid4().hex,time=datetime.now().isoformat(timespec='seconds'),class_id=frame.meta.target_class,
                   frame_id=frame.meta.frame_id,source=frame.source,shot=shot,acked=0)
        with self.lock:
            self.db.execute('INSERT INTO events VALUES(:id,:time,:class_id,:frame_id,:source,:shot,:acked)',event);self.db.commit()
            with (self.root/'alarm_log.jsonl').open('a',encoding='utf-8') as f:f.write(json.dumps(event,ensure_ascii=False)+'\n')
            csv_path=self.root/'alarm_log.csv';new=not csv_path.exists()
            with csv_path.open('a',newline='',encoding='utf-8-sig' if new else 'utf-8') as f:
                w=csv.writer(f)
                if new:w.writerow(['时间','类别','帧号','来源','截图','事件ID'])
                w.writerow([event['time'],class_name(event['class_id']),event['frame_id'],event['source'],shot,event['id']])
        return event

    def events(self,query='',status='all'):
        sql='SELECT * FROM events WHERE (time LIKE ? OR source LIKE ? OR CAST(frame_id AS TEXT) LIKE ?)'
        args=['%'+query+'%']*3
        # Class search is resolved locally because protocol labels are not stored twice.
        if query and any(query.lower() in (COCO_ZH[i]+' '+COCO_EN[i]).lower() for i in range(80)):
            ids=[i for i in range(80) if query.lower() in (COCO_ZH[i]+' '+COCO_EN[i]).lower()]
            sql='SELECT * FROM events WHERE class_id IN ('+','.join('?'*len(ids))+')';args=ids
        if status!='all':sql+=' AND acked=?';args.append(int(status=='acked'))
        with self.lock:return [dict(r) for r in self.db.execute(sql+' ORDER BY time DESC,rowid DESC LIMIT 1000',args)]

    def media(self,kind='all'):
        with self.lock:return [dict(r) for r in self.db.execute('SELECT * FROM media '+('' if kind=='all' else 'WHERE kind=? ')+
                                      'ORDER BY time DESC,rowid DESC LIMIT 300',() if kind=='all' else (kind,))]

    def acknowledge(self,ids):
        with self.lock:
            self.db.executemany('UPDATE events SET acked=1 WHERE id=?',[(i,) for i in ids]);self.db.commit()

    def counts(self):
        with self.lock:
            e=self.db.execute('SELECT COUNT(*),SUM(acked=0) FROM events').fetchone()
            return dict(events=e[0],unacked=e[1] or 0,media=self.db.execute('SELECT COUNT(*) FROM media').fetchone()[0])

    def close(self):
        with self.lock:self.db.close()


class VideoRecorder:
    """MJPEG with configured wall-clock cadence; duplicates held images as needed."""
    def __init__(self,storage):self.storage=storage;self.writer=None;self.path=None;self.written=0;self.last=None
    def start(self,frame,fps):
        import cv2
        folder=self.storage.root/'recordings';folder.mkdir(exist_ok=True)
        self.path=folder/f'REC_{datetime.now():%Y%m%d_%H%M%S_%f}.avi'
        self.writer=cv2.VideoWriter(str(self.path),cv2.VideoWriter_fourcc(*'MJPG'),fps,(frame.meta.width,frame.meta.height))
        if not self.writer.isOpened():
            self.writer.release();self.writer=None;raise RuntimeError('录像编码器打开失败，请检查保存目录和磁盘空间')
        self.fps=fps;self.started=frame.received;self.written=0;self.last=frame
        self.add(frame)
    def add(self,frame):
        if not self.writer:return
        if (frame.meta.width,frame.meta.height)!=(self.last.meta.width,self.last.meta.height):
            self.stop();raise RuntimeError('画面尺寸改变，录像已结束')
        if frame.received-self.last.received>STALE_SECONDS:
            self.stop();raise RuntimeError('图像流中断，录像已结束')
        slot=int((frame.received-self.started)*self.fps+1e-4)
        if slot<self.written:
            self.last=frame
            return
        # Intermediate slots hold the previous frame; the arrival slot uses the new image.
        import cv2
        previous=cv2.cvtColor(self.last.rgb(),cv2.COLOR_RGB2BGR)
        while self.written<slot:
            self.writer.write(previous);self.written+=1
        self.writer.write(cv2.cvtColor(frame.rgb(),cv2.COLOR_RGB2BGR));self.written+=1;self.last=frame
    def stop(self):
        if not self.writer:return None
        self.writer.release();self.writer=None
        self.storage.add_media(self.path,'video',self.last)
        return self.path


class MediaWorker(threading.Thread):
    def __init__(self,storage,notices):
        super().__init__(daemon=False,name='camera-files')
        self.storage=storage;self.notices=notices;self.jobs=queue.Queue(maxsize=48)
        self.recorder=VideoRecorder(storage);self.recording=False;self.finish=threading.Event()
    def submit(self,kind,payload=None):
        try:self.jobs.put_nowait((kind,payload));return True
        except queue.Full:
            self.notices.put(('error','磁盘处理繁忙，本次操作未提交'));return False
    def run(self):
        while not self.finish.is_set() or not self.jobs.empty():
            try:kind,payload=self.jobs.get(timeout=.2)
            except queue.Empty:
                if self.recording and time.monotonic()-self.recorder.last.received>STALE_SECONDS:
                    try:
                        path=self.recorder.stop();self.notices.put(('record_stop',str(path)))
                    except Exception as exc:self.notices.put(('error','录像收尾失败：'+str(exc)))
                    self.recording=False
                continue
            try:
                if kind=='alarm':
                    frame,capture=payload;self.notices.put(('alarm_saved',self.storage.alarm(frame,capture)))
                elif kind=='photo':self.notices.put(('photo_saved',str(self.storage.capture(payload))))
                elif kind=='record_start':
                    self.recorder.start(*payload);self.recording=True;self.notices.put(('record_start',str(self.recorder.path)))
                elif kind=='record_frame' and self.recording:self.recorder.add(payload)
                elif kind=='record_stop':
                    path=self.recorder.stop();self.recording=False;self.notices.put(('record_stop',str(path or '')))
            except Exception as exc:
                if self.recorder.writer:
                    try:self.recorder.stop()
                    except Exception:pass
                self.recording=False;self.notices.put(('error',str(exc)))
            finally:self.jobs.task_done()
        if self.recording:
            try:self.recorder.stop()
            except Exception as exc:self.notices.put(('error','录像收尾失败：'+str(exc)))
            self.recording=False
