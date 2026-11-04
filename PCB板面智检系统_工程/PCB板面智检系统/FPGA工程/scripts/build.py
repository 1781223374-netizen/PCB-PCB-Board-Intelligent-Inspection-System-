"""Two-stage TD flow copied from the vendor's synthesis/physical settings.

No .db from the manufacturer is reused. ROM relative paths, content and
elaboration parameters are checked; hardware initialization is tested on board.
The local TD version is recorded, not misrepresented as the factory version.
"""
from pathlib import Path
from datetime import datetime
import argparse, hashlib, json, os, re, shutil, subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
TD = Path(os.environ.get('ANLOGIC_HOME', 'D:/TD_6_2/Anlogic'))
FLOW = next((p for p in [TD / 'scripts/DefaultFlow.tcl',
                        TD / 'doc/scripts/DefaultFlow.tcl'] if p.is_file()), None)
if FLOW is None or not (TD / 'bin/td_commands_prompt.exe').is_file():
    raise SystemExit('TD executable/DefaultFlow.tcl not found under ' + str(TD))
ap = argparse.ArgumentParser()
ap.add_argument('target')
ap.add_argument('--report-name')
ap.add_argument('--bit-name')
ap.add_argument('--no-release',action='store_true',help='Keep experimental bit only in the private run directory until finalize_1080p.py verifies routed timing')
ap.add_argument('--resume-run',type=Path,help='Resume physical implementation from a completed, source-verified gate database')
opt = ap.parse_args()
for value in [opt.report_name,opt.bit_name]:
    if value and Path(value).name != value:raise SystemExit('Output overrides must be plain filenames')
configs = json.loads((ROOT / 'project.json').read_text(encoding='utf-8'))
cfg = configs[opt.target]
name = opt.target
run = opt.resume_run.resolve() if opt.resume_run else ROOT / 'work' / (name + '_' + datetime.now().strftime('%Y%m%d_%H%M%S'))
assert ROOT.resolve() in run.resolve().parents
previous=None
if opt.resume_run:
    previous=json.loads((ROOT/'review'/(opt.report_name or name+'_build.json')).read_text(encoding='utf-8'))
    assert Path(previous['run']).resolve()==run and previous['target']==name
    for rel in cfg['sources']+[cfg['adc'],cfg['sdc'],cfg['ip']['xml']]:
        assert hashlib.sha256((ROOT/rel).read_bytes()).hexdigest()==previous['source_hashes'][rel],rel
    assert (run/'syn_1/.opt_gate.end.f').exists() and (run/'syn_1'/(name+'_gate.db')).is_file()
run.mkdir(parents=True,exist_ok=bool(opt.resume_run))

def path(rel):
    p = (ROOT / rel).resolve()
    assert p.is_file(), p
    return p.as_posix()

template = ET.ElementTree(ET.fromstring((ROOT / 'reference/project_template.xml').read_text(encoding='utf-8').replace('P&R', 'P&amp;R')))
prj = template.getroot()
prj.attrib.pop('Path', None)
prj.find('Name').text = name
prj.find('TOP_MODULE/LABEL').text = cfg['top']
prj.find('TOP_MODULE/MODULE').text = cfg['top']
sources = prj.find('Source_Files')
sources.clear()
groups = {}
files = cfg['sources'] + [cfg['ip']['xml'], cfg['adc'], cfg['sdc']]
for i, rel in enumerate(files, 1):
    kind = ('IP_FILE' if rel.endswith('.xml') else 'ADC_FILE' if rel.endswith('.adc')
            else 'SDC_FILE' if rel.endswith('.sdc') else 'System_Verilog' if rel.endswith('.sv') else 'Verilog')
    group = groups.setdefault(kind, ET.SubElement(sources, kind)) if kind not in groups else groups[kind]
    f = ET.SubElement(group, 'File', Path=path(rel))
    info = ET.SubElement(f, 'FileInfo')
    for key, value in [('UsedInSyn', 'true'), ('UsedInP&R', 'true'),
                       ('BelongTo', 'constraint_1' if kind in ['ADC_FILE','SDC_FILE'] else 'design_1'),
                       ('CompileOrder', str(i))]:
        ET.SubElement(info, 'Attr', Name=key, Val=value)

# Exact factory RTL can keep its ../mcu_rom path even in a relocated build.
mcu_rom = ROOT / 'vendor_ddr/prj_src/rtl/usr_mcu_srcs/mcu_rom/mcu_rom.txt'
phy_rom = ROOT / 'vendor_ddr/prj_src/ip/ddrmc_x32/src/rtl/phy/ddrphy_cfg_rom.txt'
if cfg.get('rom_loads_required',1)==2:
    (run / 'mcu_rom').mkdir(exist_ok=bool(opt.resume_run))
    shutil.copy2(mcu_rom, run / 'mcu_rom/mcu_rom.txt')
status = {'target': name, 'run': run.as_posix(), 'result': 'RUNNING',
          'hardware_tested': False, 'factory_td_version': '6.2.190657',
          'two_stage': True, 'scope': cfg['scope'], 'source_hashes': {},
          'tool_home': TD.as_posix(), 'flow_script': FLOW.as_posix(),
          'tool_hashes': {p.relative_to(TD).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in [TD / 'bin/td_commands_prompt.exe', FLOW,
                                    TD / 'arch/ph1_50p.db', TD / 'arch/ph1p_macro.v',
                                    TD / 'arch/system.db'] if p.is_file()}}
for base in ['vendor_ddr', 'ethernet_ip', 'rtl', 'v16/rtl', 'v16/vendor', 'v16/constraints', 'project', 'scripts']:
    for p in sorted((ROOT / base).rglob('*')):
        if p.is_file(): status['source_hashes'][p.relative_to(ROOT).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
status['source_hashes']['project.json'] = hashlib.sha256((ROOT / 'project.json').read_bytes()).hexdigest()
report = ROOT / 'review' / (opt.report_name or name + '_build.json')

def save():
    report.write_text(json.dumps(status, indent=2, ensure_ascii=False), encoding='utf-8')

save()
print('RUN', run, flush=True)
logs = ''
for stage, start, end in [('syn_1', 'read_design', 'opt_gate'), ('phy_1', 'opt_place', 'bitgen')]:
    d = run / stage
    if previous and stage=='syn_1':
        status[stage]=previous[stage]
        status['local_td_version']=previous['local_td_version']
        logs+=(d/'full_run.log').read_text(encoding='utf-8',errors='replace')
        status['synthesis_exit_recovery']={'original_returncode':previous[stage]['returncode'],
            'completion_marker':True,'source_hashes_verified':True,
            'gate_database_sha256':hashlib.sha256((d/(name+'_gate.db')).read_bytes()).hexdigest(),
            'note':'Full physical flow reloads the completed gate DB in a fresh TD process. Original abnormal exit remains recorded.'}
        save();continue
    d.mkdir(exist_ok=bool(opt.resume_run))
    template.write(d / (name + '.prj'), encoding='utf-8', xml_declaration=True)
    shutil.copy2(phy_rom, d / phy_rom.name)
    settings = f'''set ADCList {{{{{path(cfg['adc'])}}}}}
set SDCList {{{{{path(cfg['sdc'])}}}}}
set IpADCList {{ {cfg['ip']['name']} {{{path(cfg['ip']['adc'])}}} }}
set IpSDCList {{ {cfg['ip']['name']} {{{path(cfg['ip']['sdc'])}}} }}
set area_option -packarea
set device_name ph1_50p.db
set package_name PH1P50SBG484
set speed 3
set prj_name {{{name}}}
set top_model_name {{{cfg['top']}}}
set start_step {start}
set end_step {end}
set run_type {'syn' if stage == 'syn_1' else 'phy'}
'''
    if stage == 'phy_1':
        settings += 'set arr_filter false\nset drHoldFix on\nset parent ../syn_1\n'
    (d / 'settings.cfg').write_text(settings, encoding='utf-8')
    with (d / 'full_run.log').open('w', encoding='utf-8') as f:
        p = subprocess.run([str(TD / 'bin/td_commands_prompt.exe'),
                            FLOW.as_posix()],
                           cwd=d, stdin=subprocess.DEVNULL, stdout=f, stderr=subprocess.STDOUT)
    s = (d / 'full_run.log').read_text(encoding='utf-8', errors='replace')
    logs += s
    version = re.search(r'Tang Dynasty, V([^\s]+)', s)
    if version: status['local_td_version'] = version[1]
    if status.get('local_td_version') != status['factory_td_version']:
        status['result'] = 'FAIL_TOOL_VERSION'
        save()
        raise SystemExit('This experiment requires factory TD ' + status['factory_td_version'])
    errors = re.findall(r'^.*\bERROR\s*:.*$', s, re.M)
    status[stage] = {'returncode': p.returncode, 'errors': errors,
                     'completed': (d / ('.' + end + '.end.f')).is_file()}
    save()
    print(stage, 'exit', p.returncode, 'errors', len(errors), flush=True)
    if p.returncode or errors or not status[stage]['completed']:
        status['result'] = 'FAIL_' + stage.upper()
        save()
        raise SystemExit(1)

status['rom_load_lines'] = re.findall(r'^.*readmemh: reading from file.*$', logs, re.M)
from validate_rom_staging import verify_roms
status['rom_staging_validation'] = verify_roms(ROOT, run, cfg, logs)
status['warnings'] = re.findall(r'^.*\bWARNING\s*:.*$', logs, re.M)
status['constraint_failures'] = re.findall(r'^USR-(?:8130|8159|8202|8208).*$', logs, re.M)
timing = (run / 'phy_1' / (name + '_pr.timing')).read_text(encoding='utf-8', errors='replace')
sw = re.search(r'SWNS:\s*(-?[\d.]+)ns', timing)
hw = re.search(r'HWNS:\s*(-?[\d.]+)ns', timing)
status['setup_wns_ns'] = float(sw[1]) if sw else None
status['hold_wns_ns'] = float(hw[1]) if hw else None
post_route_ok = True
constraints_ok = not status['constraint_failures']
if cfg.get('post_route_validation', False):
    from validate_post_route import verify_route, review_constraint_bindings
    status['implementation_flow_timing'] = {'setup_wns_ns': status['setup_wns_ns'], 'hold_wns_ns': status['hold_wns_ns']}
    validation = verify_route(ROOT, run, cfg, name)
    status['post_route_validation'] = validation
    post_route_ok = validation['passed']
    status['constraint_binding_review'] = review_constraint_bindings(ROOT, run, cfg, validation)
    constraints_ok = status['constraint_binding_review']['passed']
    if post_route_ok:
        status['setup_wns_ns'] = validation['setup_wns_ns']
        status['hold_wns_ns'] = validation['hold_wns_ns']
bit = run / 'phy_1' / (name + '.bit')
status['result'] = 'FAIL_VALIDATION'
if (name.startswith('smart_camera_v26_') and bit.is_file()
        and status['rom_staging_validation']['passed'] and sw and hw):
    # A candidate is deliberately not a timing-qualified release.
    # finalize_720p.py checks current routed connectivity and both timing corners.
    status['result'] = 'CANDIDATE_PENDING_ROUTE_AUDIT'
    status['experimental_bitstream'] = bit.as_posix()
elif (bit.is_file() and sw and hw and post_route_ok
        and status['setup_wns_ns'] >= 0 and status['hold_wns_ns'] >= 0
        and constraints_ok and status['rom_staging_validation']['passed']):
    status['result'] = 'PASS_BUILD_PENDING_HARDWARE'
    if opt.no_release or name.startswith('smart_camera_v26_'):
        status['result'] = 'PASS_FLOW_PENDING_ROUTE_AUDIT'
        status['experimental_bitstream'] = bit.as_posix()
    else:
        dest = ROOT / 'bitstreams' / (opt.bit_name or name + '.bit')
        shutil.copy2(bit, dest)
        status['bitstream'] = dest.as_posix()
        status['bitstream_sha256'] = hashlib.sha256(dest.read_bytes()).hexdigest()
status['tool_version_matches_factory'] = status.get('local_td_version') == status['factory_td_version']
save()
print(status['result'], status['setup_wns_ns'], status['hold_wns_ns'], flush=True)
if status['result'].startswith('FAIL'): raise SystemExit(1)
