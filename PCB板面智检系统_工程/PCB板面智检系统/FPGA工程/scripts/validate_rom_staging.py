"""Check staged ROMs and elaborated initialization parameters for both TD logs.

TD 6.2.190657 omits the old successful-readmemh message. This is a filesystem/
parameter check, not a claim that hardware initialization has been observed.
"""
from pathlib import Path
import hashlib
import re


def verify_roms(root, run, cfg, log):
    required = [('phy', root / 'vendor_ddr/prj_src/ip/ddrmc_x32/src/rtl/phy/ddrphy_cfg_rom.txt',
                 Path('ddrphy_cfg_rom.txt'), 52,
                 r'elaborate module ph1p_ddrphy_init\(ROM_LEN=43,ROM_INIT="ddrphy_cfg_rom.txt"\)')]
    if cfg.get('rom_loads_required', 2) == 2:
        required.append(('mcu', root / 'vendor_ddr/prj_src/rtl/usr_mcu_srcs/mcu_rom/mcu_rom.txt',
                         Path('../mcu_rom/mcu_rom.txt'), 32,
                         r'elaborate module usr_mcu_core_tcm\(MCU_TCM_INIT="../mcu_rom/mcu_rom.txt"\)'))
    result = {'method': 'Staged relative paths, byte hashes, hex word widths and elaborated ROM parameters',
              'tool_readmemh_success_message': bool(re.search(r'readmemh: reading from file', log)),
              'hardware_initialization_observed': False, 'files': {}, 'passed': True}
    for name, source, relative, width, pattern in required:
        expected = hashlib.sha256(source.read_bytes()).hexdigest()
        values = [int(t, 16) for t in source.read_text(encoding='ascii').split()]
        parameter_found = bool(re.search(pattern, log))
        stages = {}
        for stage in ['syn_1', 'phy_1']:
            staged = (run / stage / relative).resolve()
            matching = staged.is_file() and hashlib.sha256(staged.read_bytes()).hexdigest() == expected
            stages[stage] = {'path': staged.as_posix(), 'matches_factory_source': matching}
        ok = (parameter_found and all(v['matches_factory_source'] for v in stages.values())
              and bool(values) and any(values) and all(0 <= v < (1 << width) for v in values))
        if name == 'phy':
            ok = ok and len(values) == 43
        result['files'][name] = {'sha256': expected, 'words': len(values), 'width': width,
                                 'elaborated_parameter_found': parameter_found, 'staging': stages,
                                 'passed': ok}
        result['passed'] = result['passed'] and ok
    return result
