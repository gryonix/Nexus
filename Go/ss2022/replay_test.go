package ss2022

import "testing"

func TestReplayWindow(t *testing.T) {
	var w replayWindow
	accept := func(id uint64) bool {
		if !w.check(id) {
			return false
		}
		w.update(id)
		return true
	}
	for _, id := range []uint64{0, 1, 5, 3, 2} {
		if !accept(id) {
			t.Fatalf("fresh id %d rejected", id)
		}
	}
	for _, id := range []uint64{0, 3, 5} {
		if accept(id) {
			t.Fatalf("duplicate id %d accepted", id)
		}
	}
	if !accept(5 + windowBits) {
		t.Fatal("jump forward rejected")
	}
	if accept(5) {
		t.Fatal("id behind the window accepted")
	}
	if !accept(6 + windowBits/2) {
		t.Fatal("unseen id inside the window rejected")
	}
}

func TestNonceCountsLittleEndian(t *testing.T) {
	var n nonce
	n[0] = 0xFF
	if got := n.next(); got[0] != 0xFF {
		t.Fatal("next must return the current value")
	}
	if n[0] != 0 || n[1] != 1 {
		t.Fatalf("carry failed: %v", n)
	}
}

func TestMethodRejectsBadKeys(t *testing.T) {
	cases := map[string][2]string{
		"unknown method": {"aes-256-gcm", "AAAA"},
		"short key":      {"2022-blake3-aes-256-gcm", "AAAAAAAAAAAAAAAAAAAAAA=="},
		"not base64":     {"2022-blake3-aes-256-gcm", "%%%"},
		"bad user key":   {"2022-blake3-aes-256-gcm", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=:a"},
	}
	for name, c := range cases {
		if _, err := NewMethod(c[0], c[1]); err == nil {
			t.Errorf("%s accepted", name)
		}
	}
}
