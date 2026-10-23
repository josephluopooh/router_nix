#!/usr/bin/env python3
"""Merge one runtime outbound into the public config; never print credentials."""
import json
import os
import sys
from pathlib import Path


def render(base, outbound):
    if not isinstance(outbound, dict) or outbound.get("tag") != "us":
        raise ValueError("outbound must be one JSON object tagged 'us'")
    if outbound.get("type") not in {"socks", "http", "shadowsocks", "vmess", "trojan", "vless", "hysteria2", "tuic", "anytls", "ssh"}:
        raise ValueError("outbound type must be an explicit remote proxy protocol")
    if not isinstance(outbound.get("server"), str) or not outbound["server"]:
        raise ValueError("outbound requires a server")
    if type(outbound.get("server_port")) is not int or not 1 <= outbound["server_port"] <= 65535:
        raise ValueError("outbound requires a valid server_port")
    if not isinstance(outbound.get("tls", {}), dict):
        raise ValueError("TLS settings must be an object")
    if outbound.get("tls", {}).get("insecure"):
        raise ValueError("TLS certificate verification must remain enabled")
    if "detour" in outbound or "routing_mark" in outbound:
        raise ValueError("outbound may not override routing marks or detour")
    return dict(base, outbounds=base["outbounds"] + [outbound])


def main():
    base, source, destination = map(Path, sys.argv[1:])
    try:
        result = render(json.loads(base.read_text()), json.loads(source.read_text()))
        # The service's private runtime directory prevents symlink attacks.
        fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w") as output:
            json.dump(result, output)
            output.write("\n")
    except (ValueError, OSError, TypeError, KeyError):
        sys.exit("Unable to assemble proxy config; check runtime outbound format and file permissions.")


if __name__ == "__main__":
    main()
