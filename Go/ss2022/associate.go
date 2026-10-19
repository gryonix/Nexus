package ss2022

import (
	"io"
	"net"
	"sync"
	"time"
)

// dnsPort is the UDP destination port answered over TCP instead.
var dnsPort = "53"

const dnsTimeout = 6 * time.Second

// relayPackets serves one UDP ASSOCIATE until its control stream closes.
func (c *Client) relayPackets(control net.Conn) {
	host, _, _ := net.SplitHostPort(control.LocalAddr().String())
	local, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.ParseIP(host)})
	if err != nil {
		_ = reply(control, replyFailed, nil)
		return
	}
	defer local.Close()
	server, err := c.dial("udp")
	if err != nil {
		_ = reply(control, replyFailed, nil)
		return
	}
	session, err := NewPacketSession(server, c.method)
	if err != nil {
		server.Close()
		_ = reply(control, replyFailed, nil)
		return
	}
	defer session.Close()
	if reply(control, replySucceeded, addrFromUDP(local.LocalAddr().(*net.UDPAddr))) != nil {
		return
	}
	peer := &lastPeer{}
	go c.packetsUp(local, session, peer)
	go packetsDown(local, session, peer)
	_, _ = io.Copy(io.Discard, control)
}

// lastPeer remembers the one address the local client sends from.
type lastPeer struct {
	lock sync.Mutex
	addr *net.UDPAddr
}

// accept pins the first sender and refuses every other address.
func (p *lastPeer) accept(from *net.UDPAddr) bool {
	p.lock.Lock()
	defer p.lock.Unlock()
	if p.addr == nil {
		p.addr = from
		return true
	}
	return p.addr.IP.Equal(from.IP) && p.addr.Port == from.Port
}

func (p *lastPeer) get() *net.UDPAddr {
	p.lock.Lock()
	defer p.lock.Unlock()
	return p.addr
}

// packetsUp forwards local SOCKS datagrams to the server.
func (c *Client) packetsUp(local *net.UDPConn, session *PacketSession, peer *lastPeer) {
	buf := packetBuffers.Get().(*[]byte)
	defer packetBuffers.Put(buf)
	for {
		n, from, err := local.ReadFromUDP(*buf)
		if err != nil {
			return
		}
		if n < 4 || (*buf)[2] != 0 {
			continue
		}
		target, payload, err := splitAddr((*buf)[3:n])
		if err != nil {
			continue
		}
		if !peer.accept(from) {
			continue
		}
		if isDNS(target) {
			go c.dnsOverTCP(local, peer, append(Addr{}, target...), append([]byte{}, payload...))
			continue
		}
		_ = session.Send(target, payload)
	}
}

func isDNS(target Addr) bool {
	_, port, err := net.SplitHostPort(target.String())
	return err == nil && port == dnsPort
}

// dnsOverTCP answers one DNS datagram through a TCP stream to the resolver.
func (c *Client) dnsOverTCP(local *net.UDPConn, peer *lastPeer, target Addr, query []byte) {
	server, err := c.dial("tcp")
	if err != nil {
		return
	}
	if !c.track(server) {
		server.Close()
		return
	}
	defer c.untrack(server)
	remote := NewConn(server, c.method, target)
	defer remote.Close()
	_ = server.SetDeadline(time.Now().Add(dnsTimeout))
	frame := append([]byte{byte(len(query) >> 8), byte(len(query))}, query...)
	if _, err := remote.Write(frame); err != nil {
		return
	}
	var size [2]byte
	if _, err := io.ReadFull(remote, size[:]); err != nil {
		return
	}
	answer := make([]byte, int(size[0])<<8|int(size[1]))
	if _, err := io.ReadFull(remote, answer); err != nil {
		return
	}
	if to := peer.get(); to != nil {
		_, _ = local.WriteToUDP(append(append([]byte{0, 0, 0}, target...), answer...), to)
	}
}

// packetsDown forwards server datagrams back to the local client.
func packetsDown(local *net.UDPConn, session *PacketSession, peer *lastPeer) {
	buf := packetBuffers.Get().(*[]byte)
	defer packetBuffers.Put(buf)
	for {
		source, payload, err := session.Receive(*buf)
		if err != nil {
			return
		}
		to := peer.get()
		if to == nil {
			continue
		}
		packet := append(append([]byte{0, 0, 0}, source...), payload...)
		_, _ = local.WriteToUDP(packet, to)
	}
}
