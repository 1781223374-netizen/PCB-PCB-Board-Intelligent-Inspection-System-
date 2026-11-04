# -*- mode: python ; coding: utf-8 -*-
from pathlib import Path
import os

root = Path(SPECPATH).parent
a = Analysis([str(root/'source'/'launch_multicam.py')],
    pathex=[str(root/'source')], binaries=[], datas=[(str(root/'source/assets'),'assets')], hiddenimports=['surface_features'],
    hookspath=[], hooksconfig={}, runtime_hooks=[],
    excludes=['tkinter', 'matplotlib', 'scipy', 'pandas', 'torch', 'tensorflow',
              'IPython', 'PyQt5', 'PyQt6', 'PySide2'], noarchive=False, optimize=0)
# Use Windows' ICU implementation; an unrelated Poppler ICU DLL can be on PATH.
a.binaries = [entry for entry in a.binaries
              if Path(entry[0]).name.lower() not in {'icuuc.dll', 'icudt78.dll'}]
pyz = PYZ(a.pure)
exe = EXE(pyz, a.scripts, [], exclude_binaries=True, name='PCB_AOI_MultiStudio',
          debug=False, bootloader_ignore_signals=False, strip=False, upx=False,
          console=False, disable_windowed_traceback=False)
coll = COLLECT(exe, a.binaries, a.datas, strip=False, upx=False, name='PCB_AOI_MultiStudio')
