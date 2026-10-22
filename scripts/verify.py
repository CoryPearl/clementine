#!/usr/bin/env python3
"""Verify the packaged app without opening Pages or other Apple office apps."""
from pathlib import Path
import json, os, plistlib, shutil, subprocess, tempfile
ROOT=Path(__file__).resolve().parents[1]
APP=ROOT/'dist/Clementine.app'
def run(args,**kw):
    return subprocess.run([str(x) for x in args],check=True,capture_output=True,text=True,**kw)
run(['codesign','--verify','--deep','--strict',APP])
# A copied app in a differently named directory tests @loader_path and resource resolution.
with tempfile.TemporaryDirectory(prefix='Clementine-relocation-') as temp:
    relocated=Path(temp)/'A Different Folder'/'Clementine.app'
    relocated.parent.mkdir()
    run(['ditto',APP,relocated])
    binary=relocated/'Contents/MacOS/Clementine'
    env={'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','HOME':str(Path.home()),'TMPDIR':temp+'/', 'CLEMENTINE_DISABLE_APPLE_AUTOMATION':'1'}
    source=Path(temp)/'sample.svg'
    source.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80"><rect width="120" height="80" fill="#F56D29"/><text x="10" y="40" font-size="18">Clementine</text></svg>')
    out=Path(temp)/'outputs';out.mkdir()
    svg=run([binary,'--convert','png',source,'--output',out],env=env)
    raster=Path(svg.stdout.strip().splitlines()[-1])
    assert raster.exists() and raster.stat().st_size>100
    pdf=run([binary,'--convert','pdf',raster,'--output',out],env=env)
    assert Path(pdf.stdout.strip().splitlines()[-1]).exists()
    doc=Path(temp)/'sample.txt';doc.write_text('Clementine\n\nA document converted by the relocated app.')
    office=run([binary,'--convert','pdf',doc,'--output',out],env=env)
    assert Path(office.stdout.strip().splitlines()[-1]).exists()
    run([binary,'--snapshot',ROOT/'dist/verification/home.png'],env=env)
report={'signature':'verified','relocation':'passed','svg_to_png':'passed','image_to_pdf':'passed','document_to_pdf':'passed','runtime_path':'macOS system tools only','apple_apps':'not launched'}
(ROOT/'dist/verification').mkdir(exist_ok=True)
(ROOT/'dist/verification/package.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
