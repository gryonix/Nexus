package ss2022

import (
	"crypto/cipher"
	"crypto/rand"
	"encoding/binary"
	"errors"
	"net"
	"sync"
	"time"
)

const separateHeaderSize = 16

// PacketSession is one client UDP session to the server.
type PacketSession struct {
	method    *Method
	conn      net.Conn
	sessionID [8]byte
	sealer    cipher.AEAD

	lock     sync.Mutex
	packetID uint64
	servers  map[[8]byte]*serverSession
}

type serverSession struct {
	opener   cipher.AEAD
	window   replayWindow
	lastSeen time.Time
}

// NewPacketSession starts a session over a connected UDP socket.
func NewPacketSession(conn net.Conn, method *Method) (*PacketSession, error) {
	s := &PacketSession{method: method, conn: conn, servers: map[[8]byte]*serverSession{}}
	if _, err := rand.Read(s.sessionID[:]); err != nil {
		return nil, err
	}
	sealer, err := method.sessionAEAD(s.sessionID[:])
	if err != nil {
		return nil, err
	}
	s.sealer = sealer
	return s, nil
}

// Send encrypts one datagram for target and writes it.
func (s *PacketSession) Send(target Addr, payload []byte) error {
	packet, err := s.seal(target, payload)
	if err != nil {
		return err
	}
	_, err = s.conn.Write(packet)
	return err
}

func (s *PacketSession) seal(target Addr, payload []byte) ([]byte, error) {
	s.lock.Lock()
	id := s.packetID
	s.packetID++
	s.lock.Unlock()

	header := make([]byte, separateHeaderSize, separateHeaderSize+1+8+2+len(target)+len(payload)+tagSize)
	copy(header, s.sessionID[:])
	binary.BigEndian.PutUint64(header[8:], id)

	body := []byte{typeClient}
	body = binary.BigEndian.AppendUint64(body, uint64(time.Now().Unix()))
	body = binary.BigEndian.AppendUint16(body, 0)
	body = append(body, target...)
	body = append(body, payload...)

	identities, err := s.method.packetIdentityHeaders(header)
	if err != nil {
		return nil, err
	}
	block, err := s.method.headerBlock()
	if err != nil {
		return nil, err
	}
	nonce := append([]byte{}, header[4:16]...)
	packet := s.sealer.Seal(append(header, identities...), nonce, body, nil)
	block.Encrypt(packet[:separateHeaderSize], packet[:separateHeaderSize])
	return packet, nil
}

// Receive reads one datagram and returns its source and payload.
func (s *PacketSession) Receive(buf []byte) (Addr, []byte, error) {
	for {
		n, err := s.conn.Read(buf)
		if err != nil {
			return nil, nil, err
		}
		source, payload, err := s.open(buf[:n], time.Now())
		if err == nil {
			return source, payload, nil
		}
	}
}

func (s *PacketSession) open(packet []byte, now time.Time) (Addr, []byte, error) {
	if len(packet) < separateHeaderSize+tagSize {
		return nil, nil, errors.New("short packet")
	}
	header := packet[:separateHeaderSize]
	s.method.block.Decrypt(header, header)
	var serverID [8]byte
	copy(serverID[:], header[:8])
	packetID := binary.BigEndian.Uint64(header[8:])

	server, err := s.server(serverID, now)
	if err != nil {
		return nil, nil, err
	}
	if !server.window.check(packetID) {
		return nil, nil, errors.New("replayed packet")
	}
	body, err := server.opener.Open(packet[separateHeaderSize:separateHeaderSize], header[4:16], packet[separateHeaderSize:], nil)
	if err != nil {
		return nil, nil, errors.New("packet failed authentication")
	}
	source, payload, err := s.parseServerBody(body, now)
	if err != nil {
		return nil, nil, err
	}
	s.lock.Lock()
	server.window.update(packetID)
	server.lastSeen = now
	s.lock.Unlock()
	return source, payload, nil
}

func (s *PacketSession) parseServerBody(body []byte, now time.Time) (Addr, []byte, error) {
	if len(body) < 1+8+8+2 || body[0] != typeServer {
		return nil, nil, errors.New("bad packet header")
	}
	if err := checkTimestamp(binary.BigEndian.Uint64(body[1:9]), now); err != nil {
		return nil, nil, err
	}
	if [8]byte(body[9:17]) != s.sessionID {
		return nil, nil, errors.New("packet for another session")
	}
	padding := int(binary.BigEndian.Uint16(body[17:19]))
	if len(body) < 19+padding {
		return nil, nil, errors.New("short padding")
	}
	return splitAddr(body[19+padding:])
}

// server returns the cipher for one server session, forgetting stale ones.
func (s *PacketSession) server(id [8]byte, now time.Time) (*serverSession, error) {
	s.lock.Lock()
	defer s.lock.Unlock()
	if server, ok := s.servers[id]; ok {
		return server, nil
	}
	for key, old := range s.servers {
		if now.Sub(old.lastSeen) > 2*time.Minute {
			delete(s.servers, key)
		}
	}
	opener, err := s.method.sessionAEAD(id[:])
	if err != nil {
		return nil, err
	}
	server := &serverSession{opener: opener, lastSeen: now}
	s.servers[id] = server
	return server, nil
}

// Close closes the UDP socket.
func (s *PacketSession) Close() error { return s.conn.Close() }
