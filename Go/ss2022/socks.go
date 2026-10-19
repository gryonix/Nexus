package ss2022

import (
	"bufio"
	"bytes"
	"crypto/subtle"
	"errors"
	"io"
	"net"
	"time"
)

const (
	socksVersion   = 5
	cmdConnect     = 1
	cmdAssociate   = 3
	firstDataWait  = 50 * time.Millisecond
	replySucceeded = 0
	replyFailed    = 1
	replyCommand   = 7

	methodNoAuth   = 0
	methodPassword = 2
	methodNone     = 0xFF
	loginVersion   = 1
)

// Login is the username and password a SOCKS5 client must present.
type Login struct{ Username, Password string }

// NewLogin refuses an empty login, which would leave the proxy open.
func NewLogin(username, password string) (*Login, error) {
	if username == "" || password == "" {
		return nil, errors.New("the local proxy needs a username and password")
	}
	return &Login{Username: username, Password: password}, nil
}

func (l Login) matches(user, pass []byte) bool {
	userOK := subtle.ConstantTimeCompare([]byte(l.Username), user)
	passOK := subtle.ConstantTimeCompare([]byte(l.Password), pass)
	return userOK&passOK == 1
}

// authenticate picks the method the client must use and checks its login.
func authenticate(r *bufio.Reader, w io.Writer, offered []byte, login *Login) error {
	want := byte(methodNoAuth)
	if login != nil {
		want = methodPassword
	}
	if !bytes.Contains(offered, []byte{want}) {
		_, _ = w.Write([]byte{socksVersion, methodNone})
		return errors.New("no acceptable SOCKS5 method")
	}
	if _, err := w.Write([]byte{socksVersion, want}); err != nil {
		return err
	}
	if login == nil {
		return nil
	}
	user, pass, err := readLogin(r)
	if err != nil {
		return err
	}
	if !login.matches(user, pass) {
		_, _ = w.Write([]byte{loginVersion, 1})
		return errors.New("wrong SOCKS5 login")
	}
	_, err = w.Write([]byte{loginVersion, 0})
	return err
}

// readLogin reads an RFC 1929 username and password.
func readLogin(r *bufio.Reader) (user, pass []byte, err error) {
	head := make([]byte, 2)
	if _, err = io.ReadFull(r, head); err != nil {
		return nil, nil, err
	}
	if head[0] != loginVersion {
		return nil, nil, errors.New("not a SOCKS5 login")
	}
	user = make([]byte, head[1])
	if _, err = io.ReadFull(r, user); err != nil {
		return nil, nil, err
	}
	size, err := r.ReadByte()
	if err != nil {
		return nil, nil, err
	}
	pass = make([]byte, size)
	_, err = io.ReadFull(r, pass)
	return user, pass, err
}

// handshake reads the greeting and request, returning command and target.
func handshake(r *bufio.Reader, w io.Writer, login *Login) (byte, Addr, error) {
	greeting := make([]byte, 2)
	if _, err := io.ReadFull(r, greeting); err != nil {
		return 0, nil, err
	}
	if greeting[0] != socksVersion {
		return 0, nil, errors.New("not SOCKS5")
	}
	offered := make([]byte, greeting[1])
	if _, err := io.ReadFull(r, offered); err != nil {
		return 0, nil, err
	}
	if err := authenticate(r, w, offered, login); err != nil {
		return 0, nil, err
	}
	request := make([]byte, 3)
	if _, err := io.ReadFull(r, request); err != nil {
		return 0, nil, err
	}
	target, err := readAddr(r)
	return request[1], target, err
}

func reply(w io.Writer, code byte, bound Addr) error {
	if bound == nil {
		bound = Addr{atypIPv4, 0, 0, 0, 0, 0, 0}
	}
	_, err := w.Write(append([]byte{socksVersion, code, 0}, bound...))
	return err
}

// serveConn handles one SOCKS5 client until it closes.
func (c *Client) serveConn(local net.Conn) {
	defer local.Close()
	reader := bufio.NewReader(local)
	command, target, err := handshake(reader, local, c.login)
	if err != nil {
		return
	}
	switch command {
	case cmdConnect:
		c.relayStream(local, reader, target)
	case cmdAssociate:
		c.relayPackets(local)
	default:
		_ = reply(local, replyCommand, nil)
	}
}

// relayStream proxies one CONNECT through the server.
func (c *Client) relayStream(local net.Conn, reader *bufio.Reader, target Addr) {
	server, err := c.dial("tcp")
	if err != nil {
		_ = reply(local, replyFailed, nil)
		return
	}
	if !c.track(server) {
		server.Close()
		return
	}
	defer c.untrack(server)
	remote := NewConn(server, c.method, target)
	defer remote.Close()
	if reply(local, replySucceeded, nil) != nil {
		return
	}
	if sendFirstData(local, reader, remote) != nil {
		return
	}
	done := make(chan struct{})
	go func() {
		_ = copyPooled(local, remote)
		if tcp, ok := local.(*net.TCPConn); ok {
			_ = tcp.CloseWrite()
		}
		close(done)
	}()
	_ = copyPooled(remote, reader)
	_ = remote.CloseWrite()
	<-done
}

// sendFirstData sends the header with the first bytes, or padding alone.
func sendFirstData(local net.Conn, reader *bufio.Reader, remote *Conn) error {
	_ = local.SetReadDeadline(time.Now().Add(firstDataWait))
	_, peekErr := reader.Peek(1)
	_ = local.SetReadDeadline(time.Time{})
	if peekErr != nil {
		var timeout net.Error
		if !errors.As(peekErr, &timeout) || !timeout.Timeout() {
			return peekErr
		}
		return remote.SendHeader()
	}
	first := make([]byte, reader.Buffered())
	_, _ = reader.Read(first)
	_, err := remote.Write(first)
	return err
}
