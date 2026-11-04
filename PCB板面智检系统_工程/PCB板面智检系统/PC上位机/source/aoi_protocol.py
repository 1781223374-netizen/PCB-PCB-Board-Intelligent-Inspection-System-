"""AOI control v1. Network byte order; CRC-16/CCITT-FALSE, init FFFF."""
from dataclasses import dataclass, asdict
import binascii, struct

HELLO, QUERY, CALIBRATE, START, STOP, SET_PARAMS, SET_MODE = range(1,8)
STATES={0:'尚无模板',1:'就绪',2:'准备标定',3:'采集模板',4:'写入模板',5:'正在检测',6:'处理帧',7:'OK',8:'NG',9:'待复核',10:'检测无效'}
ACKS={0:'已执行',1:'未知命令',2:'参数超出范围',3:'忙或被本地操作取消',4:'尚无有效模板',5:'没有可用的新实时图像',6:'未处于 FPGA 检测模式'}

@dataclass(frozen=True)
class Parameters:
    threshold:int=18
    area:int=8
    margin:int=24
    observe_ms:int=20000
    confirm_ms:int=15000
    review_ms:int=3000
    def validate(self):
        if not all(type(v) is int for v in asdict(self).values()):raise ValueError('参数必须为整数')
        if not (8<=self.threshold<=64 and 4<=self.area<=64 and self.area%4==0 and 8<=self.margin<=48 and self.margin%4==0):
            raise ValueError('TH 8–64；面积 4–64 且为 4 的倍数；边缘 8–48 且为 4 的倍数')
        if not (5000<=self.observe_ms<=45000 and 1000<=self.confirm_ms<self.observe_ms and 500<=self.review_ms<=self.confirm_ms):
            raise ValueError('观察 5–45 秒；确认至少 1 秒且小于观察；复核至少 0.5 秒且不大于确认')
        return self
    def payload(self):
        self.validate()
        return struct.pack('!BBBBHHH',self.threshold,self.area,self.margin,0,self.observe_ms,self.confirm_ms,self.review_ms)

def crc(data):return binascii.crc_hqx(data,0xffff)

def command(op,client,seq,cookie=0,params=None,mode=None):
    if op not in range(1,8):raise ValueError('未知命令')
    if not (0<client<2**32 and 0<seq<2**32 and 0<=cookie<2**32):raise ValueError('无效会话或序号')
    payload=params.payload() if op==SET_PARAMS and params is not None else bytes(10)
    if op==SET_PARAMS and params is None:raise ValueError('缺少参数')
    if op==SET_MODE:
        if type(mode) is not bool:raise ValueError('缺少模式')
        payload=bytes([int(mode)])+bytes(9)
    head=struct.pack('!4sBBBBIII',b'ACMD',1,op,0,32,client,seq,cookie)+payload
    return head+struct.pack('!H',crc(head))

def decode_command(data):
    if len(data)!=32 or data[:4]!=b'ACMD' or data[4]!=1 or data[6]!=0 or data[7]!=32 or crc(data[:30])!=int.from_bytes(data[30:],'big'):
        raise ValueError('无效命令帧')
    client,seq,cookie=struct.unpack_from('!III',data,8)
    return dict(op=data[5],client=client,seq=seq,cookie=cookie,payload=data[20:30])

@dataclass(frozen=True)
class Status:
    flags:int;state:int;error:int;client:int;cookie:int;ack_seq:int;ack_code:int;ack_op:int
    parameters:Parameters;run_id:int;template_id:int;elapsed_ms:int;valid_frames:int;candidates:int;confirmed:int
    roi:tuple;source_id:int;judged_source_id:int;candidate_map:int;confirm_map:int;uptime_ms:int;status_seq:int
    paired_run:int;paired_image:int;boot_id:int
    geometry_version:int=0;current_bounds:tuple=(0,0,0,0);geometry_flags:int=0;geometry_rejects:int=0
    position_tolerance:int=3;size_tolerance:int=12;geometry_failure_limit:int=3
    @property
    def geometry_sample_valid(self):return self.geometry_version==1 and bool(self.geometry_flags&128)
    @property
    def template_bounds(self):
        x1,y1,x2,y2=self.roi;m=self.parameters.margin
        return (max(0,x1-m),max(0,y1-m),min(1023,x2+m),min(599,y2+m))
    def geometry_deltas(self):
        a,b,c,d=self.current_bounds;x,y,z,w=self.template_bounds
        return ((a+c-x-z)/2,(b+d-y-w)/2,(c-a)-(z-x),(d-b)-(w-y))
    def geometry_reason(self):
        if not self.geometry_sample_valid:return '等待完整分析帧的板边信息'
        f=self.geometry_flags
        if f&1:return '当前帧未识别到合格板区'
        reasons=[]
        if f&2:reasons.append('中心位置不一致')
        if f&4:reasons.append('板区尺寸不一致')
        if f&8:reasons.append('有效检测区域过小')
        return '、'.join(reasons) if reasons else '板区位置检查通过'

    @property
    def mode(self):return bool(self.flags&1)
    @property
    def template_ready(self):return bool(self.flags&2)
    @property
    def terminal(self):return self.mode and self.state in (7,8,9,10)
    def cells(self,confirmed=False):
        bits=self.confirm_map if confirmed else self.candidate_map
        return [(i%32,i//32) for i in range(608) if bits>>i&1]
    def as_dict(self):return asdict(self)

def decode_status(data):
    if len(data)!=256 or data[:4]!=b'AOST' or data[4]!=1 or crc(data[:254])!=int.from_bytes(data[254:],'big'):
        raise ValueError('无效 FPGA 状态包')
    u16=lambda p:int.from_bytes(data[p:p+2],'big')
    u32=lambda p:int.from_bytes(data[p:p+4],'big')
    if data[6]>10 or data[20]>6:raise ValueError('未知状态或应答码')
    params=Parameters(data[22],data[23],data[24],u16(26),u16(28),u16(30)).validate()
    roi=tuple(u16(p) for p in (48,50,52,54))
    if max(roi)>4095:raise ValueError('检测区域越界')
    return Status(data[5],data[6],data[7],u32(8),u32(12),u32(16),data[20],data[21],params,
      u32(32),u32(36),u16(40),u16(42),u16(44),u16(46),roi,u32(56),u32(60),
      int.from_bytes(data[64:140],'big'),int.from_bytes(data[140:216],'big'),u32(216),u32(220),
      u32(224),u32(228),u32(232),
      geometry_version=data[249],current_bounds=tuple(u16(p) for p in (236,238,240,242)),
      geometry_flags=data[244],geometry_rejects=data[245],position_tolerance=data[246] or 3,
      size_tolerance=data[247] or 12,geometry_failure_limit=data[248] or 3)

def newer(a,b):return 0<((a-b)&0xffffffff)<0x80000000
