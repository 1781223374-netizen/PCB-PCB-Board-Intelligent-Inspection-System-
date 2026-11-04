"""PC focus scoring/search. PWM is a command, never measured lift height."""
from dataclasses import asdict,dataclass
from pathlib import Path
import json,math,secrets,socket,threading,time
import cv2,numpy as np
from focus_protocol import Command,ServoStatus,command_bytes,ERRORS

class FocusError(RuntimeError):pass
class Cancelled(FocusError):pass

@dataclass(frozen=True)
class FocusSettings:
    lower:int=500;upper:int=2500;start:int=1500;slew:int=5
    coarse:int=250;fine:int=50;settle:float=.5;samples:int=3;discard:int=1
    roi:tuple=(.35,.35,.3,.3)
    def validate(self,search=True):
        if not (500<=self.lower<self.upper<=2500 and self.lower<=self.start<=self.upper and 1<=self.slew<=20):raise ValueError('行程或初始脉宽无效')
        if not search:return self
        if not (5<=self.fine<self.coarse<=1000 and self.coarse<=self.upper-self.lower and .2<=self.settle<=5 and 2<=self.samples<=7 and 1<=self.discard<=5):raise ValueError('搜索步长、稳定时间或采样数无效')
        x,y,w,h=self.roi
        if not all(math.isfinite(v) for v in self.roi) or not (0<=x<1 and 0<=y<1 and .05<=w<=1-x and .05<=h<=1-y):raise ValueError('对焦ROI超出画面')
        if math.ceil((self.upper-self.lower)/self.coarse)+math.ceil(2*self.coarse/self.fine)>90:raise ValueError('采样点过多，请增大搜索步长')
        return self

def focus_score(bgr,roi):
    h,w=bgr.shape[:2];x,y,rw,rh=roi
    crop=bgr[round(y*h):round((y+rh)*h),round(x*w):round((x+rw)*w)]
    if crop.shape[0]<24 or crop.shape[1]<24:raise FocusError('对焦区域过小')
    gray=cv2.cvtColor(crop,cv2.COLOR_BGR2GRAY)
    if np.mean((gray<=3)|(gray>=252))>.6:raise FocusError('对焦区域严重过曝/过暗，请选择板上走线/文字区域')
    if float(np.std(gray))<1:return 0.
    smooth=cv2.GaussianBlur(gray,(3,3),.7)
    gx=cv2.Sobel(smooth,cv2.CV_32F,1,0,ksize=3);gy=cv2.Sobel(smooth,cv2.CV_32F,0,1,ksize=3)
    energy=gx*gx+gy*gy
    # Robust Tenengrad; cap isolated glare and normalize overall exposure only.
    energy=np.minimum(energy,float(np.percentile(energy,99.5)))
    return float(np.mean(energy)/max(20.,float(np.mean(gray)))**2)

class ServoLink:
    def __init__(self,board,host,bind,status_provider,on_error=None,port=6002):
        self.board=board;self.host=host;self.port=port;self.bind=bind;self.status_provider=status_provider;self.on_error=on_error or (lambda text:None)
        self.token=0;self.seq=0;self.config=FocusSettings();self.armed=False
        self.lock=threading.RLock();self.stop=threading.Event();self.socket=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        self.socket.bind((bind,0))
        self.thread=threading.Thread(target=self._heartbeat,daemon=True,name=f'servo-lease-{board}');self.thread.start()
    def latest(self):
        value=self.status_provider()
        return ServoStatus(**value) if value else None
    def request(self,op,cancel=None,timeout=.7,retries=2,target=None):
        with self.lock:
            self.seq=(self.seq+1)&0xffffffff or 1;seq=self.seq;p=self.config
            packet=command_bytes(self.board,op,0 if op==Command.QUERY else self.token,seq,p.lower,p.upper,p.start if target is None else target,p.slew)
            sent_at=time.monotonic()
            for attempt in range(retries):
                self.socket.sendto(packet,(self.host,self.port));deadline=time.monotonic()+timeout
                while time.monotonic()<deadline:
                    if cancel is not None and cancel.is_set():raise Cancelled('已取消对焦')
                    status=self.latest()
                    if status and status.seq==seq and status.received>=sent_at and (op==Command.QUERY or status.token==self.token or status.error):
                        if status.error:raise FocusError(ERRORS.get(status.error,f'舵机错误{status.error}'))
                        return status
                    if self.stop.wait(.02):raise Cancelled('控制已关闭')
            raise FocusError('未收到舵机指令确认，请检查新固件、网络及对应编号')
    def configure(self,settings):
        with self.lock:
            state=self.request(Command.QUERY)
            if state.enabled and not state.lease_lost:raise FocusError('舵机仍处于使能保持状态。修改行程前须先关闭PWM，或在失联保持后接管；关闭PWM后不能依赖保持力。')
            self.config=settings.validate(search=False);self.token=secrets.randbits(32) or 1;self.seq=0
            return self.request(Command.CONFIGURE)
    def arm(self):
        status=self.request(Command.ARM);self.armed=status.enabled and not status.lease_lost;return status
    def hold(self):return self.request(Command.HOLD,timeout=.4,retries=1)
    def disable(self):
        status=self.request(Command.DISABLE);self.armed=False;return status
    def move(self,target,cancel=None):
        before=self.request(Command.MOVE,target=int(target),cancel=cancel)
        deadline=time.monotonic()+abs(before.applied-target)/self.config.slew*.02+3
        while time.monotonic()<deadline:
            if cancel is not None and cancel.is_set():raise Cancelled('已取消对焦')
            status=self.request(Command.QUERY,cancel=cancel)
            if status.token!=self.token or not status.enabled or status.lease_lost:raise FocusError('舵机控制已中断，已停止搜索')
            if status.applied==target and not status.moving:return status
            if cancel is not None:cancel.wait(.08)
            else:time.sleep(.08)
        raise FocusError('PWM未在预计时间内到达目标；没有位置传感器，不能据此判断机械到位')
    def _heartbeat(self):
        while not self.stop.wait(.35):
            if not self.armed:continue
            try:
                s=self.request(Command.HEARTBEAT,timeout=.5,retries=2)
                if s.lease_lost or not s.enabled:raise FocusError('运动会话超时，FPGA已保持当前PWM；请手动重新使能')
            except Exception as exc:
                self.armed=False;self.on_error(str(exc))
    def shutdown(self):
        if self.armed:
            try:self.hold()
            except Exception:pass
        self.armed=False;self.stop.set();self.thread.join(timeout=1);self.socket.close()

class FocusSearch:
    def __init__(self,link,frame_provider,settings,notify=lambda value:None):
        self.link=link;self.frames=frame_provider;self.p=settings.validate();self.notify=notify;self.cancel=threading.Event();self.points=[]
    def _check(self):
        if self.cancel.is_set():raise Cancelled('已停止，保持当前PWM')
    def _measure(self,pulse):
        self._check();self.notify({'phase':'moving','pulse':pulse});self.link.move(pulse,self.cancel)
        if self.cancel.wait(self.p.settle):self._check()
        after=time.monotonic();seen=set();scores=[];discard=self.p.discard;deadline=after+max(8,(self.p.samples+self.p.discard)*2.5)
        while time.monotonic()<deadline:
            self._check();sample=self.frames()
            if sample is not None:
                frame,image=sample;key=(frame.source,frame.meta.frame_id,frame.received)
                if frame.received>after and time.monotonic()-frame.received<2.5 and key not in seen:
                    seen.add(key)
                    if discard:discard-=1
                    else:
                        scores.append(focus_score(image,self.p.roi))
                        if len(scores)==self.p.samples:
                            score=float(np.median(scores));self.points.append({'pulse_us':pulse,'score':score,'samples':scores})
                            self.notify({'phase':'sampled','pulse':pulse,'score':score,'points':list(self.points)})
                            return score
            self.cancel.wait(.025)
        raise FocusError('对焦采样期间图像流不足，未使用旧帧计算清晰度')
    def run(self):
        p=self.p
        if not self.link.armed:raise FocusError('请先确认安全行程并配置、使能舵机')
        try:
            positions=list(range(p.lower,p.upper+1,p.coarse))
            if positions[-1]!=p.upper:positions.append(p.upper)
            scores={pos:self._measure(pos) for pos in positions}
            best=max(scores,key=scores.get)
            lo=max(p.lower,best-p.coarse);hi=min(p.upper,best+p.coarse)
            self.link.move(max(p.lower,lo-p.fine),self.cancel)
            # Approach all sampled positions in increasing pulse order. No
            # out-of-range overshoot is used for backlash compensation.
            for pos in range(lo,hi+1,p.fine):
                if pos not in scores:scores[pos]=self._measure(pos)
            best=max(scores,key=scores.get);best_score=scores[best]
            ordered=sorted(scores);index=ordered.index(best)
            if index in (0,len(ordered)-1):raise FocusError('清晰度峰值在搜索边界，请调整镜头或已确认的安全搜索范围')
            contrast=(best_score-min(scores.values()))/max(best_score,1e-9)
            if contrast<.08:raise FocusError('清晰度曲线过平，未确认对焦峰值；请调整ROI、打光或镜头')
            # Return from a lower in-range pulse, then approach the final target
            # in the same direction as the sweep to reduce gear backlash.
            approach=max(p.lower,best-p.fine)
            self.link.move(approach,self.cancel)
            verified=self._measure(best)
            if verified<.8*best_score:raise FocusError('回到峰值后清晰度未复现，建议检查回差或机构稳定性')
            return {'result':'focused','best_pulse_us':best,'score':verified,'peak_score':best_score,'contrast':contrast,'settings':asdict(p),'points':self.points,'position_feedback':False}
        finally:
            try:self.link.hold()
            except Exception:pass
