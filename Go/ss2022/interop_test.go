package ss2022

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

const interopMethod = "2022-blake3-aes-256-gcm"

// startServer runs shadowsocks-rust's ssserver on a free port.
func startServer(t *testing.T, key string) string {
	return startServerWith(t, key, "")
}

// startServerWith runs ssserver, multi-user when given a user key.
func startServerWith(t *testing.T, key, userKey string) string {
	binary, err := exec.LookPath("ssserver")
	if err != nil {
		t.Skip("ssserver not installed (brew install shadowsocks-rust)")
	}
	port := freePort(t)
	users := ""
	if userKey != "" {
		users = fmt.Sprintf(`,"users":[{"name":"phone","password":%q}]`, userKey)
	}
	config := fmt.Sprintf(`{"servers":[{"server":"127.0.0.1","server_port":%d,"method":%q,"password":%q,"mode":"tcp_and_udp"%s}]}`,
		port, interopMethod, key, users)
	path := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(path, []byte(config), 0o600); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(binary, "-c", path)
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = cmd.Process.Kill(); _ = cmd.Wait() })
	address := fmt.Sprintf("127.0.0.1:%d", port)
	waitForPort(t, address)
	return address
}

func freePort(t *testing.T) int {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}

func waitForPort(t *testing.T, address string) {
	for deadline := time.Now().Add(5 * time.Second); time.Now().Before(deadline); time.Sleep(50 * time.Millisecond) {
		if conn, err := net.Dial("tcp", address); err == nil {
			conn.Close()
			return
		}
	}
	t.Fatalf("%s never started", address)
}

func newKey(t *testing.T) string {
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		t.Fatal(err)
	}
	return base64.StdEncoding.EncodeToString(key)
}

// startClient runs our SOCKS5 front against server.
func startClient(t *testing.T, server, key string) string {
	method, err := NewMethod(interopMethod, key)
	if err != nil {
		t.Fatal(err)
	}
	client, err := Listen("127.0.0.1:0", server, method)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = client.Close() })
	return client.Addr().String()
}

// socksRequest performs a SOCKS5 handshake and returns the bound address.
func socksRequest(t *testing.T, conn net.Conn, command byte, target Addr) Addr {
	request := append([]byte{5, 1, 0, 5, command, 0}, target...)
	if _, err := conn.Write(request); err != nil {
		t.Fatal(err)
	}
	head := make([]byte, 5)
	if _, err := io.ReadFull(conn, head[:2]); err != nil || head[1] != 0 {
		t.Fatalf("greeting failed: %v %v", head[:2], err)
	}
	if _, err := io.ReadFull(conn, head[:3]); err != nil || head[1] != replySucceeded {
		t.Fatalf("request failed: %v %v", head[:3], err)
	}
	bound, err := readAddr(conn)
	if err != nil {
		t.Fatal(err)
	}
	return bound
}

func tcpEcho(t *testing.T, greeting []byte) Addr {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { l.Close() })
	go func() {
		for {
			conn, err := l.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				_, _ = conn.Write(greeting)
				_, _ = io.Copy(conn, conn)
			}()
		}
	}()
	return addrFromTCP(l.Addr().(*net.TCPAddr))
}

func addrFromTCP(a *net.TCPAddr) Addr {
	return addrFromUDP(&net.UDPAddr{IP: a.IP, Port: a.Port})
}

func TestTCPThroughShadowsocksRust(t *testing.T) {
	key := newKey(t)
	socks := startClient(t, startServer(t, key), key)
	target := tcpEcho(t, nil)

	conn, err := net.Dial("tcp", socks)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	socksRequest(t, conn, cmdConnect, target)

	payload := make([]byte, 200_000)
	_, _ = rand.Read(payload)
	go func() { _, _ = conn.Write(payload) }()
	got := make([]byte, len(payload))
	_ = conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	if _, err := io.ReadFull(conn, got); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, payload) {
		t.Fatal("echo differs")
	}
}

func TestServerSpeaksFirst(t *testing.T) {
	key := newKey(t)
	socks := startClient(t, startServer(t, key), key)
	target := tcpEcho(t, []byte("SSH-2.0-test\r\n"))

	conn, err := net.Dial("tcp", socks)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	socksRequest(t, conn, cmdConnect, target)
	got := make([]byte, 14)
	_ = conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	if _, err := io.ReadFull(conn, got); err != nil || string(got) != "SSH-2.0-test\r\n" {
		t.Fatalf("greeting %q, %v", got, err)
	}
}

func TestWrongKeyGetsNothing(t *testing.T) {
	socks := startClient(t, startServer(t, newKey(t)), newKey(t))
	conn, err := net.Dial("tcp", socks)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	socksRequest(t, conn, cmdConnect, tcpEcho(t, nil))
	_, _ = conn.Write([]byte("hello"))
	_ = conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	if n, _ := conn.Read(make([]byte, 5)); n > 0 {
		t.Fatal("data came back with the wrong key")
	}
}

func udpEcho(t *testing.T) Addr {
	conn, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	go func() {
		buf := make([]byte, 65536)
		for {
			n, from, err := conn.ReadFromUDP(buf)
			if err != nil {
				return
			}
			_, _ = conn.WriteToUDP(buf[:n], from)
		}
	}()
	return addrFromUDP(conn.LocalAddr().(*net.UDPAddr))
}

func TestUDPThroughShadowsocksRust(t *testing.T) {
	key := newKey(t)
	socks := startClient(t, startServer(t, key), key)
	target := udpEcho(t)

	control, err := net.Dial("tcp", socks)
	if err != nil {
		t.Fatal(err)
	}
	defer control.Close()
	bound := socksRequest(t, control, cmdAssociate, Addr{atypIPv4, 0, 0, 0, 0, 0, 0})
	relay, err := net.Dial("udp", bound.String())
	if err != nil {
		t.Fatal(err)
	}
	defer relay.Close()

	for i := range 3 {
		payload := binary.BigEndian.AppendUint32([]byte("ping"), uint32(i))
		if _, err := relay.Write(append(append([]byte{0, 0, 0}, target...), payload...)); err != nil {
			t.Fatal(err)
		}
		buf := make([]byte, 2048)
		_ = relay.SetReadDeadline(time.Now().Add(5 * time.Second))
		n, err := relay.Read(buf)
		if err != nil {
			t.Fatalf("packet %d: %v", i, err)
		}
		source, got, err := splitAddr(buf[3:n])
		if err != nil || !bytes.Equal(got, payload) || source.String() != target.String() {
			t.Fatalf("packet %d: %q from %s, %v", i, got, source, err)
		}
	}
}

func TestMultiUserServerOverTCPAndUDP(t *testing.T) {
	serverKey, userKey := newKey(t), newKey(t)
	socks := startClient(t, startServerWith(t, serverKey, userKey), serverKey+":"+userKey)

	conn, err := net.Dial("tcp", socks)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	socksRequest(t, conn, cmdConnect, tcpEcho(t, nil))
	_, _ = conn.Write([]byte("hello"))
	got := make([]byte, 5)
	_ = conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	if _, err := io.ReadFull(conn, got); err != nil || string(got) != "hello" {
		t.Fatalf("tcp echo %q, %v", got, err)
	}

	control, err := net.Dial("tcp", socks)
	if err != nil {
		t.Fatal(err)
	}
	defer control.Close()
	target := udpEcho(t)
	bound := socksRequest(t, control, cmdAssociate, Addr{atypIPv4, 0, 0, 0, 0, 0, 0})
	relay, err := net.Dial("udp", bound.String())
	if err != nil {
		t.Fatal(err)
	}
	defer relay.Close()
	_, _ = relay.Write(append(append([]byte{0, 0, 0}, target...), []byte("ping")...))
	buf := make([]byte, 2048)
	_ = relay.SetReadDeadline(time.Now().Add(5 * time.Second))
	n, err := relay.Read(buf)
	if err != nil {
		t.Fatalf("udp: %v", err)
	}
	if _, payload, err := splitAddr(buf[3:n]); err != nil || string(payload) != "ping" {
		t.Fatalf("udp echo %q, %v", payload, err)
	}
}

func TestDNSDatagramsAreAnsweredOverTCP(t *testing.T) {
	key := newKey(t)
	socks := startClient(t, startServer(t, key), key)
	resolver := dnsOverTCPEcho(t)
	dnsPort = resolver.port
	t.Cleanup(func() { dnsPort = "53" })

	control, err := net.Dial("tcp", socks)
	if err != nil {
		t.Fatal(err)
	}
	defer control.Close()
	bound := socksRequest(t, control, cmdAssociate, Addr{atypIPv4, 0, 0, 0, 0, 0, 0})
	relay, err := net.Dial("udp", bound.String())
	if err != nil {
		t.Fatal(err)
	}
	defer relay.Close()

	query := []byte("\x12\x34question")
	if _, err := relay.Write(append(append([]byte{0, 0, 0}, resolver.addr...), query...)); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 2048)
	_ = relay.SetReadDeadline(time.Now().Add(5 * time.Second))
	n, err := relay.Read(buf)
	if err != nil {
		t.Fatal(err)
	}
	source, got, err := splitAddr(buf[3:n])
	if err != nil || !bytes.Equal(got, append([]byte("answer:"), query...)) || source.String() != resolver.addr.String() {
		t.Fatalf("got %q from %s, %v", got, source, err)
	}
}

type tcpResolver struct {
	addr Addr
	port string
}

// dnsOverTCPEcho answers each length-prefixed query with "answer:" and the query.
func dnsOverTCPEcho(t *testing.T) tcpResolver {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { l.Close() })
	go func() {
		for {
			conn, err := l.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				var size [2]byte
				if _, err := io.ReadFull(conn, size[:]); err != nil {
					return
				}
				query := make([]byte, int(size[0])<<8|int(size[1]))
				if _, err := io.ReadFull(conn, query); err != nil {
					return
				}
				answer := append([]byte("answer:"), query...)
				_, _ = conn.Write(append([]byte{byte(len(answer) >> 8), byte(len(answer))}, answer...))
			}()
		}
	}()
	_, port, _ := net.SplitHostPort(l.Addr().String())
	return tcpResolver{addr: addrFromTCP(l.Addr().(*net.TCPAddr)), port: port}
}
