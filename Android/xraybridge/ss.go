package xraybridge

import (
	"sync"

	"gryonix/ss2022"
)

var (
	ssLock    sync.Mutex
	ssClients = map[string]*ss2022.Client{}
)

// SsStart serves SOCKS5 on listen, relaying via a Shadowsocks 2022 server.
// A client already on listen is replaced; others keep running.
func SsStart(listen, server, method, password, user, pass string) error {
	ssLock.Lock()
	defer ssLock.Unlock()
	if old := ssClients[listen]; old != nil {
		_ = old.Close()
		delete(ssClients, listen)
	}
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
	ssClients[listen] = client
	return nil
}

// SsStop closes every Shadowsocks client; safe when stopped.
func SsStop() {
	ssLock.Lock()
	defer ssLock.Unlock()
	for listen, client := range ssClients {
		_ = client.Close()
		delete(ssClients, listen)
	}
}
