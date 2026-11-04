"""Experimental green-PCB surface features. No inspection frame is learned.

Colour-only green shade and yellow/grey-metal differences are allowed. Bright
line novelty and material membership changes form separate evidence channels.
The reference's automatically located mounting-hole interiors are uninspected.
"""
import cv2
import numpy as np

def erode_mask(mask,radius):
 return cv2.erode(mask,np.ones((2*radius+1,2*radius+1),np.uint8),borderType=cv2.BORDER_CONSTANT,borderValue=0)

def boardmask(im):
 hsv=cv2.cvtColor(im,cv2.COLOR_BGR2HSV)
 a=((hsv[:,:,1]>25)&(hsv[:,:,2]>25)).astype(np.uint8)*255
 a=cv2.morphologyEx(a,cv2.MORPH_CLOSE,np.ones((11,11),np.uint8))
 cs,_=cv2.findContours(a,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
 out=np.zeros(a.shape,np.uint8)
 if cs:cv2.drawContours(out,[max(cs,key=cv2.contourArea)],-1,255,-1)
 return out

def green(im):
 a=cv2.cvtColor(im,cv2.COLOR_BGR2HSV)
 return ((a[:,:,0]>=35)&(a[:,:,0]<=100)&(a[:,:,1]>=25)&(a[:,:,2]>15)).astype(np.uint8)*255

def holemask(ref):
 gray=cv2.cvtColor(ref,cv2.COLOR_BGR2GRAY);h,w=gray.shape
 out=np.zeros((h,w),np.uint8);found=[]
 for xx,yy in [(0,0),(int(w*.8),0),(0,int(h*.8)),(int(w*.8),int(h*.8))]:
  roi=gray[yy:min(h,yy+int(h*.2)+1),xx:min(w,xx+int(w*.2)+1)]
  circles=cv2.HoughCircles(cv2.GaussianBlur(roi,(0,0),1),cv2.HOUGH_GRADIENT,1,30,param1=80,param2=20,minRadius=18,maxRadius=40)
  if circles is None:continue
  corner=np.array([0 if xx==0 else w,0 if yy==0 else h])
  candidates=[(float(cx+xx),float(cy+yy),float(r)) for cx,cy,r in circles[0]]
  cx,cy,rad=min(candidates,key=lambda c:np.sum((np.array(c[:2])-corner)**2))
  cv2.circle(out,(round(cx),round(cy)),round(rad*.85),255,-1);found.append([cx,cy,rad])
 return out,found

def ridge(im):
 g=cv2.cvtColor(im,cv2.COLOR_BGR2GRAY).astype(np.float32)
 ans=np.zeros_like(g)
 for sig in (.8,1.2,1.8):
  sm=cv2.GaussianBlur(g,(0,0),sig)
  xx=cv2.Sobel(sm,cv2.CV_32F,2,0,ksize=3,scale=.25)*sig*sig
  yy=cv2.Sobel(sm,cv2.CV_32F,0,2,ksize=3,scale=.25)*sig*sig
  xy=cv2.Sobel(sm,cv2.CV_32F,1,1,ksize=3,scale=.25)*sig*sig
  disc=np.sqrt(np.maximum((xx-yy)**2+4*xy**2,0));lo=(xx+yy-disc)*.5;hi=(xx+yy+disc)*.5
  v=np.maximum(-lo,0)*np.exp(-.5*(hi/(np.abs(lo)+.2)/.5)**2)
  ans=np.maximum(ans,v)
 return ans

def cc(mask):
 n,lab,st,_=cv2.connectedComponentsWithStats(mask.astype(np.uint8),8)
 return lab,st

def measure(mask):
 yy,xx=np.where(mask);z=np.stack((xx,yy),axis=1).astype(np.float32)
 if len(z)<3:return 0,0,0
 ev,vec=np.linalg.eigh(np.cov(z.T));ratio=float(np.sqrt((ev[1]+.1)/(ev[0]+.1)))
 proj=z@vec[:,1];length=float(proj.max()-proj.min()+1)
 return length,ratio,len(z)/max(length,1)

def inspect(model,cur,core,cut=2.5,minlen=18,ratio=2.4,structure_gain=1.6,edge_tolerance=2,mask_holes=True,min_area=120,small_response=12.0):
 ref=model.rgb
 core=core & (erode_mask(boardmask(cur),8)>0) & model.surface
 if mask_holes:core &= model.holes==0
 rg,cg=model.green,green(cur)
 # Restrict the fine-line branch to interiors of material regions, rather than
 # reacting to a stable pad's entire outline when its colour changes.
 interior=model.interior
 sc=ridge(cur);expected=model.expected
 excess=np.maximum(sc-structure_gain*expected,0)
 structure=model.edges
 near=cv2.dilate(structure,np.ones((2*edge_tolerance+1,2*edge_tolerance+1),np.uint8))>0
 mask=(excess>cut)&core&interior&~near
 source=mask.astype(np.uint8)
 joined=source.copy()
 for angle in range(0,180,15):
  kernel=np.zeros((11,11),np.uint8);dx=round(5*np.cos(np.deg2rad(angle)));dy=round(5*np.sin(np.deg2rad(angle)))
  cv2.line(kernel,(5-dx,5-dy),(5+dx,5+dy),1,1)
  joined|=cv2.morphologyEx(source,cv2.MORPH_CLOSE,kernel)
 mask=(joined>0)&core
 lab,st=cc(mask);lines=[]
 for i in range(1,len(st)):
  x,y,ww,hh,area=st[i]
  if area<12:continue
  m=lab==i;length,elong,width=measure(m)
  if length>=minlen and elong>=ratio and width<=8 and source[m].sum()/max(area,1)>=.4:
   lines.append(dict(box=[int(x),int(y),int(x+ww),int(y+hh)],area=int(area),length=round(length,2),elong=round(elong,2),width=round(width,2),peak=float(excess[m].max())))
 # Material membership is deliberately insensitive to yellow-vs-grey metal
 # or light-vs-dark green, but responds to new material boundaries.
 new=((erode_mask(model.green_only,3)>0)&(cg==0))|((erode_mask(model.other_only,3)>0)&(cg>0))
 new &=core
 new=cv2.morphologyEx(new.astype(np.uint8),cv2.MORPH_OPEN,np.ones((3,3),np.uint8))
 new=cv2.morphologyEx(new,cv2.MORPH_CLOSE,np.ones((3,3),np.uint8));new[~core]=0
 la,sta=cc(new);patches=[]
 for i in range(1,len(sta)):
  x,y,ww,hh,area=sta[i]
  if area>=min_area:patches.append(dict(box=[int(x),int(y),int(x+ww),int(y+hh)],area=int(area)))
 # Compact novel bright structure also matters on an existing copper pad,
 # where material membership alone cannot separate a same-colour foreign chip.
 cg0=cv2.GaussianBlur(cv2.cvtColor(cur,cv2.COLOR_BGR2GRAY).astype(np.float32),(0,0),.8)
 detail=cg0-cv2.GaussianBlur(cg0,(0,0),3)
 compact=np.maximum(detail-structure_gain*model.detail_expected,0)
 stable=core&(model.green>0)&(cg>0)
 offset=float(np.median(model.gray[stable]-cg0[stable])) if stable.any() else 0.0
 offset=float(np.clip(offset,-80,80))
 novel=(cg0+offset)>model.bright_expected+15.0
 seed=((compact>small_response)&novel&core).astype(np.uint8)
 lb,stats=cc(seed)
 for i in range(1,len(stats)):
  x,y,ww,hh,area=stats[i]
  if area>=20:
   patches.append(dict(box=[int(x),int(y),int(x+ww),int(y+hh)],area=int(area),peak=float(compact[lb==i].max()),kind='structure'))
 return lines,patches,excess,core

class SurfaceReference:
 def __init__(self,rgb,normals=()):
  if rgb.dtype!=np.uint8 or rgb.ndim!=3 or rgb.shape[2]!=3:raise ValueError('需要uint8 BGR参考图')
  self.rgb=np.ascontiguousarray(rgb).copy()
  self.surface=erode_mask(boardmask(self.rgb),8)>0
  self.green=green(self.rgb)
  self.interior=(erode_mask(self.green,2)>0)|(erode_mask(255-self.green,2)>0)
  self.green_only=self.green.copy();self.other_only=255-self.green
  self.holes,self.hole_circles=holemask(self.rgb)
  self.expected=cv2.dilate(ridge(self.rgb),np.ones((5,5),np.uint8))
  g=cv2.GaussianBlur(cv2.cvtColor(self.rgb,cv2.COLOR_BGR2GRAY).astype(np.float32),(0,0),.8)
  dx=cv2.Sobel(g,cv2.CV_32F,1,0,ksize=3,scale=.125);dy=cv2.Sobel(g,cv2.CV_32F,0,1,ksize=3,scale=.125)
  self.edges=(np.hypot(dx,dy)>8).astype(np.uint8)
  self.gray=g
  self.bright_expected=cv2.dilate(g,np.ones((5,5),np.uint8))
  self.detail_expected=cv2.dilate(g-cv2.GaussianBlur(g,(0,0),3),np.ones((5,5),np.uint8))

  # Additional groups are explicit confirmed-good captures, never current tests.
  self.normal_groups=len(normals) if len(normals)>=3 else 0
  if self.normal_groups:
   for image in normals[1:]:
    # Do not raise weak-line noise thresholds from additional good captures.
    # Extra groups expand normal material/strong-edge context only.
    gm=green(image);self.green_only=cv2.bitwise_and(self.green_only,gm);self.other_only=cv2.bitwise_and(self.other_only,255-gm)
    q=cv2.GaussianBlur(cv2.cvtColor(image,cv2.COLOR_BGR2GRAY).astype(np.float32),(0,0),.8)
    x=cv2.Sobel(q,cv2.CV_32F,1,0,ksize=3,scale=.125);y=cv2.Sobel(q,cv2.CV_32F,0,1,ksize=3,scale=.125)
    self.edges|=(np.hypot(x,y)>8).astype(np.uint8)
    self.bright_expected=np.maximum(self.bright_expected,cv2.dilate(q,np.ones((5,5),np.uint8)))
    self.detail_expected=np.maximum(self.detail_expected,cv2.dilate(q-cv2.GaussianBlur(q,(0,0),3),np.ones((5,5),np.uint8)))
