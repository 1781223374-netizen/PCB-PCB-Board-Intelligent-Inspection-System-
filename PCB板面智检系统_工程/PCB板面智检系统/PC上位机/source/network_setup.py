"""Bounded Windows demo-network setup, journaled rollback, and read-only discovery.

No setup runs at application startup. Only the explicit UI action launches the
elevated helper. Network commands use fixed operations and JSON data, never a
user-built shell command. The camera's fixed addresses are not editable here.
"""
from __future__ import annotations
from contextlib import contextmanager
from dataclasses import asdict,dataclass
import base64,ctypes,hashlib,json,os,re,subprocess,sys,time,uuid
from pathlib import Path

PC_IP='192.168.137.1';BOARD_IP='192.168.137.2';PORT=16001
BOARD_IPS=('192.168.137.2','192.168.137.3','192.168.137.4');PORTS=(16001,16002,16003)
RULE_PREFIX='PCBAOI.MultiCam.Demo.'
GUID_RE=re.compile(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')

def guid(value):
    value=str(value).strip('{}').lower()
    if not GUID_RE.fullmatch(value):raise ValueError('网卡标识无效，请重新扫描网卡。')
    return value

def save_json(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    temp=path.with_suffix('.tmp');temp.write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8');temp.replace(path)

def load_json(path,default=None):
    path=Path(path)
    if not path.exists():return default
    if path.stat().st_size>1024*1024:raise ValueError('网络配置文件过大，未执行操作。')
    return json.loads(path.read_text(encoding='utf-8-sig'))

@dataclass
class NetworkProfile:
    ssid:str='TP-LINK_AF9E'
    adapter_guid:str=''

    def validate(self):
        if not isinstance(self.ssid,str) or not self.ssid or len(self.ssid.encode('utf-8'))>32 or any(ord(c)<32 for c in self.ssid):
            raise ValueError('请填写演示 Wi-Fi 名称（最多 32 字节）。')
        if self.adapter_guid:self.adapter_guid=guid(self.adapter_guid)
        return self

    @classmethod
    def load(cls,path):
        v=load_json(path,{})
        return cls(v.get('ssid','TP-LINK_AF9E'),v.get('adapter_guid','')).validate()

def parse_wlan(text):
    """SSID and GUID are invariant field names; never inspect saved passwords."""
    result={};current=None
    for line in text.splitlines():
        m=re.match(r'^\s*GUID\s*:\s*\{?([0-9a-fA-F-]{36})\}?\s*$',line)
        if m:current=guid(m[1])
        m=re.match(r'^\s*SSID\s*:\s*(.*?)\s*$',line)
        if m and current:result[current]=m[1]
    return result

def normalize_snapshot(value):
    value=dict(value);value['adapters']=list(value.get('adapters') or [])
    ssids=parse_wlan(value.pop('wlan_text',''))
    for a in value['adapters']:
        a['guid']=guid(a['guid']);a['ssid']=ssids.get(a['guid'],'')
        for k in ['addresses','gateways','dns']:a[k]=list(a.get(k) or [])
    value['all_addresses']=list(value.get('all_addresses') or [])
    value['ports']=list(value.get('ports') or [])
    return value

def make_plan(snapshot,profile,parent_pid):
    profile.validate()
    candidates=[a for a in snapshot['adapters'] if a['up'] and (not profile.adapter_guid or a['guid']==profile.adapter_guid)]
    if not profile.adapter_guid:candidates=[a for a in candidates if a['wireless'] and a['ssid']==profile.ssid]
    if len(candidates)!=1:raise ValueError('未找到唯一的演示网卡。请先连接目标路由器，再在设置中选择网卡。')
    a=candidates[0]
    if PC_IP in a['gateways']:raise ValueError('路由器网关占用了相机接收地址 192.168.137.1，未修改配置。请调整演示路由器 LAN 地址。')
    if any(x['ip'] in BOARD_IPS for x in snapshot['all_addresses']):raise ValueError('本机占用了开发板地址 192.168.137.2–4，未修改配置。请先处理地址冲突。')
    if a['wireless'] and a['ssid']!=profile.ssid:
        current=a['ssid'] or '无法读取（请检查 Windows 的 Wi-Fi/位置权限）'
        raise ValueError(f"目标 Wi-Fi：{profile.ssid}；当前：{current}。请先在 Windows 连接目标路由器。尚未更改网络。")
    for entry in snapshot['all_addresses']:
        if entry['ip']==PC_IP and entry['index']!=a['index']:
            raise ValueError(f'{PC_IP} 已在另一张网卡上，未修改配置。请先处理地址冲突。')
    for owner in snapshot['ports']:
        if int(owner)!=parent_pid:raise ValueError(f'UDP {PORT} 已被另一个程序占用，请先关闭旧接收端。')
    existing=[x for x in a['addresses'] if x['ip']==PC_IP]
    if existing and any(x['prefix']!=24 or x['state'] not in ['Preferred','Deprecated'] for x in existing):
        raise ValueError('接收地址的掩码或地址状态异常，未替换现有地址。请检查网络诊断。')
    if not existing and a['dhcp'] and a.get('coexistence') is None:
        raise ValueError('无法确认 DHCP 与静态地址共存状态，未更改配置。当前支持中文/英文 Windows 10/11。')
    return dict(adapter=a,add_ip=not existing,enable_coexistence=bool(not existing and a['dhcp'] and not a['coexistence']))

class WindowsBackend:
    def call(self,operation,**params):
        if os.name!='nt':raise RuntimeError('一键网络配置仅支持 Windows。')
        if operation not in ['inventory','coexistence','add_ip','remove_ip','rule_get','rule_add','rule_remove','dhcp_restore','health']:
            raise ValueError('不支持的网络操作。')
        data=base64.b64encode(json.dumps(dict(operation=operation,**params),ensure_ascii=False).encode()).decode()
        script=(Path(__file__).parent/'assets/network_helper.ps1').read_text(encoding='utf-8-sig')
        script="$payload64='"+data+"'\n"+script
        encoded=base64.b64encode(script.encode('utf-16le')).decode()
        command=[str(Path(os.environ.get('SystemRoot','C:/Windows'))/'System32/WindowsPowerShell/v1.0/powershell.exe'),'-NoProfile','-NonInteractive','-EncodedCommand',encoded]
        proc=subprocess.run(command,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
            timeout=35,creationflags=subprocess.CREATE_NO_WINDOW)
        try:result=json.loads(proc.stdout.decode('utf-8-sig'))
        except Exception:raise RuntimeError('Windows 网络接口未返回有效结果：'+proc.stderr.decode('utf-8',errors='replace')[-700:])
        if proc.returncode or not result.get('ok'):raise RuntimeError(result.get('error','Windows 网络操作失败'))
        return result.get('value')

    def snapshot(self):return normalize_snapshot(self.call('inventory'))
    def rule_matches(self,name,adapter,program):
        if not re.fullmatch(re.escape(RULE_PREFIX)+r'[0-9a-f]{32}',name):raise ValueError('无效的规则标识。')
        return bool(self.call('rule_get',name=name,index=adapter['index'],guid=adapter['guid'],program=program))
    def change(self,operation,adapter,**params):
        return self.call(operation,index=adapter['index'],guid=adapter['guid'],**params)

@contextmanager
def operation_lock(folder):
    import msvcrt
    folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
    with (folder/'operation.lock').open('a+b') as f:
        if f.tell()==0:f.write(b'0');f.flush()
        f.seek(0)
        try:msvcrt.locking(f.fileno(),msvcrt.LK_NBLCK,1)
        except OSError:raise RuntimeError('另一个网络配置操作尚未完成，请稍后重试。')
        try:yield
        finally:f.seek(0);msvcrt.locking(f.fileno(),msvcrt.LK_UNLCK,1)

class NetworkEngine:
    """The same transaction engine is exercised with a deterministic fake backend."""
    def __init__(self,backend,state_path,program):
        self.backend=backend;self.path=Path(state_path);self.program=str(Path(program).resolve())

    def _save(self,state):save_json(self.path,state)

    def health(self,index):
        try:return self.backend.call('health',index=index)
        except Exception as exc:return dict(route_ok=None,ping=False,note='连接诊断未完成：'+str(exc))

    def ready(self,plan,state):
        if not state or state.get('status')!='active' or state.get('guid')!=plan['adapter']['guid'] or plan['add_ip']:return False
        return self.backend.rule_matches(state['rule_name'],plan['adapter'],self.program)

    def configure(self,profile,parent_pid):
        before=self.backend.snapshot();plan=make_plan(before,profile,parent_pid);a=plan['adapter']
        state=load_json(self.path)
        if state and state.get('status')!='restored' and state.get('guid')!=a['guid']:
            raise ValueError('还有另一张网卡的演示配置，请先使用“恢复本次配置”。')
        if state and state.get('status') not in ['active','restored']:
            raise ValueError('上次配置未完整结束，请先使用“恢复本次配置”。')
        if self.ready(plan,state):return dict(configured=True,reused=True,adapter=a,health=self.health(a['index']))
        if not state or state.get('status')=='restored':
            state=dict(schema=1,guid=a['guid'],original=a,status='applying',added_ip=False,coexistence_changed=False,
                rule_created=False,rule_name=RULE_PREFIX+uuid.uuid4().hex,started=time.time())
        state['status']='applying';state['program']=self.program;state['ssid']=profile.ssid;self._save(state)
        try:
            if plan['enable_coexistence']:
                state['coexistence_changed']=True;self._save(state)
                self.backend.change('coexistence',a,enabled=True)
            if plan['add_ip']:
                already_owned=state['added_ip']
                state['added_ip']=True;self._save(state)
                added=self.backend.change('add_ip',a)
                if isinstance(added,dict) and added.get('added') is False:
                    state['added_ip']=already_owned;self._save(state)
            if not self.backend.rule_matches(state['rule_name'],a,self.program):
                state['rule_created']=True;self._save(state)
                self.backend.change('rule_add',a,name=state['rule_name'],program=self.program)
            after=None
            for _ in range(12):
                after=self.backend.snapshot();current=next(x for x in after['adapters'] if x['guid']==a['guid'])
                found=[x for x in current['addresses'] if x['ip']==PC_IP]
                if any(x['state']=='Duplicate' for x in found):raise RuntimeError('接收地址发生冲突，正在撤回本次配置。')
                if found and all(x['state']=='Preferred' and x['prefix']==24 for x in found):break
                time.sleep(.4)
            else:raise RuntimeError('接收地址未就绪，正在撤回本次配置。')
            make_plan(after,profile,parent_pid)
            if current['dhcp']!=a['dhcp'] or current['gateways']!=a['gateways'] or current['dns']!=a['dns']:
                raise RuntimeError('检测到原上网配置变化，正在撤回本次配置。')
            if not self.backend.rule_matches(state['rule_name'],current,self.program):raise RuntimeError('接收防火墙规则未生效。')
            state['status']='active';state['completed']=time.time();self._save(state)
            return dict(configured=True,reused=False,adapter=current,health=self.health(a['index']))
        except Exception as exc:
            cleanup=self.restore(rollback=True)
            raise RuntimeError(str(exc)+(' 已撤回本次修改。' if cleanup['restored'] else ' 自动撤回未完成，请使用“恢复本次配置”：'+'；'.join(cleanup['errors']))) from exc

    def restore(self,rollback=False):
        state=load_json(self.path)
        if not state or state.get('status')=='restored':return dict(restored=True,errors=[],notes=['没有需要恢复的本程序配置。'])
        if state.get('schema')!=1 or not re.fullmatch(re.escape(RULE_PREFIX)+r'[0-9a-f]{32}',state.get('rule_name','')):raise ValueError('恢复记录无效，未更改系统。')
        snap=self.backend.snapshot();a=next((x for x in snap['adapters'] if x['guid']==guid(state['guid'])),None)
        if not a:raise RuntimeError('原网卡当前不可用，请接回该网卡后恢复。')
        errors=[];notes=[]
        for flag,operation,params in [('rule_created','rule_remove',dict(name=state['rule_name'])),('added_ip','remove_ip',{})]:
            if state.get(flag):
                try:self.backend.change(operation,a,**params);state[flag]=False;self._save(state)
                except Exception as exc:errors.append(str(exc))
        # Do not disable coexistence while a new, unrelated static alias needs it.
        if state.get('coexistence_changed') and not state.get('added_ip'):
            current=next(x for x in self.backend.snapshot()['adapters'] if x['guid']==a['guid'])
            original={(x['ip'],x['prefix']) for x in state['original']['addresses']}
            other=[x for x in current['addresses'] if x.get('origin')=='Manual' and (x['ip'],x['prefix']) not in original]
            if other:notes.append('发现后来添加的静态地址，已保留 DHCP 共存开关。');state['coexistence_changed']=False
            else:
                try:self.backend.change('coexistence',a,enabled=bool(state['original']['coexistence']));state['coexistence_changed']=False;self._save(state)
                except Exception as exc:errors.append(str(exc))
        if rollback and state['original']['dhcp']:
            current=next(x for x in self.backend.snapshot()['adapters'] if x['guid']==a['guid'])
            if not current['dhcp']:
                try:self.backend.change('dhcp_restore',a)
                except Exception as exc:errors.append(str(exc))
        state['status']='restore_failed' if errors else 'restored';state['restore_errors']=errors;self._save(state)
        current=next(x for x in self.backend.snapshot()['adapters'] if x['guid']==a['guid'])
        return dict(restored=not errors,errors=errors,notes=notes,adapter=current)

def launch_elevated(request_path,hwnd=0):
    """Start this executable as a helper; Windows owns the consent prompt."""
    from ctypes import wintypes
    class INFO(ctypes.Structure):
        _fields_=[('cbSize',wintypes.DWORD),('fMask',wintypes.ULONG),('hwnd',wintypes.HWND),('lpVerb',wintypes.LPCWSTR),
          ('lpFile',wintypes.LPCWSTR),('lpParameters',wintypes.LPCWSTR),('lpDirectory',wintypes.LPCWSTR),('nShow',ctypes.c_int),
          ('hInstApp',wintypes.HINSTANCE),('lpIDList',ctypes.c_void_p),('lpClass',wintypes.LPCWSTR),('hkeyClass',wintypes.HKEY),
          ('dwHotKey',wintypes.DWORD),('hIcon',wintypes.HANDLE),('hProcess',wintypes.HANDLE)]
    args=['--network-helper',str(request_path.resolve())]
    if not getattr(sys,'frozen',False):args.insert(0,str(Path(__file__).parent/'multi_aoi_studio.py'))
    params=subprocess.list2cmdline(args)
    info=INFO();info.cbSize=ctypes.sizeof(INFO);info.fMask=0x40|0x400;info.hwnd=hwnd;info.lpVerb='runas'
    info.lpFile=sys.executable;info.lpParameters=params;info.nShow=0
    shell=ctypes.WinDLL('shell32',use_last_error=True);shell.ShellExecuteExW.argtypes=[ctypes.POINTER(INFO)];shell.ShellExecuteExW.restype=wintypes.BOOL
    if not shell.ShellExecuteExW(ctypes.byref(info)):
        code=ctypes.get_last_error()
        raise RuntimeError('已取消管理员授权，未执行网络配置。' if code==1223 else f'无法启动网络配置助手（Windows {code}）。')
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.WaitForSingleObject.argtypes=[wintypes.HANDLE,wintypes.DWORD];kernel.WaitForSingleObject.restype=wintypes.DWORD
    kernel.CloseHandle.argtypes=[wintypes.HANDLE]
    try:
        while kernel.WaitForSingleObject(info.hProcess,500)==258:pass
    finally:kernel.CloseHandle(info.hProcess)
    result=load_json(request_path.parent/'result.json')
    if not result:raise RuntimeError('网络助手未完成。可检查诊断并使用“恢复本次配置”。')
    if not result.get('ok'):raise RuntimeError(result.get('error','网络配置失败。'))
    return result['value']

class NetworkService:
    def __init__(self,folder,backend=None,launcher=None):
        self.folder=Path(folder);self.backend=backend or WindowsBackend();self.launcher=launcher or launch_elevated
        self.profile_path=self.folder/'profile.json';self.state_path=self.folder/'state.json'
    def inventory(self):return self.backend.snapshot()
    def apply(self,profile,hwnd=0):
        snap=self.inventory();plan=make_plan(snap,profile,os.getpid())
        engine=NetworkEngine(self.backend,self.state_path,sys.executable)
        if engine.ready(plan,load_json(self.state_path)):
            return dict(configured=True,reused=True,adapter=plan['adapter'],health=engine.health(plan['adapter']['index']))
        return self._request('apply',profile,hwnd)
    def restore(self,hwnd=0):
        state=load_json(self.state_path)
        if not state or state.get('status')=='restored':return dict(restored=True,errors=[],notes=['没有需要恢复的本程序配置。'])
        return self._request('restore',NetworkProfile(),hwnd)
    def _request(self,action,profile,hwnd):
        job=self.folder/'requests'/uuid.uuid4().hex;job.mkdir(parents=True)
        request=job/'request.json';save_json(request,dict(action=action,profile=asdict(profile.validate()),parent_pid=os.getpid()))
        return self.launcher(request,hwnd)

def elevated_entry(path):
    path=Path(path).resolve()
    if path.name!='request.json' or not re.fullmatch(r'[0-9a-f]{32}',path.parent.name) or path.parent.parent.name!='requests':return 2
    result_path=path.parent/'result.json'
    try:
        if os.name!='nt' or not ctypes.windll.shell32.IsUserAnAdmin():raise RuntimeError('Windows 未授予网络配置所需的管理员权限。')
        request=load_json(path);action=request['action'];assert action in ['apply','restore']
        folder=path.parent.parent.parent;backend=WindowsBackend();engine=NetworkEngine(backend,folder/'state.json',sys.executable)
        profile=NetworkProfile(**request['profile']).validate();pid=request['parent_pid']
        if type(pid)is not int or pid<=0:raise ValueError('无效的父进程标识。')
        with operation_lock(folder):value=engine.configure(profile,pid) if action=='apply' else engine.restore()
        save_json(result_path,dict(ok=True,value=value));return 0
    except Exception as exc:save_json(result_path,dict(ok=False,error=str(exc)));return 1
