#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc,char**argv) {
 if(argc!=2)return 2;
 char path[4096];int failures=0;
 snprintf(path,sizeof path,"%s/owntone-sqlext.so",argv[1]);
 if(!dlopen(path,RTLD_NOW|RTLD_LOCAL)){fprintf(stderr,"FAIL: missing or unloadable SQLite runtime module: %s\n",dlerror());return 1;}
 snprintf(path,sizeof path,"%s/libavformat.61.dylib",argv[1]);void*format=dlopen(path,RTLD_NOW|RTLD_LOCAL);
 snprintf(path,sizeof path,"%s/libavcodec.61.dylib",argv[1]);void*codec=dlopen(path,RTLD_NOW|RTLD_LOCAL);
 snprintf(path,sizeof path,"%s/libavfilter.10.dylib",argv[1]);void*filter=dlopen(path,RTLD_NOW|RTLD_LOCAL);
 if(!format||!codec||!filter){fprintf(stderr,"library load failed: %s\n",dlerror());return 1;}
 void*(*guess)(const char*,const char*,const char*)=dlsym(format,"av_guess_format");
 void*(*encoder)(const char*)=dlsym(codec,"avcodec_find_encoder_by_name");
 void*(*getfilter)(const char*)=dlsym(filter,"avfilter_get_by_name");
 if(!guess||!encoder||!getfilter)return 1;
 const char*muxers[]={"data","s16le"};
 for(int i=0;i<2;i++)if(!guess(muxers[i],NULL,NULL)){fprintf(stderr,"FAIL: missing muxer %s\n",muxers[i]);failures++;}
 if(!encoder("alac")){fprintf(stderr,"FAIL: missing ALAC encoder\n");failures++;}
 const char*filters[]={"abuffer","abuffersink","aformat","aresample"};
 for(int i=0;i<4;i++)if(!getfilter(filters[i])){fprintf(stderr,"FAIL: missing filter %s\n",filters[i]);failures++;}
 if(!failures)puts("PASS: packaged backend has ALAC, raw-data muxer, PCM and required audio filters");
 return failures?1:0;
}
