from pathlib import Path
import subprocess,sys
R=Path(__file__).resolve().parents[1]
subprocess.run([sys.executable,'-m','PyInstaller','--noconfirm','--clean',
 str(R/'tools/PCB_AOI_MultiStudio.spec'),'--workpath',str(R/'build'),
 '--distpath',str(R/'dist')],cwd=R,check=True)
print('New application: dist/PCB_AOI_MultiStudio. Copy the launch BAT there if needed.')
