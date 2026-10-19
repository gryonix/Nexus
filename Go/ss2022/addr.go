package ss2022

import (
	"encoding/binary"
	"errors"
	"io"
	"net"
	"strconv"
)

const (
	atypIPv4   = 1
	atypDomain = 3
	atypIPv6   = 4
)

// Addr is a target in SOCKS5 wire format.
type Addr []byte

// readAddr reads one SOCKS5 address from a stream.
func readAddr(r io.Reader) (Addr, error) {
	head := make([]byte, 2)
	if _, err := io.ReadFull(r, head[:1]); err != nil {
		return nil, err
	}
	if head[0] == atypDomain {
		if _, err := io.ReadFull(r, head[1:]); err != nil {
			return nil, err
		}
	} else {
		head = head[:1]
	}
	size, err := addrSize(head)
	if err != nil {
		return nil, err
	}
	addr := make([]byte, size)
	copy(addr, head)
	_, err = io.ReadFull(r, addr[len(head):])
	return addr, err
}

// addrSize is the whole address length its first bytes promise.
func addrSize(b []byte) (int, error) {
	if len(b) < 1 {
		return 0, errors.New("empty address")
	}
	switch b[0] {
	case atypIPv4:
		return 1 + net.IPv4len + 2, nil
	case atypIPv6:
		return 1 + net.IPv6len + 2, nil
	case atypDomain:
		if len(b) < 2 {
			return 0, errors.New("short address")
		}
		return 2 + int(b[1]) + 2, nil
	}
	return 0, errors.New("unknown address type")
}

// splitAddr cuts one SOCKS5 address off the front of b.
func splitAddr(b []byte) (Addr, []byte, error) {
	size, err := addrSize(b)
	if err != nil {
		return nil, nil, err
	}
	if len(b) < size {
		return nil, nil, errors.New("short address")
	}
	return Addr(b[:size]), b[size:], nil
}

// String renders the address as host:port.
func (a Addr) String() string {
	if len(a) < 3 {
		return ""
	}
	port := strconv.Itoa(int(binary.BigEndian.Uint16(a[len(a)-2:])))
	switch a[0] {
	case atypDomain:
		return net.JoinHostPort(string(a[2:len(a)-2]), port)
	default:
		return net.JoinHostPort(net.IP(a[1:len(a)-2]).String(), port)
	}
}

// addrFromUDP converts a UDP address to SOCKS5 format.
func addrFromUDP(u *net.UDPAddr) Addr {
	ip := u.IP.To4()
	atyp := byte(atypIPv4)
	if ip == nil {
		ip, atyp = u.IP.To16(), atypIPv6
	}
	addr := append([]byte{atyp}, ip...)
	return binary.BigEndian.AppendUint16(addr, uint16(u.Port))
}
