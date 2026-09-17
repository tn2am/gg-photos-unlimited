package main

/*
#include <stdlib.h>
#include <stdint.h>
static inline char *gunshot_host_bearer(uintptr_t provider, const char *account) {
 return ((char *(*)(const char *))provider)(account);
}
*/
import "C"
import (
	"app/backend"
	"context"
	"errors"
	"github.com/tqmane/gunshot/internal/service"
	"io"
	"log"
	"log/slog"
	"sync"
	"unsafe"
)

var engine *service.Engine
var initMu sync.Mutex
var hostBearerProvider bool

//export GunshotSetHostBearerProvider
func GunshotSetHostBearerProvider(provider C.uintptr_t) {
	initMu.Lock()
	defer initMu.Unlock()
	hostBearerProvider = provider != 0
	if provider == 0 {
		backend.GunshotSetNativeBearerProvider(nil)
		return
	}
	backend.GunshotSetNativeBearerProvider(func(identifier string) (string, error) {
		account := C.CString(identifier)
		defer C.free(unsafe.Pointer(account))
		token := C.gunshot_host_bearer(provider, account)
		if token == nil {
			return "", errors.New("host authorization unavailable")
		}
		defer C.free(unsafe.Pointer(token))
		return C.GoString(token), nil
	})
}

//export GunshotPing
func GunshotPing() C.int { return 1 }

//export GunshotInitialize
func GunshotInitialize(path *C.char) C.int {
	initMu.Lock()
	defer initMu.Unlock()
	if engine != nil {
		return 0
	}
	log.SetOutput(io.Discard)
	slog.SetDefault(slog.New(slog.DiscardHandler))
	e, err := service.Initialize(C.GoString(path))
	if err != nil {
		return -1
	}
	engine = e
	if !hostBearerProvider { e.EnableNativeRelay() }
	go e.Run(context.Background())
	return 0
}

//export GunshotRequest
func GunshotRequest(request *C.char, role *C.char) (out *C.char) {
	defer func() {
		if recover() != nil {
			out = C.CString(`{"ok":false,"error":"internal_error"}`)
		}
	}()
	if engine == nil {
		return C.CString(`{"ok":false,"error":"not_initialized"}`)
	}
	return C.CString(string(engine.HandleJSON([]byte(C.GoString(request)), C.GoString(role))))
}

//export GunshotFree
func GunshotFree(p unsafe.Pointer) { C.free(p) }
func main()                        {}
