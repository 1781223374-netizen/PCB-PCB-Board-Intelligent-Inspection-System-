"""Isolated Surface13 computation; no Qt or packet parsing in this process."""
from collections import OrderedDict
import os
import cv2
import numpy as np
import multiprocessing,threading
from multiprocessing import shared_memory
from concurrent.futures import ProcessPoolExecutor
from pcb_aoi_core import TemplateMatcher
from surface_features import SurfaceReference

_models=OrderedDict()
_priority=None

def _configure_worker():
    global _priority
    if _priority is not None:return
    _priority='normal'
    if os.name=='nt':
        import ctypes
        # Apply only to our bounded, serial compute child, never the desktop or
        # other programs. ABOVE_NORMAL avoids starving time-limited observations.
        kernel=ctypes.WinDLL('kernel32',use_last_error=True)
        kernel.GetCurrentProcess.restype=ctypes.c_void_p
        kernel.SetPriorityClass.argtypes=(ctypes.c_void_p,ctypes.c_uint32)
        if kernel.SetPriorityClass(kernel.GetCurrentProcess(),0x8000):_priority='above_normal'

def calculate(path,digest,image=None,parameters=None,use_variation=True):
    _configure_worker()
    threads=min(8, os.cpu_count() or 2)
    if cv2.getNumThreads()!=threads:cv2.setNumThreads(threads)
    key=(path,digest)
    if key not in _models:
        import hashlib
        from pathlib import Path
        if hashlib.sha256(Path(path).read_bytes()).hexdigest()!=digest:
            raise ValueError('模板文件已改变，请重新加载后再开始检测')
        tm=TemplateMatcher.load(path)
        ref=tm.raw_tpl if tm.raw_tpl is not None else cv2.warpPerspective(tm.ref_bgr,tm.S,(tm.tpl.shape[1],tm.canon_h),borderMode=cv2.BORDER_CONSTANT,borderValue=(255,255,255))
        groups=tm.raw_good_groups if use_variation and len(tm.raw_good_groups)>=3 else []
        tm._surface_ref=SurfaceReference(ref,groups);tm._surface_ref_profile=(bool(use_variation),len(tm.raw_good_groups))
        _models[key]=tm
        while len(_models)>6:_models.popitem(last=False)
    _models.move_to_end(key)
    if image is None:return {'pid':os.getpid(),'prepared':True,'threads':cv2.getNumThreads(),'logical_processors':os.cpu_count(),'priority':_priority}
    return _models[key].detect(image,**parameters)

def calculate_shared(input_name,output_name,path,digest,shape,parameters,use_variation):
    incoming=shared_memory.SharedMemory(name=input_name);outgoing=shared_memory.SharedMemory(name=output_name)
    image=np.ndarray(shape,dtype=np.uint8,buffer=incoming.buf)
    try:
        result=calculate(path,digest,image,parameters,use_variation)
        coverage_shape=None
        if result.coverage_mask is not None:
            coverage_shape=result.coverage_mask.shape
            outgoing.buf[:result.coverage_mask.nbytes]=result.coverage_mask.tobytes()
            result.coverage_mask=None
        return result,coverage_shape
    finally:
        del image;incoming.close();outgoing.close()

class DetectorExecutor:
    """Only small control/results traverse pipes; native images use shared RAM."""
    def __init__(self):
        self.pool=ProcessPoolExecutor(max_workers=1,mp_context=multiprocessing.get_context('spawn'))
        self.incoming=shared_memory.SharedMemory(create=True,size=1920*1080*3)
        self.outgoing=shared_memory.SharedMemory(create=True,size=1920*1080)
        self.lock=threading.Lock();self.closing=False
    def submit(self,*args,**kw):return self.pool.submit(*args,**kw)
    def detect(self,path,digest,image,parameters,use_variation):
        with self.lock:
            if self.closing:raise RuntimeError('检测进程正在关闭')
            if image.dtype!=np.uint8 or image.nbytes>self.incoming.size:raise ValueError('多通道检测支持最高1920x1080 uint8图像')
            self.incoming.buf[:image.nbytes]=image.tobytes()
            result,shape=self.pool.submit(calculate_shared,self.incoming.name,self.outgoing.name,path,digest,image.shape,parameters,use_variation).result()
            if shape is not None:result.coverage_mask=np.ndarray(shape,dtype=np.uint8,buffer=self.outgoing.buf).copy()
            return result
    def shutdown(self,wait=False,cancel_futures=True):
        self.closing=True;self.pool.shutdown(wait=wait,cancel_futures=cancel_futures)
        def release():
            with self.lock:
                self.incoming.close();self.incoming.unlink();self.outgoing.close();self.outgoing.unlink()
        threading.Thread(target=release,daemon=False,name='close-detector-memory').start()
