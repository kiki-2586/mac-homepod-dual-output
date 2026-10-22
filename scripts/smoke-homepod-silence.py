#!/usr/bin/env python3
"""Manual transport test: stream generated DIGITAL SILENCE, never system audio."""
import json,subprocess,time,urllib.request,urllib.error,os,errno,argparse,math,struct
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device',required=True,help='Exact AirPlay device name')
parser.add_argument('--tone',action='store_true',help='Play an audible generated test beat instead of silence')
parser.add_argument('--seconds',type=float,default=10)
parser.add_argument('--debug',action='store_true')
args=parser.parse_args()
root=Path(__file__).resolve().parent.parent
data=Path.home()/'Library/Application Support/MacHomePod'
command=[str(root/'backend/runtime/usr/sbin/owntone'),'-f','-c',str(data/'owntone.conf'),'-s',str(root/'backend/runtime/usr/lib/owntone-sqlext.so'),'-P',str(data/'owntone.pid')]
if args.debug:command+=['-d','4']
logpath=data/'backend.log'
logstart=logpath.stat().st_size if logpath.exists() else 0
log=open(root/'logs/silence-smoke.log','a')
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
 fd=os.open(data/'media/system.pipe',os.O_WRONLY|os.O_NONBLOCK)
 try:
  sent=0;started=time.monotonic();chunk=bytes(1920)
  while time.monotonic()-started<args.seconds:
   if args.tone:
    frame=sent//4
    chunk=b''.join(struct.pack('<hh',*(2*[int(32767*.12*math.sin(2*math.pi*660*(frame+i)/48000)*max(0,1-((frame+i)%48000)/5760))])) for i in range(480))
   try:
    n=os.write(fd,chunk);sent+=n
   except BlockingIOError:time.sleep(.002);continue
   target=started+sent/192000
   if target>time.monotonic():time.sleep(target-time.monotonic())
  print('Generated test beat bytes sent:' if args.tone else 'Generated digital silence bytes sent:',sent)
  outputs=request('/api/outputs')
  print(json.dumps(outputs,ensure_ascii=False))
  assert all(any(d['id']==id and d['selected'] for d in outputs['outputs']) for id in selected), 'HomePod dropped its actual stream'
  print(json.dumps(request('/api/player'),ensure_ascii=False))
 finally:os.close(fd)
finally:
 for id in selected:
  try:request('/api/outputs/'+id,{'selected':False})
  except Exception as e:print('teardown',e)
 p.terminate()
 try:p.wait(timeout=2)
 except subprocess.TimeoutExpired:p.kill();p.wait()
 log.close()

segment=logpath.read_bytes()[logstart:].decode(errors='replace')
for failure in ['Could not send playback sync', 'failed to activate', 'Response to SETUP (session)']:
 assert failure not in segment, 'Transport log failure: '+failure
if args.debug:assert 'Added peer id' in segment,'Clock daemon did not register HomePod'
print('PASS: HomePod transport stayed active without timing-send failures; audible result requires listener confirmation')
