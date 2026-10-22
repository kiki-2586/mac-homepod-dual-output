#!/usr/bin/env python3
"""Package the verified local app and source without build caches or user data."""
from pathlib import Path
import hashlib,json,os,plistlib,shutil,subprocess,zipfile

root=Path(__file__).resolve().parent.parent
dist=root/'dist'
app=Path(os.environ.get('MAC_HOMEPOD_APP_PATH',str(dist/'MacHomePod.app'))).resolve()
with (app/'Contents/Info.plist').open('rb') as f:
 version=plistlib.load(f)['CFBundleShortVersionString']
stage=dist/'source-staging/MacHomePod-source'
vendor=stage/'vendor-sources'
vendor.mkdir(parents=True,exist_ok=True)
archives={
 'owntone-29.2.tar.xz':'4d5693f7fb34ced35a7a0937acca244184b46aa4cd1dc623a3f5dbfc02b7e0cf',
 'ffmpeg-7.1.2.complete.tar.xz':'089bc60fb59d6aecc5d994ff530fd0dcb3ee39aa55867849a2bbc4e555f9c304',
 'libinotify-20240724.tar.gz':'5cc3fb7af407b17b7daa871cc98bb882716c4b5c296fadfb66bfe86c37cc599c',
}
for name,digest in archives.items():
 source=root/'.deps/sources'/name
 assert hashlib.sha256(source.read_bytes()).hexdigest()==digest,name
 shutil.copy2(source,vendor/name)
(vendor/'core-source-sha256.json').write_text(json.dumps(archives,indent=2)+'\n')
manifest=json.loads((vendor/'manifest.json').read_text())
for item in manifest:
 assert hashlib.sha256((vendor/item['file']).read_bytes()).hexdigest()==item['sha256'],item['file']
# Recreate generated source content so removed upstream files cannot leak back
# into a later release. Keep the verified vendor archives between runs.
for child in stage.iterdir():
 if child==vendor:continue
 if child.is_dir():shutil.rmtree(child)
 else:child.unlink()
files=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=root).decode().split('\0')
for name in files:
 if not name or name.startswith(('.superpowers/','.omc/','.claude/')):continue
 source=root/name
 if not source.is_file():continue
 target=stage/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
shutil.copytree(root/'backend/licenses',stage/'backend/licenses',dirs_exist_ok=True)
sourcezip=dist/f'MacHomePod-{version}-source.zip'
with zipfile.ZipFile(sourcezip,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for path in sorted(stage.rglob('*')):
  if path.is_file():z.write(path,path.relative_to(stage.parent))
appzip=dist/f'MacHomePod-{version}-arm64.zip'
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(app),str(appzip)],check=True)
checksums=[]
for path in [sourcezip,appzip]:
 with zipfile.ZipFile(path) as z:assert z.testzip() is None
 digest=hashlib.sha256(path.read_bytes()).hexdigest()
 checksums.append(f'{digest}  {path.name}')
 print(f'{path.name}: {path.stat().st_size:,} bytes, SHA256 {digest}')
(dist/f'SHA256SUMS-{version}.txt').write_text('\n'.join(checksums)+'\n')
