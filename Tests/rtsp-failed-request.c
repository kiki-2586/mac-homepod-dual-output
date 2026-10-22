#include <assert.h>
#include <stdio.h>
#include <sys/resource.h>
#include <event2/event.h>
#include "evrtsp.h"
int main(void) {
 struct event_base*base=event_base_new();assert(base);
 struct evrtsp_connection*connection=evrtsp_connection_new("127.0.0.1",7000);assert(connection);
 evrtsp_connection_set_base(connection,base);
 struct evrtsp_request*request=evrtsp_request_new(NULL,NULL);assert(request);
 struct rlimit original,limited;assert(getrlimit(RLIMIT_NOFILE,&original)==0);
 limited=original;limited.rlim_cur=0;assert(setrlimit(RLIMIT_NOFILE,&limited)==0);
 int result=evrtsp_make_request(connection,request,EVRTSP_REQ_GET,"/info");
 assert(setrlimit(RLIMIT_NOFILE,&original)==0);assert(result<0);
 // The caller retains a failed request; freeing the connection must not touch it again.
 evrtsp_request_free(request);
 evrtsp_connection_free(connection);
 event_base_free(base);
 puts("PASS: synchronous RTSP connect failure returns request ownership without double-free");
 return 0;
}
