package ss2022

import (
	"net"
	"testing"
)

func TestOnlyTheFirstSenderIsServed(t *testing.T) {
	first := &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 50000}
	other := &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 50001}
	peer := &lastPeer{}
	if !peer.accept(first) {
		t.Fatal("the first sender was refused")
	}
	if !peer.accept(&net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 50000}) {
		t.Fatal("the pinned sender was refused on a later datagram")
	}
	if peer.accept(other) {
		t.Fatal("a second local sender was accepted")
	}
	if got := peer.get(); got == nil || got.Port != 50000 {
		t.Fatalf("replies would go to %v", got)
	}
}
