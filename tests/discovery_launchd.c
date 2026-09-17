#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "../Shared/GSDiscovery.h"
#include <dispatch/dispatch.h>

static bool Authorize(audit_token_t token){return token.val[1]==getuid()&&token.val[5]>0;}
int main(int argc,char **argv){
 if(argc==2&&!strcmp(argv[1],"--serve")){
  mach_port_t port=MACH_PORT_NULL;
  assert(mach_port_allocate(mach_task_self(),MACH_PORT_RIGHT_RECEIVE,&port)==KERN_SUCCESS);
  assert(GSStartDiscoveryService(port,Authorize));dispatch_main();
 }
 alarm(15);
 mach_port_t port=MACH_PORT_NULL;const char *stage=NULL;
 kern_return_t code=GSDiscoverDaemon(&port,5000,&stage);
 if(code!=KERN_SUCCESS){fprintf(stderr,"launchd discovery failed: %s (%d)\n",stage,code);return 1;}
 assert(MACH_PORT_VALID(port));mach_port_deallocate(mach_task_self(),port);
 puts("PASS named LaunchDaemon discovery through the production client and server");
 return 0;
}
