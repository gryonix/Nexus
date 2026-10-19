// Package ss2022 is a Shadowsocks 2022 (SIP022) client with a local SOCKS5 front.
package ss2022

import (
	"crypto/aes"
	"crypto/cipher"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
	"time"

	"lukechampine.com/blake3"
)

const (
	subkeyContext        = "shadowsocks 2022 session subkey"
	identityContext      = "shadowsocks 2022 identity subkey"
	tagSize              = 16
	maxPayload           = 0xFFFF
	maxPadding           = 900
	maxClockSkew         = 30 * time.Second
	typeClient      byte = 0
	typeServer      byte = 1
)

// Method is one AEAD-2022 cipher with its pre-shared keys.
type Method struct {
	psk   []byte
	block cipher.Block
	// identities are the server keys before the user key (SIP023)
	identities [][]byte
}

// NewMethod parses a method name and a base64 pre-shared key.
func NewMethod(name, password string) (*Method, error) {
	size, ok := map[string]int{
		"2022-blake3-aes-128-gcm": 16,
		"2022-blake3-aes-256-gcm": 32,
	}[name]
	if !ok {
		return nil, fmt.Errorf("unsupported method %q", name)
	}
	var keys [][]byte
	for _, part := range strings.Split(password, ":") {
		key, err := base64.StdEncoding.DecodeString(part)
		if err != nil {
			return nil, fmt.Errorf("key is not base64: %w", err)
		}
		if len(key) != size {
			return nil, fmt.Errorf("key is %d bytes, %s needs %d", len(key), name, size)
		}
		keys = append(keys, key)
	}
	psk := keys[len(keys)-1]
	block, err := aes.NewCipher(psk)
	if err != nil {
		return nil, err
	}
	return &Method{psk: psk, block: block, identities: keys[:len(keys)-1]}, nil
}

// nextKey is the key an identity header names after layer i
func (m *Method) nextKey(i int) []byte {
	if i+1 < len(m.identities) {
		return m.identities[i+1]
	}
	return m.psk
}

// identityHeaders are the TCP request's headers between salt and chunks
func (m *Method) identityHeaders(salt []byte) ([]byte, error) {
	var out []byte
	for i, identity := range m.identities {
		subkey := make([]byte, len(identity))
		blake3.DeriveKey(subkey, identityContext, append(append([]byte{}, identity...), salt...))
		block, err := aes.NewCipher(subkey)
		if err != nil {
			return nil, err
		}
		header := identityPlaintext(m.nextKey(i))
		block.Encrypt(header, header)
		out = append(out, header...)
	}
	return out, nil
}

// packetIdentityHeaders are the UDP headers after the separate header
func (m *Method) packetIdentityHeaders(separate []byte) ([]byte, error) {
	var out []byte
	for i, identity := range m.identities {
		block, err := aes.NewCipher(identity)
		if err != nil {
			return nil, err
		}
		header := identityPlaintext(m.nextKey(i))
		for j := range header {
			header[j] ^= separate[j]
		}
		block.Encrypt(header, header)
		out = append(out, header...)
	}
	return out, nil
}

// headerBlock encrypts the client's separate header
func (m *Method) headerBlock() (cipher.Block, error) {
	if len(m.identities) == 0 {
		return m.block, nil
	}
	return aes.NewCipher(m.identities[0])
}

func identityPlaintext(key []byte) []byte {
	sum := blake3.Sum256(key)
	return append([]byte{}, sum[:16]...)
}

// saltSize equals the key size for every AES method.
func (m *Method) saltSize() int { return len(m.psk) }

// sessionAEAD derives the AES-GCM cipher for one salt.
func (m *Method) sessionAEAD(salt []byte) (cipher.AEAD, error) {
	material := make([]byte, 0, len(m.psk)+len(salt))
	material = append(append(material, m.psk...), salt...)
	key := make([]byte, len(m.psk))
	blake3.DeriveKey(key, subkeyContext, material)
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}

// nonce is a 96-bit little-endian counter.
type nonce [12]byte

func (n *nonce) next() []byte {
	current := *n
	for i := range n {
		n[i]++
		if n[i] != 0 {
			break
		}
	}
	return current[:]
}

func checkTimestamp(seconds uint64, now time.Time) error {
	diff := now.Sub(time.Unix(int64(seconds), 0))
	if diff > maxClockSkew || diff < -maxClockSkew {
		return errors.New("server clock differs by more than 30 seconds")
	}
	return nil
}
