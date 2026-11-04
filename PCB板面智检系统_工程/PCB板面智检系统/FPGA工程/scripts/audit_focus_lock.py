import os
"""Prove the final routed ownership signal has a registered pixel source."""
from pathlib import Path
import json,hashlib,re,subprocess
F=Path(__file__).resolve().parents[1]
O=F/'review/final1080';T='smart_camera_v26_7_fast_ui'
db=O/(T+'_final.db');assert db.is_file()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def call(name,body):
 script=O/(name+'.tcl');log=O/(name+'.log');script.write_text(body,encoding='utf-8')
 with log.open('w',encoding='utf-8') as output:
  td=Path(os.environ.get('ANLOGIC_HOME','D:/TD_6_2/Anlogic'))/'bin/td_commands_prompt.exe'
  p=subprocess.run([str(td),script.as_posix()],cwd=O,stdout=output,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL)
 text=log.read_text(encoding='utf-8',errors='replace')
 assert p.returncode==0 and not re.search(r'\bERROR\s*:|EMPTY_REQUIRED|No (?:nets|pins|clocks) matched',text),text[-3000:]
 return text
header=f'import_device ph1_50p.db -package PH1P50SBG484 -speed 3\nimport_db {{{db.as_posix()}}}\n'
names=['u_network/focus_lock','u_network/focus_lock_sync[0]','u_network/focus_lock_sync[1]']
body=''
for i,name in enumerate(names):
 body+='puts "FOCUS_NET_'+str(i)+'"\n'
 body+='set n [get_nets {'+name+'}]\nif {[llength $n]!=1} {error EMPTY_REQUIRED_FOCUS_NET}\nreport_nets $n -connection\n'
text=call('focus_lock_connection',header+body+'exit\n')
pins=lambda section:re.findall(r':\s*\d+\s*\|\s*(\S+)\s*\|',section)
drivers=[];loads=[]
for i in range(3):
 block=text.split('FOCUS_NET_'+str(i)+'\n',1)[-1]
 # TD echoes puts; use the last marker before the report when necessary.
 block=block.split('Net:',1)[1].split('FOCUS_NET_'+str(i+1),1)[0]
 drivers.append(pins(block.split('Driver pin(s):',1)[1].split('Load pin(s):',1)[0]))
 loads.append(pins(block.split('Load pin(s):',1)[1]))
assert all(len(d)==1 for d in drivers),drivers
assert all(re.search(r'\.oq[a-z]?$',d[0]) for d in drivers),drivers
cells=[d[0].rsplit('.',1)[0] for d in drivers]
# A physical slice may contain two different FF slots (oq/oqb); they need not
# occupy different slices, but must remain three distinct registered outputs.
assert len(set(d[0] for d in drivers))==3,drivers
assert any(p.rsplit('.',1)[0]==cells[1] for p in loads[0]),(cells,loads)
second_inputs=[p for p in loads[1] if p.rsplit('.',1)[0]==cells[2]]
assert second_inputs,(cells,loads)
sdc=F/'project/smart_camera_ddr.sdc'
timing=header+'start_timer\nclear_sdc -user\nread_sdc {'+sdc.as_posix()+'}\nupdate_timing -mode final\n'
timing+='report_cells [get_cells {'+' '.join(cells)+'}] -connection\n'
timing+='report_timing_path -from [get_pins {'+drivers[1][0]+'}] -to [get_pins {'+' '.join(second_inputs)+'}] -file {'+(O/'focus_lock_stage1.timing').as_posix()+'}\nexit\n'
call('focus_lock_stage1',timing)
slacks=[float(x) for x in re.findall(r'Slack\s*:\s*([\d.-]+)ns',(O/'focus_lock_stage1.timing').read_text(encoding='utf-8'))]
assert slacks and min(slacks)>=0,slacks
result=dict(result='PASS',hardware_tested=False,scope='final routed pixel-domain registered ownership source plus two serial net-domain registers; internal stage1 setup/hold explicitly timed',database_sha256=sha(db),registered_outputs=[d[0] for d in drivers],stage1_slacks_ns=slacks,source_hashes={p:sha(F/p) for p in ['rtl/ddr/smart_camera_ddr_top.v','rtl/network/camera_ethernet.v']})
(F/'review/focus_lock_proof.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2),flush=True)
