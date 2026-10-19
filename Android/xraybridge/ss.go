package xraybridge

import (
	"sync"

	"gryonix/ss2022"
)

var (
	ssLock   sync.Mutex
	ssClient *ss2022.Client
)

// SsStart serves SOCKS5 on listen, relaying via a Shadowsocks 2022 server.
func SsStart(listen, server, method, password, user, pass string) error {
	ssLock.Lock()
	defer ssLock.Unlock()
	stopLocked()
	m, err := ss2022.NewMethod(method, password)
	if err != nil {
		return err
	}
	login, err := ss2022.NewLogin(user, pass)
	if err != nil {
		return err
	}
	client, err := ss2022.ListenWithLogin(listen, server, m, login)
	if err != nil {
		return err
	}
	ssClient = client
	return nil
}

// SsStop closes the Shadowsocks client; safe when stopped.
func SsStop() {
	ssLock.Lock()
	defer ssLock.Unlock()
	stopLocked()
}

func stopLocked() {
	if ssClient != nil {
		_ = ssClient.Close()
		ssClient = nil
	}
}
