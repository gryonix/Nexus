package ss2022

import (
	"io"
	"sync"
)

// One datagram buffer per running UDP relay direction.
var packetBuffers = sync.Pool{New: func() any {
	buf := make([]byte, 64*1024)
	return &buf
}}

var streamBuffers = sync.Pool{New: func() any {
	buf := make([]byte, 16*1024)
	return &buf
}}

// copyPooled copies with a shared buffer instead of a fresh one.
func copyPooled(dst io.Writer, src io.Reader) error {
	buf := streamBuffers.Get().(*[]byte)
	defer streamBuffers.Put(buf)
	_, err := io.CopyBuffer(struct{ io.Writer }{dst}, struct{ io.Reader }{src}, *buf)
	return err
}
