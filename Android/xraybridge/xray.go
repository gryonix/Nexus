// The Xray core, as three functions Kotlin can call.
//
// **A bridge module, and it is here rather than fetched, because the shape of
// the API is ours.** `amnezia-libxray` is a Go package with a good deal more
// surface than this app has any use for, and `gomobile bind` exports whatever
// it can and fails on whatever it cannot. Three functions is what the datapath
// needs, and a wrapper that names them is also the record of what this app
// actually calls into a proxy core to do.
//
// The Apple side reaches the SAME core without any of this: Amnezia builds
// `amnezia-libxray` into the very archive that carries WireGuard there, so the
// symbols are already in the binary. Android's fork of the tunnel does not
// (checked with `nm` on the AAR's `libwg-go.so`, 2026-09-06), which is the
// whole reason this module exists.
//
// Built by `scripts/build-runtimes.sh android-xray` into a gitignored AAR.
package xraybridge

import (
	"github.com/amnezia-vpn/amnezia-libxray/xray"
)

// Run starts the core against a configuration file and returns once it is
// running — it does NOT block. datDir is where geo data would be looked for;
// this app writes no routing rule that needs any, so it is only ever the
// app's own files directory.
//
// maxMemory is Go's soft memory limit in bytes, which makes the runtime
// collect harder rather than grow. A tunnel service is killed without a word
// when Android decides it is too big, so the budget is stated rather than
// discovered.
func Run(datDir string, configPath string, maxMemory int64) error {
	return xray.RunXray(datDir, configPath, maxMemory)
}

// Stop tears the core down. Safe to call when nothing is running.
func Stop() error {
	return xray.StopXray()
}

// Version is what the core calls itself — for the About screen and for a bug
// report that has to say which core was carrying the traffic.
func Version() string {
	return xray.XrayVersion()
}
