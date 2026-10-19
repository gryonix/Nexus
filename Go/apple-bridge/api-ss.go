package main

// Shadowsocks 2022 entry points, copied into WireGuardKitGo at build time.

import "C"
import (
	"runtime/debug"
	"sync"

	"gryonix/ss2022"
)

// The extension's memory ceiling leaves room beside Go
const ssMemoryLimit = 30 << 20

var (
	ssLock   sync.Mutex
	ssClient *ss2022.Client
)

//export GryonixSSStart
func GryonixSSStart(listen, server, method, password, user, pass *C.char) *C.char {
	ssLock.Lock()
	defer ssLock.Unlock()
	if ssClient != nil {
		_ = ssClient.Close()
		ssClient = nil
	}
	debug.SetMemoryLimit(ssMemoryLimit)
	m, err := ss2022.NewMethod(C.GoString(method), C.GoString(password))
	if err != nil {
		return C.CString(err.Error())
	}
	login, err := ss2022.NewLogin(C.GoString(user), C.GoString(pass))
	if err != nil {
		return C.CString(err.Error())
	}
	client, err := ss2022.ListenWithLogin(C.GoString(listen), C.GoString(server), m, login)
	if err != nil {
		return C.CString(err.Error())
	}
	ssClient = client
	return C.CString("")
}

//export GryonixSSStop
func GryonixSSStop() *C.char {
	ssLock.Lock()
	defer ssLock.Unlock()
	if ssClient != nil {
		_ = ssClient.Close()
		ssClient = nil
	}
	return C.CString("")
}
