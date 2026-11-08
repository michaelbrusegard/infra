// Package plugin implements CLIProxyAPI's plugin C ABI for the plugins here.
//
// CLIProxyAPI loads each plugin with dlopen and talks to it through a C ABI:
// each call is a method name plus a JSON request, answered with a JSON
// envelope. A plugin's main package calls Serve from init.
package plugin

/*
#include <stdint.h>
#include <stdlib.h>

typedef struct {
	void* ptr;
	size_t len;
} cliproxy_buffer;

typedef int (*cliproxy_plugin_call_fn)(char*, uint8_t*, size_t, cliproxy_buffer*);
typedef void (*cliproxy_plugin_free_fn)(void*, size_t);
typedef void (*cliproxy_plugin_shutdown_fn)(void);

typedef struct {
	uint32_t abi_version;
	void* host_ctx;
	void* call;
	void* free_buffer;
} cliproxy_host_api;

typedef struct {
	uint32_t abi_version;
	cliproxy_plugin_call_fn call;
	cliproxy_plugin_free_fn free_buffer;
	cliproxy_plugin_shutdown_fn shutdown;
} cliproxy_plugin_api;

extern int cliproxyPluginCall(char*, uint8_t*, size_t, cliproxy_buffer*);
extern void cliproxyPluginFree(void*, size_t);
extern void cliproxyPluginShutdown(void);
*/
import "C"

import (
	"encoding/json"
	"unsafe"
)

// Handler answers the host's method calls.
type Handler interface {
	Handle(method string, request []byte) (response []byte, ok bool)
	Shutdown()
}

var handler Handler

// Serve sets the handler for every call from the host.
func Serve(h Handler) {
	handler = h
}

// Registration describes a plugin to the host.
func Registration(name string, capabilities map[string]bool) map[string]any {
	return map[string]any{
		// 7 lets the archive's after-auth interceptor skip the translated
		// upstream body; 5 and 3 drop history and request bodies from stream
		// chunks.
		"schema_version": 7,
		"metadata": map[string]any{
			"Name":             name,
			"Version":          "0.1.0",
			"Author":           "michaelbrusegard",
			"GitHubRepository": "https://github.com/michaelbrusegard/infra",
			"ConfigFields":     []any{},
		},
		"capabilities": capabilities,
	}
}

type envelope struct {
	OK     bool    `json:"ok"`
	Result any     `json:"result,omitempty"`
	Error  *rpcErr `json:"error,omitempty"`
}

type rpcErr struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// Reply answers a call successfully.
func Reply(result any) ([]byte, bool) {
	out, err := json.Marshal(envelope{OK: true, Result: result})
	if err != nil {
		return Fail("encode_failed", err)
	}
	return out, true
}

// Fail answers a call with an error.
func Fail(code string, err error) ([]byte, bool) {
	out, _ := json.Marshal(envelope{Error: &rpcErr{Code: code, Message: err.Error()}})
	return out, false
}

//export cliproxy_plugin_init
func cliproxy_plugin_init(_ *C.cliproxy_host_api, api *C.cliproxy_plugin_api) C.int {
	if api == nil {
		return 1
	}
	api.abi_version = 1
	api.call = C.cliproxy_plugin_call_fn(C.cliproxyPluginCall)
	api.free_buffer = C.cliproxy_plugin_free_fn(C.cliproxyPluginFree)
	api.shutdown = C.cliproxy_plugin_shutdown_fn(C.cliproxyPluginShutdown)
	return 0
}

//export cliproxyPluginCall
func cliproxyPluginCall(method *C.char, request *C.uint8_t, requestLen C.size_t, response *C.cliproxy_buffer) C.int {
	if response != nil {
		response.ptr = nil
		response.len = 0
	}
	var raw []byte
	if request != nil && requestLen > 0 {
		raw = C.GoBytes(unsafe.Pointer(request), C.int(requestLen))
	}
	out, ok := handler.Handle(C.GoString(method), raw)
	if len(out) > 0 && response != nil {
		response.ptr = C.CBytes(out)
		response.len = C.size_t(len(out))
	}
	if !ok {
		return 1
	}
	return 0
}

//export cliproxyPluginFree
func cliproxyPluginFree(ptr unsafe.Pointer, _ C.size_t) {
	if ptr != nil {
		C.free(ptr)
	}
}

//export cliproxyPluginShutdown
func cliproxyPluginShutdown() {
	handler.Shutdown()
}
