#!/usr/bin/env python3
"""Manual connection-only check. No audio capture or sample generation."""
import json,subprocess,time,urllib.request,urllib.error,argparse
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device',required=True,help='Exact AirPlay device name')
args=parser.parse_args()
root=Path(__file__).resolve().parent.parent
data=Path.home()/'Library/Application Support/MacHomePod'
command=[str(root/'backend/runtime/usr/sbin/owntone'),'-f','-c',str(data/'owntone.conf'),'-s',str(root/'backend/runtime/usr/lib/owntone-sqlext.so'),'-P',str(data/'owntone.pid')]
log=open(root/'logs/connection-check.log','a')
p=subprocess.Popen(command,stdout=log,stderr=log)
selected=[]
def request(path,body=None):
 req=urllib.request.Request('http://127.0.0.1:3689'+path,data=None if body is None else json.dumps(body).encode(),headers={'Content-Type':'application/json'},method='GET' if body is None else 'PUT')
 try:
  with urllib.request.urlopen(req,timeout=8) as response:
   data=response.read();print('HTTP',response.status,path)
   return json.loads(data) if data else None
 except urllib.error.HTTPError as e:
  print('HTTP ERROR',e.code,e.read().decode());raise
try:
 for i in range(60):
  if p.poll() is not None:raise RuntimeError(f'backend exited {p.returncode}')
  try:
   devices=request('/api/outputs')['outputs']
   if any(x['name']==args.device for x in devices):break
  except urllib.error.URLError:pass
  time.sleep(.25)
 else:raise RuntimeError('HomePod not discovered')
 for device in devices:
  if device['name']==args.device:
   selected.append(device['id'])
   request('/api/outputs/'+device['id'],{'selected':True})
 print(json.dumps(request('/api/outputs'),ensure_ascii=False))
finally:
 for id in selected:
  try:request('/api/outputs/'+id,{'selected':False})
  except Exception as e:print('teardown',e)
 p.terminate()
 try:p.wait(timeout=2)
 except subprocess.TimeoutExpired:p.kill();p.wait()
 log.close()
