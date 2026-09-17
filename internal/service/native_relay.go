package service

import (
	"app/backend"
	"errors"
	"strings"
	"sync"
	"time"
)

// SSO stays inside Google Photos. The daemon holds only one short-lived bearer
// in memory, never the host's refresh credential. This is a local retention cap,
// not an assertion about the token's expiry at Google.
const nativeBearerRetention = 5 * time.Minute

type nativeRelay struct {
	mu sync.Mutex
	id, token string
	until time.Time
	now func() time.Time
}

func (r *nativeRelay) clear() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.id, r.token, r.until = "", "", time.Time{}
}

func (r *nativeRelay) put(id, token string) error {
	if id == "" || len(id) > 256 || strings.ContainsAny(id, "\x00\r\n") || token == "" || len(token) > 32768 || strings.ContainsAny(token, "\x00 \r\n\t") {
		return errRequest
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	r.id, r.token, r.until = id, token, r.now().Add(nativeBearerRetention)
	return nil
}

func (r *nativeRelay) get(id string) (string, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if !r.now().Before(r.until) { r.id, r.token = "", "" }
	if id == "" || r.id != id || r.token == "" {
		return "", errors.New("open Google Photos to refresh authorization")
	}
	return r.token, nil
}

// Call before Run, only in the standalone daemon. Jailed uses its direct SSO
// provider. Both paths ultimately implement the same upstream bearer API.
func (e *Engine) EnableNativeRelay() {
	e.nativeRelay = &nativeRelay{now: time.Now}
	backend.GunshotSetNativeBearerProvider(e.nativeRelay.get)
}

func (e *Engine) nativeAuthorization(email string) string {
	if e.nativeRelay == nil { return "" }
	id := backend.GunshotNativeAccountID(email)
	if id == "" { return "" }
	if _, err := e.nativeRelay.get(id); err != nil { return "waiting" }
	return "ready"
}
