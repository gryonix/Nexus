package ss2022

import (
	"bytes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/binary"
	"errors"
	"io"
	"math/big"
	"net"
	"sync"
	"time"
)

// Conn is one proxied TCP stream over a Shadowsocks 2022 connection.
// Larger sealed writes are not kept between calls.
const maxKeptWriteBuffer = 128 * 1024

type Conn struct {
	net.Conn
	method *Method
	target Addr

	writeLock   sync.Mutex
	sealer      cipher.AEAD
	sealNonce   nonce
	requestSalt []byte

	writeBuf []byte

	opener    cipher.AEAD
	openNonce nonce
	pending   []byte
	readBuf   []byte
}

// NewConn wraps a connection to the server for one target.
func NewConn(server net.Conn, method *Method, target Addr) *Conn {
	return &Conn{Conn: server, method: method, target: target}
}

// Write sends p, preceded by the request header on first use.
func (c *Conn) Write(p []byte) (int, error) {
	c.writeLock.Lock()
	defer c.writeLock.Unlock()
	out := c.writeBuf[:0]
	sent := 0
	if c.sealer == nil {
		header, used, err := c.requestHeader(p)
		if err != nil {
			return 0, err
		}
		out, sent = header, used
	}
	out = c.appendChunks(out, p[sent:])
	if cap(out) <= maxKeptWriteBuffer {
		c.writeBuf = out
	}
	if _, err := c.Conn.Write(out); err != nil {
		return 0, err
	}
	return len(p), nil
}

// SendHeader sends the request header with padding and no payload.
func (c *Conn) SendHeader() error {
	if c.sealer != nil {
		return nil
	}
	_, err := c.Write(nil)
	return err
}

// requestHeader builds salt and both header chunks with initial payload.
func (c *Conn) requestHeader(p []byte) ([]byte, int, error) {
	salt := make([]byte, c.method.saltSize())
	if _, err := rand.Read(salt); err != nil {
		return nil, 0, err
	}
	sealer, err := c.method.sessionAEAD(salt)
	if err != nil {
		return nil, 0, err
	}
	c.sealer, c.requestSalt = sealer, salt

	padding := 0
	if len(p) == 0 {
		padding = randomPadding()
	}
	room := maxPayload - len(c.target) - 2 - padding
	initial := p[:min(len(p), room)]

	variable := make([]byte, 0, len(c.target)+2+padding+len(initial))
	variable = append(variable, c.target...)
	variable = binary.BigEndian.AppendUint16(variable, uint16(padding))
	variable = append(variable, make([]byte, padding)...)
	variable = append(variable, initial...)

	fixed := []byte{typeClient}
	fixed = binary.BigEndian.AppendUint64(fixed, uint64(time.Now().Unix()))
	fixed = binary.BigEndian.AppendUint16(fixed, uint16(len(variable)))

	identities, err := c.method.identityHeaders(salt)
	if err != nil {
		return nil, 0, err
	}
	out := append(append([]byte{}, salt...), identities...)
	out = c.sealer.Seal(out, c.sealNonce.next(), fixed, nil)
	out = c.sealer.Seal(out, c.sealNonce.next(), variable, nil)
	return out, len(initial), nil
}

// appendChunks seals p as length and payload chunks.
func (c *Conn) appendChunks(out, p []byte) []byte {
	for len(p) > 0 {
		n := min(len(p), maxPayload)
		length := binary.BigEndian.AppendUint16(nil, uint16(n))
		out = c.sealer.Seal(out, c.sealNonce.next(), length, nil)
		out = c.sealer.Seal(out, c.sealNonce.next(), p[:n], nil)
		p = p[n:]
	}
	return out
}

// Read returns decrypted response payload.
func (c *Conn) Read(p []byte) (int, error) {
	for len(c.pending) == 0 {
		if err := c.readChunk(); err != nil {
			return 0, err
		}
	}
	n := copy(p, c.pending)
	c.pending = c.pending[n:]
	return n, nil
}

// readChunk reads the response header or one length+payload pair.
func (c *Conn) readChunk() error {
	var length int
	var err error
	if c.opener == nil {
		length, err = c.readResponseHeader()
	} else {
		length, err = c.readLength()
	}
	if err != nil {
		return err
	}
	return c.readPayload(length)
}

func (c *Conn) readResponseHeader() (int, error) {
	saltSize := c.method.saltSize()
	fixedSize := 1 + 8 + saltSize + 2
	buf := make([]byte, saltSize+fixedSize+tagSize)
	if _, err := io.ReadFull(c.Conn, buf); err != nil {
		return 0, err
	}
	opener, err := c.method.sessionAEAD(buf[:saltSize])
	if err != nil {
		return 0, err
	}
	c.opener = opener
	fixed, err := c.opener.Open(nil, c.openNonce.next(), buf[saltSize:], nil)
	if err != nil {
		return 0, errors.New("response header failed authentication")
	}
	if fixed[0] != typeServer {
		return 0, errors.New("response header has the wrong type")
	}
	if err := checkTimestamp(binary.BigEndian.Uint64(fixed[1:9]), time.Now()); err != nil {
		return 0, err
	}
	c.writeLock.Lock()
	salt := c.requestSalt
	c.writeLock.Unlock()
	if !bytes.Equal(fixed[9:9+saltSize], salt) {
		return 0, errors.New("response is for another request")
	}
	return int(binary.BigEndian.Uint16(fixed[9+saltSize:])), nil
}

func (c *Conn) readLength() (int, error) {
	buf := make([]byte, 2+tagSize)
	if _, err := io.ReadFull(c.Conn, buf); err != nil {
		return 0, err
	}
	length, err := c.opener.Open(buf[:0], c.openNonce.next(), buf, nil)
	if err != nil {
		return 0, errors.New("length chunk failed authentication")
	}
	return int(binary.BigEndian.Uint16(length)), nil
}

func (c *Conn) readPayload(length int) error {
	if cap(c.readBuf) < length+tagSize {
		c.readBuf = make([]byte, length+tagSize)
	}
	buf := c.readBuf[:length+tagSize]
	if _, err := io.ReadFull(c.Conn, buf); err != nil {
		return err
	}
	payload, err := c.opener.Open(buf[:0], c.openNonce.next(), buf, nil)
	if err != nil {
		return errors.New("payload chunk failed authentication")
	}
	c.pending = payload
	return nil
}

// CloseWrite half-closes the server connection.
func (c *Conn) CloseWrite() error {
	if tcp, ok := c.Conn.(*net.TCPConn); ok {
		return tcp.CloseWrite()
	}
	return nil
}

func randomPadding() int {
	n, err := rand.Int(rand.Reader, big.NewInt(maxPadding))
	if err != nil {
		return maxPadding
	}
	return int(n.Int64()) + 1
}
