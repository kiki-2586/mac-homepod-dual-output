#include <stdio.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <string.h>
#include <unistd.h>
#include "airptp.h"
static atomic_int registered;
static void logmsg(const char *fmt,...) {
  char text[1024]; va_list ap;va_start(ap,fmt);vsnprintf(text,sizeof text,fmt,ap);va_end(ap);
  if(strstr(text,"Added peer id"))atomic_store(&registered,1);
}
int main(int argc,char **argv) {
  struct airptp_callbacks cb={.logmsg=logmsg};
  airptp_callbacks_register(&cb);airptp_ports_override(30319,30320);
  struct airptp_handle *h=airptp_daemon_bind(argc>1?argv[1]:NULL);
  if(!h||airptp_daemon_start(h,123,false)<0){fprintf(stderr,"startup: %s\n",airptp_errmsg_get());return 2;}
  uint32_t peer;
  int r=airptp_peer_add(&peer,"127.0.0.1",h);
  for(int i=0;i<100&&!atomic_load(&registered);i++)usleep(10000);
  int success=r==0&&atomic_load(&registered);
  airptp_end(h);
  if(!success){fputs("FAIL: peer-add returned success but clock daemon never registered peer\n",stderr);return 1;}
  puts("PASS: clock daemon received local peer registration");return 0;
}
