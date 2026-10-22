#!/usr/bin/env python3
"""Copy the linked dependency closure and make the backend independent of build prefixes."""
from pathlib import Path
import subprocess, shutil, json
root=Path(__file__).resolve().parent.parent
source=root/'backend/usr/sbin/owntone'
destination=root/'backend/runtime/usr'
(destination/'sbin').mkdir(parents=True,exist_ok=True)
(destination/'lib').mkdir(parents=True,exist_ok=True)
pending=[(source,destination/'sbin/owntone'), (root/'backend/usr/lib/owntone/owntone-sqlext.so',destination/'lib/owntone-sqlext.so')]
seen={}
manifest=[]
while pending:
 src,dst=pending.pop(0)
 if str(dst) in seen:
  if seen[str(dst)]!=src.resolve(): raise RuntimeError(f'dependency filename collision: {src}')
  continue
 seen[str(dst)]=src.resolve()
 shutil.copy2(src,dst);dst.chmod(0o755)
 dependencies=[]
 lines=subprocess.check_output(['otool','-L',str(src)],text=True).splitlines()[1:]
 for line in lines:
  dep=line.strip().split(' (compatibility')[0]
  if dep.startswith(('/System/','/usr/lib/')):continue
  # Own install ID can appear as the first -L entry for a dylib.
  if dep.startswith('@'):raise RuntimeError(f'unresolved runtime dependency {dep} from {src}')
  candidate=Path(dep)
  if candidate.resolve()==src.resolve():continue
  if not candidate.is_file():raise RuntimeError(f'missing dependency {dep}')
  target=destination/'lib'/candidate.name
  pending.append((candidate,target))
  replacement=('@executable_path/../lib/' if dst.parent.name=='sbin' else '@loader_path/')+candidate.name
  subprocess.run(['install_name_tool','-change',dep,replacement,str(dst)],check=True,capture_output=True)
  dependencies.append(candidate.name)
 if dst.suffix=='.dylib':
  subprocess.run(['install_name_tool','-id','@loader_path/'+dst.name,str(dst)],check=True,capture_output=True)
 subprocess.run(['codesign','--force','--sign','-','--timestamp=none',str(dst)],check=True,capture_output=True)
 manifest.append({'file':str(dst.relative_to(destination)),'source':str(src),'dependencies':dependencies})
(root/'backend/runtime/manifest.json').write_text(json.dumps(manifest,indent=2))
print(f'Bundled {len(manifest)} runtime binaries')
