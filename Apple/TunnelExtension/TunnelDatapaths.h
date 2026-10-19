/*
 * The two C datapaths this extension calls into, brought into Swift.
 *
 * **LibXray is DECLARED here rather than imported, and that is not a
 * shortcut.** Its prototypes live in `wireguard.h`, inside the AmneziaWG
 * package's `WireGuardKitGo` target — a target, not a product, so no other
 * module can import it. What CAN be relied on is the link: this extension
 * already links `libwg-go.a` for WireGuard, and Amnezia builds
 * `amnezia-libxray` into that same archive, so the symbols below are in the
 * binary whether or not anything declares them. These declarations are copied
 * from that header verbatim; they are checked by the only check that can catch
 * a drift, which is the linker.
 *
 * hev-socks5-tunnel is the other half of the same datapath: Xray is a proxy
 * and has no idea what an IP packet is, so lwIP inside this library takes the
 * packets off the tunnel interface and opens a SOCKS5 connection per flow.
 * That one has a public header, and it is included.
 */

#ifndef GRYONIX_TUNNEL_DATAPATHS_H
#define GRYONIX_TUNNEL_DATAPATHS_H

#include <stdint.h>
#include <sys/types.h>
#include <sys/ioctl.h>

/* What it takes to ask an open descriptor whether it is the utun this
 * extension was handed (see `XrayDatapath`).
 *
 * **Written out rather than included, and the iOS SDK is why.**
 * `<sys/kern_control.h>` exists on macOS and NOT in the iOS SDK's public
 * headers: including it builds on a Mac and stops the iOS build with "file not
 * found", while leaving it out leaves `ctl_info` and `sockaddr_ctl` out of
 * Swift's scope on BOTH platforms. `CTLIOCGINFO` is a third problem of its
 * own — an `_IOWR` doing arithmetic on a `sizeof`, which Swift's importer
 * drops on the floor with no diagnostic saying why.
 *
 * All three go away with the declarations below, and they are WireGuard's own,
 * copied verbatim from `WireGuardKitC.h` in the package this extension already
 * links ("From <sys/kern_control.h>", same three lines). That is the same
 * trade made for the same reason by code that ships on both platforms, and it
 * is checked by the only check that can catch a drift: the kernel, which fills
 * these in. */
static const unsigned long GryonixControlGetInfo = 0xc0644e03UL;
struct ctl_info {
    u_int32_t   ctl_id;
    char        ctl_name[96];
};
struct sockaddr_ctl {
    u_char      sc_len;
    u_char      sc_family;
    u_int16_t   ss_sysaddr;
    u_int32_t   sc_id;
    u_int32_t   sc_unit;
    u_int32_t   sc_reserved[5];
};

/* Every one of these returns a C string the CALLER owns: the Go side hands
 * back `C.CString(...)`, which is `malloc`ed and never freed by Go. Empty
 * means success and anything else is the failure's own words. */
extern char *LibXrayRunXray(const char *datDir, const char *configPath, int64_t maxMemory);
extern char *LibXrayStopXray(void);
extern char *LibXrayXrayVersion(void);

/* Shadowsocks 2022 client from Go/ss2022, same ownership rules. */
extern char *GryonixSSStart(const char *listen, const char *server,
                            const char *method, const char *password,
                            const char *user, const char *pass);
extern char *GryonixSSStop(void);
/* Where Go writes a fatal panic before the process exits. */
extern char *GryonixCrashOutput(const char *path);
/* Go's heap and stacks in use, and its goroutines. */
extern char *GryonixGoMemory(void);

#include "hev-main.h"

#endif /* GRYONIX_TUNNEL_DATAPATHS_H */
