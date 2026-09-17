#pragma once
#include <mach/mach.h>
#include <stdbool.h>
#include <stdint.h>
#define GS_DISCOVERY_SERVICE "dev.tqmane.gunshot.discovery"
#ifdef __cplusplus
extern "C" {
#endif
kern_return_t GSDiscoverDaemon(mach_port_t *port,uint32_t timeoutMS,const char **stage);
bool GSStartDiscoveryService(mach_port_t port,bool (*authorize)(audit_token_t));
#ifdef __cplusplus
}
#endif
