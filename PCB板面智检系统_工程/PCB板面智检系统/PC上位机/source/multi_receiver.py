"""One independent packet-assembly process per channel, original SCAM decoder.

Only complete Frame objects cross IPC. The Qt process never parses three packet
streams under one Python interpreter lock. Image pixels and timestamps are kept.
"""
import multiprocessing as mp
from multiprocessing import shared_memory
import queue,threading,time
from dataclasses import asdict
from camera_core import Receiver,Settings,Frame
from focus_protocol import decode_status

def _latest(target,value):
    try:target.put_nowait(value);return
    except queue.Full:pass
    try:target.get_nowait()
    except queue.Empty:pass
    try:target.put_nowait(value)
    except queue.Full:pass

CAPACITY=1920*1080*2

def _receive(config,frames,status,stop,name,locks,sequences,board_id):
    memory=shared_memory.SharedMemory(name=name);counter=0
    control={'servo_status':None,'servo_invalid':0}
    def packet_hook(data,addr,now):
        if data[:4]!=b'SVST':return False
        try:control['servo_status']=asdict(decode_status(data,board_id,now))
        except ValueError:control['servo_invalid']+=1
        return True
    def publish(frame):
        nonlocal counter
        if len(frame.rgb565)>CAPACITY:raise ValueError('多通道接收支持最高1920x1080 RGB565')
        counter+=1;slot=counter%2;offset=slot*CAPACITY
        with locks[slot]:
            memory.buf[offset:offset+len(frame.rgb565)]=frame.rgb565
            sequences[slot]=counter
        _latest(frames,(frame.meta,frame.source,frame.received,frame.wall_time,slot,counter,len(frame.rgb565)))
    rx=Receiver(Settings(**config),publish,packet_hook=packet_hook)
    try:
        rx.start()
        while not stop.wait(.08):_latest(status,dict(rx.snapshot(),**control))
    finally:
        rx.stop();rx.join(timeout=1)
        frames.cancel_join_thread();status.cancel_join_thread();memory.close()

class ProcessReceiver:
    cooperative=False
    def __init__(self,config,callback,board_id=None):
        self.config=config;self.callback=callback;self.board_id=board_id;self.context=mp.get_context('spawn')
        self.frames=self.context.Queue(maxsize=2);self.status=self.context.Queue(maxsize=3)
        self.memory=shared_memory.SharedMemory(create=True,size=CAPACITY*2)
        self.slot_locks=[self.context.Lock(),self.context.Lock()];self.sequences=self.context.Array('Q',2,lock=False)
        self.child_stop=self.context.Event();self.parent_stop=threading.Event();self.lock=threading.Lock()
        self.process=None;self.bridge=None
        self.stats=dict(packets=0,bytes=0,frames=0,dropped=0,invalid=0,duplicates=0,mbps=0.,fps=0.,last_packet=0.,last_frame=0.,sender='',listening=False,ignored=0,error='')

    def start(self):
        self.process=self.context.Process(target=_receive,args=(asdict(self.config),self.frames,self.status,self.child_stop,self.memory.name,self.slot_locks,self.sequences,self.board_id),daemon=True,name=f'SCAM-{self.config.port}')
        try:self.process.start()
        except Exception as exc:
            self.stats['error']='无法启动接收进程：'+str(exc);return
        self.bridge=threading.Thread(target=self.run,daemon=True,name=f'SCAM-frames-{self.config.port}');self.bridge.start()

    def run(self):
        while not self.parent_stop.is_set():
            try:
                meta,source,received,wall,slot,sequence,length=self.frames.get(timeout=.08)
                if self.slot_locks[slot].acquire(timeout=.2):
                    try:
                        if self.sequences[slot]==sequence:
                            offset=slot*CAPACITY;raw=bytes(self.memory.buf[offset:offset+length])
                        else:raw=None
                    finally:self.slot_locks[slot].release()
                    if raw is not None:self.callback(Frame(meta,raw,source,received,wall))
            except queue.Empty:pass
            except (EOFError,OSError):break
            latest=None
            while True:
                try:latest=self.status.get_nowait()
                except queue.Empty:break
                except (EOFError,OSError):break
            if latest is not None:
                with self.lock:self.stats=latest
            if self.process.exitcode is not None:
                if not self.child_stop.is_set():
                    with self.lock:self.stats['error']=f'接收进程已退出（{self.process.exitcode}）';self.stats['listening']=False
                break

    def snapshot(self):
        with self.lock:return dict(self.stats,receiver_pid=self.process.pid if self.process else None,transport='process_shared_memory')

    def stop(self):self.parent_stop.set();self.child_stop.set()

    def join(self,timeout=1):
        if self.process and self.process.pid:
            self.process.join(timeout=max(1,timeout))
            if self.process.is_alive():self.process.terminate();self.process.join(timeout=1)
        if self.bridge:self.bridge.join(timeout=.25)
        self.frames.close();self.status.close();self.memory.close();self.memory.unlink()
