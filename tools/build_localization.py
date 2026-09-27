"""Compile the offline ten-language mount menu. No network service is used."""
import json
import re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
data=json.loads((ROOT/'localization/ui.json').read_text(encoding='utf-8'))
quote=lambda value:json.dumps(value,ensure_ascii=False)
out=['-- Generated from localization/ui.json by tools/build_localization.py.', 'return {rows={']
for key,values in data['strings'].items():
    assert len(values)==9 and all(values),key
    assert all(sorted(re.findall(r'\{\d+\}',v))==sorted(re.findall(r'\{\d+\}',key)) for v in values),key
    out.append(' ['+quote(key)+']={'+','.join(quote(v) for v in values)+'},')
out+=['},help={']
for key,value in data['help'].items():out.append(' ['+quote(key)+']='+quote(value)+',')
out+=['}}']
(ROOT/'Scripts/translations.lua').write_text('\n'.join(out)+'\n',encoding='utf-8')
print('Compiled',len(data['strings']),'mount strings in ten languages.')
