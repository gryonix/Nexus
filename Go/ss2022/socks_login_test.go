package ss2022

import (
	"bufio"
	"bytes"
	"testing"
)

func greetingWith(methods []byte, login []byte) *bufio.Reader {
	data := append([]byte{socksVersion, byte(len(methods))}, methods...)
	data = append(data, login...)
	data = append(data, socksVersion, cmdConnect, 0, atypIPv4, 1, 2, 3, 4, 0, 80)
	return bufio.NewReader(bytes.NewReader(data))
}

func loginBytes(user, pass string) []byte {
	out := append([]byte{loginVersion, byte(len(user))}, user...)
	return append(append(out, byte(len(pass))), pass...)
}

var sessionLogin = &Login{Username: "session-user", Password: "session-pass"}

func TestRightLoginReachesTheRequest(t *testing.T) {
	var out bytes.Buffer
	command, _, err := handshake(greetingWith([]byte{methodPassword},
		loginBytes("session-user", "session-pass")), &out, sessionLogin)
	if err != nil || command != cmdConnect {
		t.Fatalf("command %d, error %v", command, err)
	}
	if !bytes.Equal(out.Bytes(), []byte{socksVersion, methodPassword, loginVersion, 0}) {
		t.Fatalf("replies %v", out.Bytes())
	}
}

func TestWrongLoginIsRefused(t *testing.T) {
	for _, pass := range []string{"wrong", "", "session-pass-and-more"} {
		var out bytes.Buffer
		_, _, err := handshake(greetingWith([]byte{methodPassword},
			loginBytes("session-user", pass)), &out, sessionLogin)
		if err == nil {
			t.Fatalf("password %q was accepted", pass)
		}
		if !bytes.Equal(out.Bytes(), []byte{socksVersion, methodPassword, loginVersion, 1}) {
			t.Fatalf("replies %v", out.Bytes())
		}
	}
}

func TestNoAuthIsRefusedWhenALoginIsSet(t *testing.T) {
	var out bytes.Buffer
	_, _, err := handshake(greetingWith([]byte{methodNoAuth}, nil), &out, sessionLogin)
	if err == nil {
		t.Fatal("an anonymous client was accepted")
	}
	if !bytes.Equal(out.Bytes(), []byte{socksVersion, methodNone}) {
		t.Fatalf("replies %v", out.Bytes())
	}
}

func TestWithoutALoginNoAuthStillWorks(t *testing.T) {
	var out bytes.Buffer
	command, _, err := handshake(greetingWith([]byte{methodNoAuth}, nil), &out, nil)
	if err != nil || command != cmdConnect {
		t.Fatalf("command %d, error %v", command, err)
	}
}
