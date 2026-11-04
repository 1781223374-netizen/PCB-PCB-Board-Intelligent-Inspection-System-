"""Create a relocatable source-browsing TD project from the active manifest."""
from pathlib import Path
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
for name, cfg in json.loads((ROOT / 'project.json').read_text(encoding='utf-8')).items():
    tree = ET.ElementTree(ET.fromstring((ROOT / 'reference/project_template.xml').read_text(encoding='utf-8').replace('P&R', 'P&amp;R')))
    project = tree.getroot()
    project.attrib.pop('Path', None)
    project.find('Name').text = name
    project.find('TOP_MODULE/LABEL').text = cfg['top']
    project.find('TOP_MODULE/MODULE').text = cfg['top']
    sources = project.find('Source_Files');sources.clear();groups = {}
    for i, rel in enumerate(cfg['sources'] + [cfg['ip']['xml'], cfg['adc'], cfg['sdc']], 1):
        kind = ('IP_FILE' if rel.endswith('.xml') else 'ADC_FILE' if rel.endswith('.adc') else
                'SDC_FILE' if rel.endswith('.sdc') else 'System_Verilog' if rel.endswith('.sv') else 'Verilog')
        if kind not in groups:
            groups[kind] = ET.SubElement(sources, kind)
        file = ET.SubElement(groups[kind], 'File', Path='../' + rel)
        info = ET.SubElement(file, 'FileInfo')
        for key, value in [('UsedInSyn', 'true'), ('UsedInP&R', 'true'),
                           ('BelongTo', 'constraint_1' if kind in ['ADC_FILE','SDC_FILE'] else 'design_1'), ('CompileOrder', str(i))]:
            ET.SubElement(info, 'Attr', Name=key, Val=value)
        assert (ROOT / rel).is_file(), rel
    out = ROOT / 'project' / (name + '.al')
    tree.write(out, encoding='utf-8', xml_declaration=True)
    check = ET.parse(out)
    for file in check.findall('Source_Files/*/File'):
        assert (out.parent / file.get('Path')).resolve().is_file()
    print('PASS relative TD source project:', out.name)
