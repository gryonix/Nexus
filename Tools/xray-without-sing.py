#!/usr/bin/env python3
"""Copies xray-core and cuts out everything that links sagernet/sing.

Usage: xray-without-sing.py SOURCE_DIR DEST_DIR
Shadowsocks 2022 then comes from Go/ss2022 instead.
"""

import os
import re
import shutil
import stat
import sys

STUB = 'errors.New("Shadowsocks 2022 is not built into this core")'


def replace(text, old, new, path):
    if old not in text:
        sys.exit(f"{path}: expected text not found: {old[:60]!r}")
    return text.replace(old, new)


def patch_conf(path):
    s = open(path).read()
    for line in ('\t"github.com/sagernet/sing-shadowsocks/shadowaead_2022"\n',
                 '\tC "github.com/sagernet/sing/common"\n',
                 '\t"github.com/xtls/xray-core/proxy/shadowsocks_2022"\n'):
        s = replace(s, line, "", path)
    s = replace(s, "C.Contains(shadowaead_2022.List, ", "isShadowsocks2022(", path)
    s, n = re.subn(r"func buildShadowsocks2022\(v \*ShadowsocksServerConfig\) \(proto\.Message, error\) \{\n.*?\n\}\n",
                   "func buildShadowsocks2022(v *ShadowsocksServerConfig) (proto.Message, error) {\n"
                   f"\treturn nil, {STUB}\n}}\n", s, flags=re.S)
    if n != 1:
        sys.exit(f"{path}: buildShadowsocks2022 not found")
    s, n = re.subn(r"config := new\(shadowsocks_2022\.ClientConfig\)\n.*?return config, nil",
                   f"return nil, {STUB}", s, flags=re.S)
    if n != 1:
        sys.exit(f"{path}: Shadowsocks 2022 client block not found")
    s += '\nfunc isShadowsocks2022(cipher string) bool { return strings.HasPrefix(cipher, "2022-") }\n'
    if "shadowsocks_2022" in s or "sagernet" in s:
        sys.exit(f"{path}: sing references remain")
    open(path, "w").write(s)


def patch_api(path):
    s = open(path).read()
    s = replace(s, '\t"github.com/xtls/xray-core/proxy/shadowsocks_2022"\n', "", path)
    s = replace(s, "\tcase *shadowsocks_2022.MultiUserServerConfig:\n\t\treturn ty.Users\n", "", path)
    open(path, "w").write(s)


def make_writable(root):
    for directory, dirs, files in os.walk(root):
        for name in dirs + files:
            p = os.path.join(directory, name)
            os.chmod(p, os.stat(p).st_mode | stat.S_IWUSR)
    os.chmod(root, os.stat(root).st_mode | stat.S_IWUSR)


def main():
    source, dest = sys.argv[1], sys.argv[2]
    if os.path.exists(dest):
        make_writable(dest)
        shutil.rmtree(dest)
    shutil.copytree(source, dest)
    make_writable(dest)
    for gone in ("proxy/shadowsocks_2022", "common/singbridge"):
        shutil.rmtree(os.path.join(dest, gone))
    patch_conf(os.path.join(dest, "infra/conf/shadowsocks.go"))
    patch_api(os.path.join(dest, "main/commands/all/api/inbound_user_add.go"))
    for directory, _, files in os.walk(dest):
        for name in files:
            if name.endswith(".go") and not name.endswith("_test.go"):
                text = open(os.path.join(directory, name), errors="replace").read()
                if "github.com/sagernet/sing" in text:
                    sys.exit(f"{os.path.join(directory, name)} still imports sing")
    print(f"xray-core without sing -> {dest}")


if __name__ == "__main__":
    main()
