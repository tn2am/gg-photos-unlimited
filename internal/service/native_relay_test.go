package service

import (
	"app/backend"
	"context"
	"crypto/x509"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func relayEngine(t *testing.T, runner Runner) *Engine {
	t.Helper()
	e := newEngine(t, runner)
	if err := backend.LoadConfig(filepath.Join(e.root, "credentials.json")); err != nil { t.Fatal(err) }
	e.EnableNativeRelay()
	t.Cleanup(func() { e.Close(); backend.GunshotSetNativeBearerProvider(nil) })
	return e
}

func relayRequest(t *testing.T, e *Engine, role string, r Request, want bool) {
	t.Helper()
	wire, err := json.Marshal(r)
	if err != nil { t.Fatal(err) }
	reply := e.HandleJSON(wire, role)
	var result struct { OK bool `json:"ok"` }
	if json.Unmarshal(reply, &result) != nil || result.OK != want { t.Fatal("unexpected relay result") }
	if r.Secret != "" && strings.Contains(string(reply), r.Secret) { t.Fatal("secret in reply") }
}

func nativeValidationServer(t *testing.T) {
	t.Helper()
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer synthetic-native-bearer" { t.Error("native authorization header missing") }
		w.WriteHeader(http.StatusOK) // Empty protobuf: no match for the validation hash.
	}))
	t.Cleanup(server.Close)
	previous := http.DefaultTransport
	transport := previous.(*http.Transport).Clone()
	transport.Proxy = nil
	transport.TLSClientConfig = server.Client().Transport.(*http.Transport).TLSClientConfig.Clone()
	transport.TLSClientConfig.InsecureSkipVerify = false
	transport.TLSClientConfig.ServerName = "127.0.0.1"
	transport.TLSClientConfig.RootCAs = x509.NewCertPool()
	transport.TLSClientConfig.RootCAs.AddCert(server.Certificate())
	transport.DialContext = func(ctx context.Context, network, address string) (net.Conn, error) {
		if address != "photosdata-pa.googleapis.com:443" { return nil, errors.New("non-fixture endpoint refused") }
		return (&net.Dialer{}).DialContext(ctx, network, server.Listener.Addr().String())
	}
	http.DefaultTransport = transport
	t.Cleanup(func() { http.DefaultTransport = previous; transport.CloseIdleConnections() })
}

func TestNativeRelayConnectsThroughPhotosEndpointWithoutPersistingBearer(t *testing.T) {
	e := relayEngine(t, nil)
	nativeValidationServer(t)
	r := Request{Op: "account_native", Account: "a@example.com", NativeID: "id-a", Secret: "synthetic-native-bearer"}
	for _, role := range []string{"settings", "photos", "daemon", "untrusted"} { relayRequest(t, e, role, r, false) }
	relayRequest(t, e, "googlephotos", r, true)
	if backend.GunshotNativeAccountID(r.Account) != r.NativeID || e.nativeAuthorization(r.Account) != "ready" { t.Fatal("native binding unavailable") }
	for _, name := range []string{"credentials.json", "state.json"} {
		b, err := os.ReadFile(filepath.Join(e.root, name))
		if err != nil || strings.Contains(string(b), r.Secret) { t.Fatal("missing state or persisted bearer") }
	}
	r.Op = "native_bearer"
	r.NativeID = "id-other"
	relayRequest(t, e, "googlephotos", r, false)
	r.NativeID = "id-a"
	r.Secret = "bad\r\nheader"
	relayRequest(t, e, "googlephotos", r, false)
	r.Secret = "renewed-native-bearer"
	for _, role := range []string{"settings", "photos", "daemon", "untrusted"} { relayRequest(t, e, role, r, false) }
	relayRequest(t, e, "googlephotos", r, true)
	if token, err := e.nativeRelay.get("id-a"); err != nil || token != r.Secret { t.Fatal("renewal not used") }
	if _, err := e.nativeRelay.get("id-other"); err == nil { t.Fatal("wrong account received bearer") }
	r = Request{Op: "native_bearer_clear"}
	relayRequest(t, e, "photos", r, false)
	relayRequest(t, e, "googlephotos", r, true)
	if e.nativeAuthorization("a@example.com") != "waiting" { t.Fatal("sign-out did not clear authorization") }
}

func TestNativeRelayExpiryAndDaemonRestartWaitWithoutUsingRetries(t *testing.T) {
	e := relayEngine(t, func(context.Context, []string, string, string, func(Progress)) (string, error) { return "media-key", nil })
	nativeValidationServer(t)
	relayRequest(t, e, "googlephotos", Request{Op: "account_native", Account: "a@example.com", NativeID: "id-a", Secret: "synthetic-native-bearer"}, true)
	j := importTest(t, e, "original")
	e.online, e.wifi = true, true
	e.nativeRelay.mu.Lock(); e.nativeRelay.until = time.Now().Add(-time.Second); e.nativeRelay.mu.Unlock()
	e.Tick()
	if j.State != "pending" || j.Attempts != 0 { t.Fatal("expired bearer consumed retries") }
	// A new process retains only the binding and pending queue, not the bearer.
	next, err := Open(e.root, e.runner)
	if err != nil { t.Fatal(err) }
	defer next.Close()
	next.EnableNativeRelay()
	next.online, next.wifi = true, true
	next.Tick()
	if next.find(j.ID).State != "pending" || next.find(j.ID).Attempts != 0 { t.Fatal("restart attempted unauthed upload") }
	relayRequest(t, next, "googlephotos", Request{Op: "native_bearer", Account: "a@example.com", NativeID: "id-a", Secret: "renewed-native-bearer"}, true)
	next.Tick(); waitIdle(t, next)
	if next.find(j.ID).State != "completed" { t.Fatal("refresh did not resume pending work") }
}

func TestNativeRelayConcurrentRefreshAndExpiry(t *testing.T) {
	now := time.Now()
	r := &nativeRelay{now: func() time.Time { return now }}
	if r.put("id-a", "synthetic-token") != nil { t.Fatal("valid bearer rejected") }
	var wg sync.WaitGroup
	for range 8 {
		wg.Add(1)
		go func() { defer wg.Done(); for range 100 { r.put("id-a", "renewed-token"); r.get("id-a"); r.clear() } }()
	}
	wg.Wait()
	r.put("id-a", "synthetic-token")
	now = now.Add(nativeBearerRetention)
	if _, err := r.get("id-a"); err == nil || r.token != "" { t.Fatal("retention boundary did not discard token") }
}
