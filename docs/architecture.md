# Routing and boundaries

All LAN Ethernet ports join `br-lan`. An external AP must use AP/bridge mode with its own DHCP and NAT disabled; connect its LAN port to this bridge. Optional hostapd adds the Wi-Fi interface to the same bridge. This is one trusted LAN, without guest isolation or VLAN segmentation.

dnsmasq owns UDP/TCP 53 and DHCPv4 on LAN and listens on loopback. It serves `home.arpa` and DHCP names locally. When proxy routing is enabled, it forwards other queries to sing-box on `127.0.0.1:5353` and disables its own DNS cache. sing-box returns synthetic A records from `198.18.0.0/15`, remembers the domain mapping, and persists mappings in its private state directory. This permits domain routing even when an application's TLS name is encrypted, provided it uses the router's DNS. AAAA answers are filtered.

LAN port-53 traffic is redirected to dnsmasq by default, including hardcoded public DNS addresses. This does **not** intercept DNS-over-HTTPS, DNS-over-TLS, VPN tunnels, or a client's existing cached real addresses. HTTP/TLS/QUIC sniffing may recover a name for such connections, but cannot guarantee it. Otherwise CIDR rules and the default route apply. Configure clients to use router DNS and clear old DNS caches during onboarding. Domain routing is a traffic preference, not a security boundary against malicious LAN clients.

The policy order inside sing-box is:

1. Handle its dedicated DNS inbound, then attempt protocol sniffing.
2. Match direct domain suffixes, then US domain suffixes. Suffixes include their subdomains; overlapping direct/US domains are rejected by validation.
3. Resolve remaining domain destinations using the explicit upstream resolver, then match direct CIDRs and US CIDRs. Overlapping direct/US CIDRs are rejected.
4. Use `router.proxy.defaultRoute`, initially `direct`.

Upstream DNS resolution is **direct UDP** to the first configured upstream when sing-box is enabled. DNS queries are not made private by selecting a US traffic route. With sing-box disabled, dnsmasq uses the configured upstream list. Host DNS uses those explicit IP addresses instead of WAN-provided DNS, preventing a dnsmasq/sing-box resolver loop. DNSSEC validation and encrypted upstream DNS are not provided by this baseline.

The nftables TPROXY chain only captures IPv4 TCP/UDP arriving from the LAN bridge with a LAN source. It excludes local router addresses, DNS/DHCP, protected private/reserved destinations, and remote WireGuard routes. It sets mark `1`; systemd-networkd maintains policy rule priority `100` and a local route in table `100`. These marks/table numbers are reserved for this module.

Router-originated traffic, sing-box's own outbound connections, WireGuard encapsulation, and inbound traffic from WAN/WireGuard do not re-enter the LAN interception path. There is no output-hook proxy redirect. Site traffic follows normal routes without source NAT. Only LAN source traffic exiting WAN is masqueraded. A WireGuard hub may forward between configured peers; this grants connectivity between those trusted sites. WireGuard peers cannot use this router as a general Internet exit.

The firewall defaults to dropping input and forwarding. It permits LAN SSH, DNS, DHCP, ICMP, established replies, and the configured WAN WireGuard UDP port. WAN SSH/DNS/proxy ports remain closed. Remote-site SSH is opt-in. Public LAN TCP/UDP that unexpectedly reaches forwarding while transparent mode is enabled is dropped, preventing a proxy outage or missing policy route from silently falling back to direct WAN. Existing connections may need to be restarted after policy changes. Local management and site links remain available if sing-box stops; external LAN DNS then fails because its configured upstream is unavailable.

ICMP and other non-TCP/UDP protocols are not proxied. Ordinary real-IP ICMP uses WAN directly. Synthetic FakeIP destinations never forward to WAN. IPv6 is disabled at the NixOS and sysctl levels and dropped by the inet firewall; LAN devices may still exchange link-local IPv6 on their shared Ethernet segment. Dual-stack operation needs a separately designed IPv6 firewall, DNS and proxy policy before enabling it.

The `us` tag names the outbound you supply; the configuration cannot verify a server's physical location or IP geolocation. Prefer an authenticated encrypted protocol such as Trojan, VLESS with TLS, or Shadowsocks over trusted infrastructure. A plain remote SOCKS example is for testing, not an encrypted transport. UDP works only if the selected outbound and remote server support UDP. HTTP CONNECT proxies typically cannot carry general UDP.

WireGuard uses a separate tunnel address per site and unique LAN subnets. A peer's `allowedIPs` contains its tunnel `/32` and the LAN networks reachable through it. The private key and optional preshared key are runtime files. At least one endpoint must be reachable: a public IP, forwarded UDP port, or a reachable hub. Two sites both behind CGNAT require such a hub; keepalive alone cannot solve that. Use [site-b.nix](site-b.nix) as a reciprocal example, never its placeholder key or endpoint.

Defaults assume Ethernet IPv4 DHCP, not PPPoE or an ISP VLAN. Configure the relevant NixOS link/PPPoE module and select the actual resulting WAN interface if needed. Confirm MTU with the ISP and sites; WireGuard starts at 1380. This baseline does not promise line-rate proxy throughput on unknown hardware.
