package ss2022

import (
	"net"
	"sync"
	"time"
)

// Client is a local SOCKS5 server that relays through one Shadowsocks server.
type Client struct {
	method   *Method
	login    *Login
	server   string
	listener net.Listener
	dialer   net.Dialer

	lock  sync.Mutex
	conns map[net.Conn]struct{}
	wait  sync.WaitGroup
}

// Listen starts serving SOCKS5 on listen, relaying to server.
func Listen(listen, server string, method *Method) (*Client, error) {
	return ListenWithLogin(listen, server, method, nil)
}

// ListenWithLogin is Listen, and a client must present login when it is set.
func ListenWithLogin(listen, server string, method *Method, login *Login) (*Client, error) {
	listener, err := net.Listen("tcp", listen)
	if err != nil {
		return nil, err
	}
	c := &Client{
		method:   method,
		login:    login,
		server:   server,
		listener: listener,
		dialer:   net.Dialer{Timeout: 10 * time.Second, KeepAlive: 30 * time.Second},
		conns:    map[net.Conn]struct{}{},
	}
	c.wait.Add(1)
	go c.accept()
	return c, nil
}

// Addr is where the SOCKS5 server listens.
func (c *Client) Addr() net.Addr { return c.listener.Addr() }

func (c *Client) dial(network string) (net.Conn, error) {
	return c.dialer.Dial(network, c.server)
}

func (c *Client) accept() {
	defer c.wait.Done()
	for {
		conn, err := c.listener.Accept()
		if err != nil {
			return
		}
		if !c.track(conn) {
			conn.Close()
			return
		}
		c.wait.Add(1)
		go func() {
			defer c.wait.Done()
			defer c.untrack(conn)
			c.serveConn(conn)
		}()
	}
}

func (c *Client) track(conn net.Conn) bool {
	c.lock.Lock()
	defer c.lock.Unlock()
	if c.conns == nil {
		return false
	}
	c.conns[conn] = struct{}{}
	return true
}

func (c *Client) untrack(conn net.Conn) {
	c.lock.Lock()
	delete(c.conns, conn)
	c.lock.Unlock()
}

// Close stops listening and drops every open connection.
func (c *Client) Close() error {
	err := c.listener.Close()
	c.lock.Lock()
	for conn := range c.conns {
		conn.Close()
	}
	c.conns = nil
	c.lock.Unlock()
	c.wait.Wait()
	return err
}
