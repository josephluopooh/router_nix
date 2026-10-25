#!/usr/bin/env python3
"""Validate evaluated router options before building an installable system."""
import base64
import ipaddress as ip
import json
import re
import sys
from pathlib import PurePosixPath


def require(condition, message):
    if not condition:
        raise ValueError(message)


def network(value):
    result = ip.ip_network(value, strict=True)
    require(result.version == 4, "Only IPv4 policy/subnets are supported")
    return result


def secret(path):
    require(isinstance(path, str) and path.startswith("/"), "Secret paths must be absolute strings")
    require(".." not in PurePosixPath(path).parts, "Secret paths cannot contain '..'")
    require(path != "/nix/store" and not path.startswith("/nix/store/"), "Secrets must not enter the Nix store")


def validate(cfg):
    lan = network(cfg["lan"]["subnet"])
    require(lan.prefixlen == 24, "LAN must be a /24")
    require(any(lan.subnet_of(network(n)) for n in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]), "LAN must use RFC1918 space")
    wan = cfg["wan"]
    ports = cfg["lan"]["ports"]
    require(len(ports) == len(set(ports)), "LAN ports must be unique")
    require(ports and wan["interface"] not in ports, "WAN/LAN interfaces must be separate")
    require(2 <= cfg["lan"]["dhcpStart"] <= cfg["lan"]["dhcpEnd"] <= 254, "DHCP pool must exclude gateway/network/broadcast")
    if not wan["dhcp"]:
        interface = ip.ip_interface(wan["address"])
        gateway = ip.ip_address(wan["gateway"])
        require(interface.version == 4 and gateway.version == 4, "Static WAN must use IPv4")
        require(gateway in interface.network, "Static WAN gateway must be on-link")
        require(not interface.network.overlaps(lan), "WAN and LAN cannot overlap")
    for address in cfg["dns"]["upstream"]:
        addr = ip.ip_address(address)
        require(addr.version == 4 and not addr.is_loopback and not addr.is_unspecified and not addr.is_multicast and addr not in lan and addr not in network("198.18.0.0/15"), "Use explicit non-loopback, non-LAN upstream DNS IPv4 addresses")
    wg = cfg["wireguard"]
    remotes = []
    if wg["enable"]:
        secret(wg["privateKeyFile"])
        local = ip.ip_interface(wg["address"])
        require(local.version == 4 and not local.network.overlaps(lan), "WireGuard connected network must be distinct from LAN")
        if not wan["dhcp"]:
            require(not local.network.overlaps(ip.ip_interface(wan["address"]).network), "WireGuard connected network must not overlap the WAN network")
        require(wg["peers"], "Enabled WireGuard requires peers")
        for peer in wg["peers"]:
            try:
                require(len(base64.b64decode(peer["publicKey"], validate=True)) == 32, "WireGuard public keys must encode 32 bytes")
            except (ValueError, TypeError) as e:
                raise ValueError("Invalid WireGuard public key") from e
            require(peer["allowedIPs"], "WireGuard peers require explicit routes")
            if peer["presharedKeyFile"] is not None:
                secret(peer["presharedKeyFile"])
            current = [network(n) for n in peer["allowedIPs"]]
            for route in current:
                require(route.prefixlen > 0 and not route.overlaps(lan), "WireGuard cannot claim the default route or local LAN")
                require(local.ip not in route, "Peer cannot claim this router's WireGuard IP")
                require(not any(route.overlaps(other) for other in remotes), "Different peers cannot claim overlapping routes")
                if not wan["dhcp"]:
                    require(not route.overlaps(ip.ip_interface(wan["address"]).network), "Peer route must not capture the WAN network")
            remotes.extend(current)
    proxy = cfg["proxy"]
    if proxy["enable"]:
        secret(proxy["outboundFile"])
        fake = network("198.18.0.0/15")
        bypass = [network(n) for n in proxy["bypassCIDRs"]] + [lan] + remotes
        require(not any(fake.overlaps(n) for n in bypass), "FakeIP range cannot bypass sing-box")
        direct = [network(n) for n in proxy["directCIDRs"]]
        us = [network(n) for n in proxy["usCIDRs"]]
        for route in direct + us:
            require(not route.overlaps(fake), "FakeIP pool is reserved")
        require(not any(a.overlaps(b) for a in direct for b in us), "Direct/US CIDRs cannot overlap")
        require(not any(a.overlaps(b) for a in us for b in bypass), "US CIDRs cannot override protected direct networks")
        domains = proxy["directDomains"] + proxy["usDomains"]
        require(all(re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", d) and ".." not in d for d in domains), "Domain suffixes must be lowercase names without wildcards, schemes, or empty labels")
        require(not any(a == b or a.endswith("." + b) or b.endswith("." + a) for a in proxy["directDomains"] for b in proxy["usDomains"]), "Direct/US domain suffixes cannot overlap")
    if cfg["wifi"]["enable"]:
        secret(cfg["wifi"]["passwordFile"])
        require(re.fullmatch("[A-Z]{2}", cfg["wifi"]["country"]) is not None, "Wi-Fi requires the actual country code")
    return True


if __name__ == "__main__":
    try:
        with (open(sys.argv[1]) if len(sys.argv) > 1 else sys.stdin) as source:
            validate(json.load(source))
        print("Site validation passed")
    except (ValueError, KeyError, TypeError) as error:
        sys.exit(f"Site validation failed: {error}")
