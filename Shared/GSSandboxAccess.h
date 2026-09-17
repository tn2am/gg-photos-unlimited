#pragma once

#define GS_IPC_SANDBOX_PROFILE "dev.tqmane.gunshot.ipc"
enum {
 GS_SANDBOX_LIBRARY_MISSING = -1,
 GS_SANDBOX_API_MISSING = -2,
};
// Other return values are libSandy status codes (0 success, 1 unavailable,
// 2 restricted). Success still requires a subsequent daemon lookup.
int GSApplyIPCSandboxProfile(void);
// -1 means the provider does not expose the introspection symbol; 0/1 are
// false/true. This is read-only metadata, never a request to change its policy.
typedef struct { int active,uploadRedirected,discoveryRedirected; } GSSandboxAdapterState;
GSSandboxAdapterState GSGetSandboxAdapterState(void);
