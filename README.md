# router_nix

A modular NixOS IPv4 router for an x86-64 mini PC. It combines dnsmasq DNS/DHCP, an nftables firewall, optional hostapd, routed WireGuard between sites, and transparent sing-box routing of LAN TCP/UDP traffic through either the local WAN or a user-supplied US proxy.

The repository is a configuration kit, not a deployment to your router. No hardware, ISP settings, SSH key, site keys, or proxy subscription is assumed. The pinned nixpkgs revision is `da6dc0e7b26060f2f71ce3ef7088fb56ee44fa36` (NixOS 26.05), with sing-box **1.13.19**.

Start with [onboarding](docs/onboarding.md), then review [routing behavior](docs/architecture.md), [secrets](docs/secrets.md), [recovery](docs/recovery.md), and [validation evidence](docs/validation.md).

| Component | Behavior |
| --- | --- |
| LAN | A wired bridge with a configurable RFC1918 `/24`; dnsmasq supplies leases, gateway, and DNS |
| WAN | DHCPv4 or static IPv4; nftables masquerades LAN traffic going to WAN |
| Management | SSH public keys only, reachable from LAN; optional access from authenticated WireGuard sites |
| Wi-Fi | Separate AP in bridge mode by default; optional local WPA3 hostapd with a runtime password |
| Site links | Routed WireGuard with explicit remote subnets, no default route and no intersite NAT |
| Proxy | DNS FakeIP mapping plus TCP/UDP TPROXY; domain suffixes and CIDRs choose `direct` or `us` |
| IPv6 | Disabled on the router, no RA/DHCPv6, AAAA responses filtered; no accidental IPv6 WAN bypass |
| Credentials | Loaded from runtime paths; never embedded in Nix or committed to this repository |

```text
LAN clients / external AP ── br-lan ── router ── WAN
                               │       ├── direct Internet egress
                               │       ├── sing-box ── your US proxy
                               │       └── wg-sites ── remote LAN(s)
                               └── dnsmasq ── sing-box DNS mapping
```

`modules/router/` contains independent network, firewall, DNS, WireGuard, Wi-Fi, and proxy modules. `hosts/router/site.nix` is the editable site profile. `tests/` contains policy tests and an isolated five-VM integration test.

On a Linux Nix builder:

```sh
nix flake check --no-build
nix build .#checks.x86_64-linux.policy .#checks.x86_64-linux.sing-box-config
nix build .#checks.x86_64-linux.router-vm -L
```

The VM test requires a builder with the `kvm` and `nixos-test` system features. A successful evaluation is not a successful VM run; see the validation document for actual results.

`nixosConfigurations.router` deliberately appears only after a real `hosts/router/hardware-configuration.nix` is added. The example profile is evaluation-only. There is no disk partitioning script, unattended installer, or remote activation command in CI.
