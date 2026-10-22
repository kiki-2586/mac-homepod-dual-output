import http.server,json,sys,time
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args): pass
 def do_GET(self):
  if self.path=='/bad/api/outputs':
   self.send_response(500); self.end_headers(); return
  if self.path=='/invalid/api/outputs':
   data=b'{"wrong":[]}'
  elif self.path=='/last': data=json.dumps(getattr(self.server,'last',{})).encode()
  else: data=json.dumps({'outputs':[{'id':'speaker-1','name':'HomePod','type':'AirPlay 2','selected':False,'volume':45},{'id':'local','name':'Local','type':'ALSA','selected':False,'volume':100}]}).encode()
  self.send_response(200);self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
 def do_PUT(self):
  body=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
  self.server.last={'path':self.path,'body':body}
  self.send_response(204);self.end_headers()
s=http.server.HTTPServer(('127.0.0.1',0),Handler)
print(s.server_port,flush=True)
s.serve_forever()
