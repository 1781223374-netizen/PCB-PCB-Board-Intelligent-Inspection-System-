"""Display-only PCB surface inspection. Input arrays always remain untouched."""
from dataclasses import dataclass,asdict
from pathlib import Path
import json
import cv2
import numpy as np

MODES={'original':'原图','contrast':'彩色对比增强','detail':'PCB 彩色细节','gray':'灰度对比增强','edges':'边缘观察'}

@dataclass
class ViewSettings:
    mode:str='detail'
    level:int=3
    compare:bool=False
    def validate(self):
        if self.mode not in MODES:raise ValueError('未知图像模式')
        if type(self.level) is not int or not 1<=self.level<=7:raise ValueError('强度应为 1–7')
        if type(self.compare) is not bool:raise ValueError('对照开关无效')
        return self
    @classmethod
    def load(cls,path):
        return cls(**json.loads(Path(path).read_text(encoding='utf-8'))).validate() if Path(path).exists() else cls()
    def save(self,path):
        self.validate();path=Path(path);temp=path.with_suffix('.tmp')
        temp.write_text(json.dumps(asdict(self),ensure_ascii=False,indent=2),encoding='utf-8');temp.replace(path)

class Enhancer:
    def __init__(self):
        # Thread policy belongs to the application, not each channel's viewer.
        self.clahe={n:cv2.createCLAHE(clipLimit=1.0+n*.45,tileGridSize=(8,8)) for n in range(1,8)}
        self.stretch={n:np.clip(np.rint((np.arange(256,dtype=np.float32)-112)*(1+n*.10)+112),0,255).astype(np.uint8) for n in range(1,8)}
    def apply(self,rgb,mode='detail',level=3):
        if mode not in MODES or type(level) is not int or not 1<=level<=7:raise ValueError('无效增强参数')
        if rgb.dtype!=np.uint8 or rgb.ndim!=3 or rgb.shape[2]!=3:raise ValueError('需要 uint8 RGB 图像')
        if mode=='original':return rgb.copy()
        ycc=cv2.cvtColor(np.ascontiguousarray(rgb),cv2.COLOR_RGB2YCrCb);y=ycc[:,:,0]
        if mode=='edges':
            dx=cv2.Scharr(y,cv2.CV_16S,1,0);dy=cv2.Scharr(y,cv2.CV_16S,0,1)
            v=(np.abs(dx.astype(np.int32))+np.abs(dy.astype(np.int32)))/16
            v=np.clip(np.maximum(v-3,0)*(1+level*.5),0,255).astype(np.uint8)
            return cv2.cvtColor(v,cv2.COLOR_GRAY2RGB)
        # Uniform fields stay uniform at their original level.
        if float(cv2.meanStdDev(y)[1][0,0])<.5:
            return cv2.cvtColor(y,cv2.COLOR_GRAY2RGB) if mode=='gray' else rgb.copy()
        mapped=self.clahe[level].apply(y)
        blend=.4+level*.075
        enhanced=cv2.addWeighted(y,1-blend,mapped,blend,0)
        # CLAHE alone can leave broad, low-contrast regions almost unchanged.
        # A modest global stretch also separates those surfaces.
        enhanced=cv2.LUT(enhanced,self.stretch[level])
        if mode=='detail':
            fine=enhanced.astype(np.float32)-cv2.GaussianBlur(enhanced,(0,0),1.15).astype(np.float32)
            fine=np.sign(fine)*np.maximum(np.abs(fine)-2,0)
            delta=np.clip(fine*(.2+level*.12),-(8+level*3),8+level*3)
            enhanced=np.clip(np.rint(enhanced+delta),0,255).astype(np.uint8)
        if mode=='gray':return cv2.cvtColor(enhanced,cv2.COLOR_GRAY2RGB)
        ycc[:,:,0]=enhanced
        return cv2.cvtColor(ycc,cv2.COLOR_YCrCb2RGB)
