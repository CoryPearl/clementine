#!/usr/bin/env python3
"""Build a relocatable Apple silicon application, including its offline engines."""
import argparse, hashlib, json, os, plistlib, re, shutil, subprocess, sys, uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
DIST=ROOT/'dist'; APP=DIST/'Clementine.app'; CONTENTS=APP/'Contents'; RES=CONTENTS/'Resources'; TOOLS=RES/'Tools'; LIB=TOOLS/'lib'
def run(*args, **kw):
    return subprocess.check_output([str(a) for a in args], text=True, stderr=kw.pop('stderr', subprocess.STDOUT), **kw)
def cp(src,dst):
    src=Path(src);dst=Path(dst)
    dst.parent.mkdir(parents=True,exist_ok=True)
    temporary=dst.with_name('.'+dst.name+'.copy-'+uuid.uuid4().hex)
    try:
        shutil.copy2(src,temporary,follow_symlinks=True)
        temporary.chmod(temporary.stat().st_mode | 0o200)
        os.replace(temporary,dst)
    finally:
        temporary.unlink(missing_ok=True)
def tree(src,dst,**kw):
    return shutil.copytree(src,dst,copy_function=cp,**kw)
def deps(path):
    return [line.strip().split(' (compatibility')[0] for line in run('/usr/bin/otool','-L',path).splitlines()[1:] if 'compatibility' in line]
def macho(path):
    try:
        with path.open('rb') as f:header=f.read(8)
        if header[:4] in [bytes.fromhex(s) for s in ['cffaedfe','feedfacf']]:return True
        if header[:4] in [bytes.fromhex(s) for s in ['cafebabe','cafebabf']]:return 0 < int.from_bytes(header[4:8],'big') < 16
        if header[:4]==bytes.fromhex('bebafeca'):return 0 < int.from_bytes(header[4:8],'little') < 16
        return False
    except OSError:return False
seen={}; pending=[]; manifests={}
def queue(src,dst):
    src=Path(src).resolve();dst=Path(dst)
    if dst in seen:
        if seen[dst] != src and hashlib.sha256(src.read_bytes()).digest()!=hashlib.sha256(seen[dst].read_bytes()).digest():raise RuntimeError(f'Duplicate library: {dst}')
        return
    seen[dst]=src; cp(src,dst); pending.append((src,dst))
def resolve(dep,src):
    if dep.startswith('@loader_path/'):return src.parent/dep[len('@loader_path/'):]
    if dep.startswith('@rpath/'):
        name=dep[len('@rpath/'):]
        paths=[]
        lines=run('/usr/bin/otool','-l',src).splitlines()
        for i,line in enumerate(lines):
            if 'cmd LC_RPATH' in line:
                for row in lines[i+1:i+4]:
                    if row.strip().startswith('path '):
                        base=row.strip().split('path ',1)[1].split(' (offset')[0].replace('@loader_path',str(src.parent))
                        paths.append(Path(base)/name)
        paths += [src.parent/name,Path('/opt/homebrew/lib')/name]
        for p in paths:
            if p.exists():return p.resolve()
        raise RuntimeError(f'Cannot resolve {dep} from {src}')
    return Path(dep)
def closure():
    while pending:
        src,dst=pending.pop(0)
        for dep in deps(src):
            if dep.startswith(('/System/','/usr/lib/')):continue
            target=resolve(dep,src)
            # Mach-O dylib identifiers also appear in otool output.
            if target.resolve()==src:continue
            if not target.exists():raise RuntimeError(f'Missing dependency: {target}')
            bundled=LIB/target.name;queue(target,bundled)
            rel=os.path.relpath(bundled,dst.parent)
            run('/usr/bin/install_name_tool','-change',dep,'@loader_path/'+rel,dst)
        if dst.suffix in ['.dylib','.so']:run('/usr/bin/install_name_tool','-id','@rpath/'+dst.name,dst)

def build_tools():
    print('Bundling conversion engines and dynamic libraries…',flush=True)
    for name in ['ffmpeg','ffprobe','magick','pandoc','rsvg-convert']:
        path=shutil.which(name)
        if not path:raise RuntimeError(f'{name} is required to package; install with Homebrew.')
        queue(path,TOOLS/name)
    (TOOLS/'fonts.conf').write_text('''<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig><dir>/System/Library/Fonts</dir><dir>/Library/Fonts</dir><dir prefix="xdg">fonts</dir><cachedir prefix="xdg">fontconfig</cachedir><config><rescan><int>0</int></rescan></config></fontconfig>''')
    prefix=Path(run('brew','--prefix','imagemagick').strip())
    modules=list((prefix/'lib/ImageMagick').glob('modules-*/coders'))[0]
    for module in modules.glob('*.so'):queue(module,TOOLS/'ImageMagick/modules'/module.name)
    for metadata in modules.glob('*.la'):
        dest=TOOLS/'ImageMagick/modules'/metadata.name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(re.sub(r"^libdir=.*$","libdir=''",metadata.read_text(),flags=re.M))
    tree(prefix/'etc/ImageMagick-7',TOOLS/'ImageMagick/config',dirs_exist_ok=True)
    # No remote resources, scripted coders, or external delegates are needed.
    (TOOLS/'ImageMagick/config/policy.xml').write_text('''<policymap>
<policy domain="resource" name="memory" value="512MiB"/><policy domain="resource" name="map" value="1GiB"/>
<policy domain="resource" name="disk" value="4GiB"/><policy domain="resource" name="width" value="30KP"/>
<policy domain="resource" name="height" value="30KP"/><policy domain="delegate" rights="none" pattern="*"/>
<policy domain="coder" rights="none" pattern="{HTTP,HTTPS,URL,FTP,MVG,MSL,EPHEMERAL}"/>
</policymap>''')
    exif=Path(run('brew','--prefix','exiftool').strip())/'libexec'
    if (TOOLS/'exiftool').is_dir():shutil.rmtree(TOOLS/'exiftool')
    # The Perl program looks for its modules beside itself, avoiding Homebrew paths.
    cp(exif/'bin/exiftool',TOOLS/'exiftool')
    tree(exif/'lib/perl5',TOOLS/'lib',dirs_exist_ok=True)
    for native in (exif/'lib/perl5').rglob('*'):
        if native.is_file() and macho(native):queue(native,TOOLS/'lib'/native.relative_to(exif/'lib/perl5'))
    office=ROOT/'vendor/LibreOffice.app'
    if not office.exists():
        print('Extracting LibreOffice from its verified Homebrew download…',flush=True)
        cached=list((Path.home()/'Library/Caches/Homebrew/downloads').glob('*--LibreOffice_*_MacOS_aarch64.dmg'))
        if not cached:
            run('brew','fetch','--cask','libreoffice');cached=list((Path.home()/'Library/Caches/Homebrew/downloads').glob('*--LibreOffice_*_MacOS_aarch64.dmg'))
        info=json.loads(run('brew','info','--json=v2','--cask','libreoffice'))['casks'][0]
        dmg=next((p for p in cached if hashlib.sha256(p.read_bytes()).hexdigest()==info['sha256']),None)
        if dmg is None:raise RuntimeError('LibreOffice download checksum does not match Homebrew metadata.')
        mount=Path('/private/tmp/clementine-office-mount');mount.mkdir(exist_ok=True)
        run('hdiutil','attach','-readonly','-nobrowse','-mountpoint',mount,dmg)
        try:tree(mount/'LibreOffice.app',office,symlinks=True)
        finally:run('hdiutil','detach',mount)
    tree(office,TOOLS/'LibreOffice.app',symlinks=True,dirs_exist_ok=True)
    closure()
    # Collect dependency versions, installed recipes, and shipped notices.
    license_dir=RES/'Licenses';license_dir.mkdir(parents=True,exist_ok=True)
    formulae={}
    for src in seen.values():
        parts=src.parts
        if 'Cellar' in parts:
            i=parts.index('Cellar');formulae[parts[i+1]]=Path(*parts[:i+3])
    formulae['exiftool']=exif.parent
    versions={}
    for name,prefix in sorted(formulae.items()):
        dest=license_dir/name;dest.mkdir(exist_ok=True)
        versions[name]=prefix.name
        for pattern in ['*LICENSE*','*COPYING*','*NOTICE*','*Copyright*','.brew/*.rb','share/doc/**/*LICENSE*','share/doc/**/*COPYING*']:
            for p in prefix.glob(pattern):
                if p.is_file():cp(p,dest/p.name)
    for name in ['LICENSE','NOTICE','CREDITS','license.html']:
        for p in office.rglob(name):
            if p.is_file():cp(p,license_dir/'LibreOffice'/p.name)
    (license_dir/'THIRD-PARTY.txt').write_text('''Clementine bundles independently sourced open-source conversion tools.
FFmpeg: https://ffmpeg.org/ (this build includes GPL codecs)
ImageMagick: https://imagemagick.org/ (ImageMagick License)
ExifTool: https://exiftool.org/ (Artistic License / GPL)
Pandoc: https://pandoc.org/ (GPL)
librsvg: https://gitlab.gnome.org/GNOME/librsvg (LGPL)
LibreOffice: https://www.libreoffice.org/ (MPL 2.0 and other component licenses)
Apple system libraries and apps are supplied by macOS.

Installed Homebrew formula recipes in the adjacent directories identify exact
source URLs, patches and build flags for the bundled formulae. Bundled
components retain their respective licenses. Source directions and notices:
https://github.com/CoryPearl/clementine/tree/main/ThirdParty
''')
    (RES/'dependency-versions.json').write_text(json.dumps(versions,indent=2))

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--reuse-tools',action='store_true');parser.add_argument('--no-zip',action='store_true');args=parser.parse_args()
    print('Compiling Swift release…',flush=True);print(run('swift','build','-c','release',cwd=ROOT)[-1000:])
    (CONTENTS/'MacOS').mkdir(parents=True,exist_ok=True);TOOLS.mkdir(parents=True,exist_ok=True);LIB.mkdir(exist_ok=True)
    cp(ROOT/'.build/release/Clementine',CONTENTS/'MacOS/Clementine')
    plist={'CFBundleName':'Clementine','CFBundleDisplayName':'Clementine','CFBundleIdentifier':'local.clementine.mac','CFBundleExecutable':'Clementine','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.2','CFBundleVersion':'3','CFBundleIconFile':'Clementine.icns','LSUIElement':True,'LSMinimumSystemVersion':'26.0','NSHighResolutionCapable':True,'NSPrincipalClass':'NSApplication','NSAppleEventsUsageDescription':'Clementine uses Pages, Numbers, and Keynote to convert your documents locally.','LSApplicationCategoryType':'public.app-category.utilities','CFBundleDocumentTypes':[{'CFBundleTypeName':'Files','CFBundleTypeRole':'Viewer','LSHandlerRank':'Alternate','LSItemContentTypes':['public.data','public.content','public.folder']}]}
    with (CONTENTS/'Info.plist').open('wb') as f:plistlib.dump(plist,f)
    iconset=ROOT/'.build/Clementine.iconset';run('swift',ROOT/'scripts/icon.swift',iconset)
    run('iconutil','-c','icns',iconset,'-o',RES/'Clementine.icns')
    if not args.reuse_tools:
        if TOOLS.exists():shutil.rmtree(TOOLS)
        TOOLS.mkdir(parents=True);LIB.mkdir()
        build_tools()
    notices=RES/'Licenses/THIRD-PARTY.txt'
    if notices.exists():
        notices.write_text(notices.read_text().replace('This package is\nfor personal local use. Bundled components retain their respective licenses.', 'Bundled components retain their respective licenses.\nSource directions and notices:\nhttps://github.com/CoryPearl/clementine/tree/main/ThirdParty'))
    if notices.exists() and 'librsvg:' not in notices.read_text():
        notices.write_text(notices.read_text()+'\nlibrsvg: https://gitlab.gnome.org/GNOME/librsvg (LGPL)\n')
    # Verify that every bundled engine dependency resolves inside the app or macOS.
    machos=[]
    for path in TOOLS.rglob('*'):
        if path.is_file() and not path.is_symlink() and macho(path):
            external=[d for d in deps(path) if d.startswith(('/opt/','/usr/local/','/Users/')) and Path(d).name != path.name]
            if external:raise RuntimeError(f'External dependency in {path}: {external}')
            machos.append(path)
    print(f'Signing {len(machos)} bundled Mach-O files…',flush=True)
    if not args.reuse_tools:
        for path in machos:
            run('codesign','--force','--sign','-','--timestamp=none',path)
        # LibreOffice has several nested app bundles; sign deepest containers first.
        for path in sorted(TOOLS.rglob('*.app'),key=lambda p:len(p.parts),reverse=True):run('codesign','--force','--deep','--sign','-','--timestamp=none',path)
    run('codesign','--force','--sign','-','--timestamp=none',APP)
    run('codesign','--verify','--deep','--strict','--verbose=2',APP)
    if not args.no_zip:
        print('Creating installation ZIP…',flush=True)
        archive=DIST/'Clementine.zip'
        if archive.exists():archive.unlink()
        run('ditto','-c','-k','--sequesterRsrc','--keepParent',APP,archive)
    print(f'Built {APP}',flush=True)
if __name__=='__main__':main()
