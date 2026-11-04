"""Audit routed CDC connectivity, close timing, publish only a passing bit."""
from pathlib import Path
import re,json,subprocess,hashlib,shutil,argparse,os
R=Path(__file__).resolve().parents[1];T='smart_camera_v26_7_fast_ui'
P='u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]'
D='u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
ap=argparse.ArgumentParser();ap.add_argument('run',type=Path);ap.add_argument('--inspect',action='store_true');a=ap.parse_args()
run=a.run.resolve();assert R.resolve() in run.parents
source=run/'phy_1'/f'{T}_pr.db';assert source.is_file()
build=json.loads((R/'review/release_build.json').read_text())
cfg=json.loads((R/'project.json').read_text())[T]
assert build['rom_staging_validation']['passed']
assert not build['syn_1']['errors'] and not build['phy_1']['errors']
for rel in cfg['sources']+[cfg['adc'],cfg['ip']['xml']]:
    assert sha(R/rel)==build['source_hashes'][rel], 'RTL changed since synthesis: '+rel
out=R/'review/final1080';out.mkdir(parents=True,exist_ok=True)
TD=str(Path(os.environ.get('ANLOGIC_HOME','D:/TD_6_2/Anlogic'))/'bin/td_commands_prompt.exe')
def call(name,body):
    script=out/(name+'.tcl');log=out/(name+'.log');script.write_text(body,encoding='utf-8')
    with log.open('w',encoding='utf-8') as f:
        p=subprocess.run([TD,script.as_posix()],cwd=source.parent,stdin=subprocess.DEVNULL,stdout=f,stderr=subprocess.STDOUT)
    t=log.read_text(encoding='utf-8',errors='replace')
    assert p.returncode==0 and not re.search(r'\bERROR\s*:|EMPTY_REQUIRED',t),t[-3500:]
    print(name,'PASS',flush=True);return t
header=f'import_device ph1_50p.db -package PH1P50SBG484 -speed 3\nimport_db {{{source.as_posix()}}}\n'
net='u_pipeline/native_path$u_buffer/hold_sync[0]'
conn=call('connections',header+'report_nets [get_nets {'+net+'}] -connection\nexit\n')
section=conn.split('Net: '+net,1)[1]
drivers,loads=section.split('Driver pin(s):',1)[1].split('Load pin(s):',1)
pins=lambda s:re.findall(r'RUN-1001 :\s+\d+\s+\|\s+(\S+)\s+\|',s)
first,second=pins(drivers),pins(loads);assert len(first)==len(second)==1,(first,second)
first_cell=first[0].rsplit('.',1)[0]
cells=call('cells',header+'report_cells [get_cells {'+first_cell+'}] -connection\nexit\n')
section=cells.split('Inst      : '+first_cell,1)[1].split('Output Pin(s):',1)[0]
inputs=re.findall(r'\|\s*(i\w*)\s*\|\s*(\S+)\s*$',section,re.M)
selected=[(pin,net) for pin,net in inputs if re.match(r'(?:u_app/(?:fs/snap_hold|play_enable|fs/found_slot_reg|ui_page(?:\[\d+\])?)|(?:.*/)?hold_display)',net)]
assert selected,(inputs,section)
command='set_false_path -from [get_clocks {'+P+'}] -through [get_pins {'+' '.join(first_cell+'.'+p for p,n in selected)+'}] -to [get_clocks {'+D+'}]'
# Narrow, audited CDC binding for the synthesized playback comparator alias.
# RTL: ui_page == 4 -> play_enable -> hold_display -> async_reg hold_sync[0].
# Restrict this separate exception to three verified UI register Q pins,
# one alias net, and the
# single stage-0 input pin. No other endpoint, OSD path or stage-1 path is cut.
alias='u_app/osd_video/line[5]_syn_4'
alias_pins=[pin for pin,n in inputs if n==alias]
if alias_pins:
    assert len(alias_pins)==1,alias_pins
    trace=call('ui_hold_source_proof',header+
        'report_nets [get_nets {'+alias+'}] -connection\n'+
        'report_nets [get_nets {u_app/ui_page[*]}] -connection\nexit\n')
    block=trace.split('Net: '+alias,1)[1].split('Net:',1)[0]
    # Packing may move this same comparator from ie to id (or another input).
    # Bind only the one pin that the queried net actually drives, preserving
    # the unrelated startup/OSD logic that may share this physical slice.
    target=first_cell+'.'+alias_pins[0]
    assert target in pins(block.split('Load pin(s):',1)[1])
    sources=[]
    for bit in range(4):
        block=trace.split('Net: u_app/ui_page['+str(bit)+']',1)[1].split('Net:',1)[0]
        drivers=pins(block.split('Driver pin(s):',1)[1].split('Load pin(s):',1)[0])
        assert len(drivers)==1 and drivers[0].startswith('u_app/ui_page_reg[') and '.oq' in drivers[0]
        sources+=drivers
    command+='\n# Only UI state Q -> playback comparator -> hold synchronizer stage 0.\n'
    # The same packed slice can also contain pixel-domain startup logic.
    # Restrict capture to DDR; those pixel -> pixel paths stay timed.
    command+='set_false_path -from [get_pins {'+' '.join(sources)+'}] -through [get_pins {'+target+'}] -to [get_clocks {'+D+'}]'
sdc=R/'project/smart_camera_ddr.sdc';text=sdc.read_text()
text=text.split('# V26.1 physical hold CDC binding')[0]
text+='\n# V26.1 physical hold CDC binding: pixel inputs to DDR stage 0 only.\n'+command+'\n'
sdc.write_text(text)
base=header+'start_timer\nclear_sdc -user\nread_sdc {'+sdc.as_posix()+'}\nupdate_timing -mode final\n'
proof=f'''set a [get_pins {{{first[0]}}}]
set b [get_pins {{{second[0]}}}]
if {{[llength $a]!=1 || [llength $b]!=1}} {{error EMPTY_REQUIRED_HOLD_PINS}}
report_timing_path -from $a -to $b -file {{{(out/'hold_stage1.timing').as_posix()}}}
'''
queries=[]
for i,line in enumerate(text.splitlines(),1):
    if not line.startswith(('set_','create_')):continue
    for m in re.finditer(r'\[(get_(?:clocks|nets|pins|ports)\s+\{[^}]*\})\]',line):
        expr='['+m[1]+']';queries.append(f'puts "SELECTOR_{i}_{m.start()} [llength {expr}]"\nif {{[llength {expr}]==0}} {{error EMPTY_REQUIRED_SELECTOR_{i}}}\n')
validation=call('validate',base+''.join(queries)+proof+f'report_timing_summary -file {{{(out/"before.timing").as_posix()}}}\nexit\n')
# The candidate DB retains its original SDC. start_timer evaluates that
# embedded copy before clear_sdc; a removed LED heartbeat may warn here. Audit
# the replacement SDC strictly, and retain only this bounded inherited warning.
marker='RUN-1002 : start command "clear_sdc -user"'
assert marker in validation
import_phase,current_phase=validation.split(marker,1)
inherited_warnings=[line for line in import_phase.splitlines() if re.search(r'CRITICAL-WARNING|No (?:pins|nets|clocks) matched',line)]
assert all('ddr_cycles[26]' in line or 'value for option -through is invalid' in line for line in inherited_warnings),inherited_warnings
assert not re.search(r'CRITICAL-WARNING|No (?:pins|nets|clocks) matched',current_phase),current_phase[-4000:]
(out/'inherited_constraint_warning.json').write_text(json.dumps(dict(scope='candidate DB embedded SDC before explicit clear_sdc only; replacement SDC checked strictly; final exported DB must reload without warnings',warnings=inherited_warnings,active_sdc_sha256=sha(sdc)),indent=2))
def timing(p):
    t=p.read_text();assert 'Check Corner        : Both (Slow and Fast)' in t
    return tuple(float(re.search(k+r':\s*([\d.-]+)',t)[1]) for k in ['SWNS','HWNS'])
sw,hw=timing(out/'before.timing');print('before final setup/hold',sw,hw,flush=True)
if a.inspect:raise SystemExit()
db=out/(T+'_final.db');bit=out/(T+'.bit')
optimization='phys_opt -post_route -effort ultra -mode relocation\nfix_hold\n' if sw<0 or hw<0 else ''
call('optimize',base+optimization+'update_timing -mode final\n'+proof+
    f'report_timing_summary -file {{{(out/"final.timing").as_posix()}}}\n'+
    f'report_qor -step route -file {{{(out/"final.qor").as_posix()}}}\n'+
    f'report_abnormal_timing_target -file {{{(out/"abnormal.rpt").as_posix()}}}\nexport_db {{{db.as_posix()}}}\nexit\n')
# Reload the exported physical DB to check timing and connectivity independently.
reload_header=f'import_device ph1_50p.db -package PH1P50SBG484 -speed 3\nimport_db {{{db.as_posix()}}}\n'
reload_body=reload_header+'start_timer\nclear_sdc -user\nread_sdc {'+sdc.as_posix()+'}\nupdate_timing -mode final\n'
reload_log=call('reload_final',reload_body+proof+'report_cells [get_cells {'+first_cell+'}] -connection\n'+
    f'report_timing_summary -file {{{(out/"reload_final.timing").as_posix()}}}\nexit\n')
assert not re.search(r'CRITICAL-WARNING|No (?:pins|nets|clocks) matched',reload_log),reload_log[-4000:]
for pin,net in selected:
    assert re.search(r'\|\s*'+re.escape(pin)+r'\s*\|\s*'+re.escape(net)+r'\s*$',reload_log,re.M),(pin,net)
assert timing(out/'reload_final.timing')==timing(out/'final.timing')
sw,hw=timing(out/'reload_final.timing');holdtext=(out/'hold_stage1.timing').read_text()
slacks=[float(x) for x in re.findall(r'Slack\s*:\s*([\d.-]+)ns',holdtext)]
record=dict(result='PASS_PENDING_HARDWARE' if sw>=0 and hw>=0 else 'FAIL_TIMING',hardware_tested=False,
    setup_wns_ns=sw,hold_wns_ns=hw,hold_stage1_slacks_ns=slacks,
    hold_first_output=first[0],hold_second_input=second[0],hold_first_data_inputs=selected,
    added_constraint=command,sdc_sha256=sha(sdc),database_sha256=sha(db),source_database_sha256=sha(source))
(out/'result.json').write_text(json.dumps(record,indent=2))
assert sw>=0 and hw>=0,(sw,hw)
assert slacks and min(slacks)>=0,slacks
ft=(out/'final.timing').read_text()
video=re.search(r'([0-9.]+)\s+\d+\s+'+re.escape(P),ft)
serial=re.search(r'([0-9.]+)\s+\d+\s+'+re.escape(P.replace('[0]','[1]')),ft)
assert video and serial and abs(float(video[1])-114.75)<.02 and abs(float(serial[1])/float(video[1])-5)<.003,(video,serial)
record['video_clock_mhz']=float(video[1]);record['serializer_clock_mhz']=float(serial[1])
call('bitgen',f'import_device ph1_50p.db -package PH1P50SBG484 -speed 3\nimport_db {{{db.as_posix()}}}\nbitgen -bit {{{bit.as_posix()}}}\nexit\n')
assert bit.is_file()
dest=R/'bitstreams'/bit.name;shutil.copy2(bit,dest)
record['bitstream_sha256']=sha(dest)
record['active_source_hashes']={rel:sha(R/rel) for rel in json.loads((R/'project.json').read_text())[T]['sources']}
record['resource_text']=(out/'final.qor').read_text()
(out/'result.json').write_text(json.dumps(record,indent=2));print('PASS final bit',record['bitstream_sha256'],flush=True)

build['initial_flow_result']=build['result']
build['implementation_flow_timing']={'setup_wns_ns':build.get('setup_wns_ns'),'hold_wns_ns':build.get('hold_wns_ns')}
build.update(result='PASS_BUILD_PENDING_HARDWARE',setup_wns_ns=sw,hold_wns_ns=hw,
    bitstream=dest.as_posix(),bitstream_sha256=record['bitstream_sha256'],post_route_validation=record)
build['source_hashes'][cfg['sdc']]=sha(sdc)
(R/'review/release_build.json').write_text(json.dumps(build,indent=2))
