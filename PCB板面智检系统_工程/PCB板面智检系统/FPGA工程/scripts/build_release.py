from pathlib import Path
import subprocess,sys,json,shutil
R=Path(__file__).resolve().parents[1]
for folder in ('work','review'): (R/folder).mkdir(exist_ok=True)
target=next(iter(json.loads((R/'project.json').read_text(encoding='utf-8'))))
def run(name,*args): subprocess.run([sys.executable,str(R/'scripts'/name),*map(str,args)],cwd=R,check=True)
run('build.py',target,'--report-name','release_build.json','--no-release')
record=json.loads((R/'review/release_build.json').read_text(encoding='utf-8'))
run('finalize_1080p.py',record['run'])
run('audit_focus_lock.py')
shutil.copy2(R/'bitstreams'/(target+'.bit'),R/'bitstreams/PCB_Camera.bit')
print('Build and routed checks passed. See review/ for the new build record.')
