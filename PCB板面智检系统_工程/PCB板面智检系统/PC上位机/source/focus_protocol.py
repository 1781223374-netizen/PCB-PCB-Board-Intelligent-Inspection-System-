"""SVCT/SVST v1, positional servo commands over the existing image UDP port."""
from dataclasses import dataclass,asdict
from enum import IntEnum
import struct,binascii

class Command(IntEnum):
    QUERY=0;CONFIGURE=1;ARM=2;MOVE=3;HOLD=4;DISABLE=5;HEARTBEAT=6

BODY=struct.Struct('!4sBBBBIIHHHHHHH')
assert BODY.size==30
LEASE_MS=2000

def crc(data):return binascii.crc_hqx(data,0xffff)

def command_bytes(board,command,token,seq,lower=500,upper=2500,target=1500,slew=5):
    if board not in (1,2,3):raise ValueError('设备编号必须为1/2/3')
    command=Command(command)
    if not (0<=token<=0xffffffff and 1<=seq<=0xffffffff):raise ValueError('会话或序号无效')
    if not (500<=lower<upper<=2500 and lower<=target<=upper and 1<=slew<=20):raise ValueError('脉宽范围为500–2500µs，目标须在设定行程内，斜率为1–20µs/周期')
    body=BODY.pack(b'SVCT',1,command,board,0,token,seq,lower,upper,target,slew,LEASE_MS,0,0x5aa5)
    return body+struct.pack('!H',crc(body))

@dataclass(frozen=True)
class ServoStatus:
    board:int;flags:int;error:int;token:int;seq:int
    applied:int;target:int;lower:int;upper:int;slew:int;lease_ms:int
    received:float=0.
    @property
    def enabled(self):return bool(self.flags&1)
    @property
    def configured(self):return bool(self.flags&2)
    @property
    def moving(self):return bool(self.flags&4)
    @property
    def lease_lost(self):return bool(self.flags&8)

def decode_status(data,board=None,received=0.):
    if len(data)!=32 or struct.unpack('!H',data[30:])[0]!=crc(data[:30]):raise ValueError('舵机状态长度或CRC无效')
    magic,version,identity,flags,error,token,seq,applied,target,lower,upper,slew,lease,guard=BODY.unpack(data[:30])
    if magic!=b'SVST' or version!=1 or identity not in (1,2,3) or (board is not None and identity!=board) or flags&0xf0 or guard!=0xa55a:raise ValueError('舵机状态协议或设备编号无效')
    if not (500<=lower<upper<=2500 and lower<=applied<=upper and lower<=target<=upper and 1<=slew<=20 and lease==LEASE_MS):raise ValueError('舵机返回参数超出范围')
    return ServoStatus(identity,flags,error,token,seq,applied,target,lower,upper,slew,lease,received)

ERRORS={2:'目标或行程参数越界',3:'舵机会话失效，请重新配置',4:'收到过期指令',5:'当前状态不允许；停止运动或等待会话超时后重试',6:'固件不支持此指令'}
