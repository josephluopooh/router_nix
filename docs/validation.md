# Validation evidence

Cloud implementation and checks performed on 2026-10-23. This document separates evaluation, executable configuration checks, and real network tests.

## Cloud environment

- Work was performed in a separate `/workspace/router_nix` clone of the verified public repository. The repository had no commits when cloned. Preconfigured unrelated repositories were not edited.
- Nix 2.26.3 was extracted from Debian's Nix package into `/workspace/router-nix-tools`; no system installation or user-computer access was required. PRoot maps a workspace-owned store to `/nix` for evaluation.
- nixpkgs was fetched at `da6dc0e7b26060f2f71ce3ef7088fb56ee44fa36`. Its computed source NAR hash matches `flake.lock`: `sha256-MlvRfa1O5Cqc2/a+gG+l9TSuowEoCKCmrJ1d9oAVm0I=`.
- The ordinary cloud proxy blocks `releases.nixos.org` and `cache.nixos.org` with HTTP 403, including an attempted approved download. No `/dev/kvm` exists. Nested user-namespace setup is unavailable. No host interfaces, routes, sysctls, or firewall rules were changed.

## Executed checks

| Check | Result |
| --- | --- |
| Python policy/credential validator suite | Passed: 6 test methods, with multiple rejection subcases |
| Evaluated example site through NixOS | Passed; no failed NixOS assertions |
| `nix flake check --no-build` | Passed with a local Git input override of the exact pinned nixpkgs revision; lock file unchanged |
| Optional-hostapd NixOS system derivation | Evaluated successfully; no physical radio test |
| Complete example NixOS system derivation | Evaluated successfully; not built in this cloud |
| Five-VM test derivation | Evaluated successfully; VM test not executed in this cloud |
| Generated site manifest through Python validation | Passed |
| Rendered proxy config through official sing-box 1.13.19 `check` | Passed |
| Exact rendered sing-box config in a network-isolated container | Started successfully; an A query to its DNS listener returned `198.18.0.2`. This checks startup and FakeIP DNS, not LAN packet interception. |
| Generated dnsmasq config through dnsmasq 2.91 `--test` | Passed |
| Generated nftables rules through nftables 1.1.3 `--check`, in a `--network none` container | Full check blocked: cloud kernel lacks FIB and TPROXY expressions. It reports `No such file or directory` for those two statements. The same rules with only those two unsupported statements omitted pass the kernel check. This is not a full firewall validation pass. |

The local tool versions for dnsmasq and nftables are distribution binaries, not a realization of the pinned nixpkgs packages. The sing-box binary has extra upstream build tags compared with nixpkgs; the configuration uses features present in both. CI checks the actual pinned packages.

## GitHub Actions execution

For implementation commit [`553e407`](https://github.com/josephluopooh/router_nix/commit/553e407c2bff76fd3196571fbaf79efdd6a73493), [workflow run 39982556348](https://github.com/josephluopooh/router_nix/actions/runs/39982556348) passed its `config` job. This independently ran `nix flake check --no-build` against the committed lock file, then built the configuration-evaluation, Python policy, and pinned sing-box schema checks. The runner confirmed `/dev/kvm` exists for the separate VM job.

The first VM run **failed** at 16:13 UTC while trying the direct-domain HTTP request. DNS and LAN interception had reached sing-box, which timed out connecting to `198.51.100.10:8080`. The fixture declared its fake public addresses on loopback, but its scripted-networking guest never started the loopback address service. Its Ethernet address was configured normally. The fixture now places those fake public addresses on that Ethernet interface and checks the origin from both the Internet guest and router before testing LAN policy. No production firewall rule was relaxed. Network retries are bounded at 60 seconds, with addresses, routes, listeners, rules and service journals collected on failure. Replacement VM validation is required before claiming an end-to-end pass.

The generated configurations for both test sites also passed the site validator independently in cloud.

## Automated checks provided

`nix flake check --no-build` evaluates all exposed outputs. `checks.x86_64-linux.configuration` forces the full example and optional-hostapd NixOS derivations. The Python suite rejects invalid/overlapping LAN, WAN and peer routes, conflicting domain/CIDR policy, FakeIP bypass, unsafe DNS recursion, store-resident secrets, and inappropriate proxy outbound objects. The rendered proxy configuration is checked using `pkgs.sing-box`.

`checks.x86_64-linux.router-vm` boots five isolated NixOS machines: router A, router B, a DHCP LAN client, a remote LAN client, and a fake Internet/DNS/SOCKS server. It checks DHCP, local management, WAN port blocking, IPv6 policy, policy routing, redirected DNS, FakeIP answers, direct/proxy domain and IP routing via observed source addresses, basic NAT, bidirectional WireGuard site traffic without NAT, and proxy outage/restart behavior. Its public test keys and fake Internet addresses are fixtures, not production credentials.

The GitHub workflow runs these checks on an isolated Linux runner, without router credentials or deployment steps. A written test or successfully evaluated derivation is not evidence that packets passed. The observed configuration-check result is recorded above; no VM success is claimed without its completed result.

Physical NIC identity, disk/boot layout, ISP connectivity, Wi-Fi radio/regulatory operation, real endpoint reachability, actual US egress location, and throughput require the intended hardware and real site parameters. They are intentionally not inferred from cloud tests.

## Upstream references

- [Pinned NixOS sing-box module](https://github.com/NixOS/nixpkgs/blob/da6dc0e7b26060f2f71ce3ef7088fb56ee44fa36/nixos/modules/services/networking/sing-box.nix)
- [Pinned sing-box 1.13.19 package](https://github.com/NixOS/nixpkgs/blob/da6dc0e7b26060f2f71ce3ef7088fb56ee44fa36/pkgs/by-name/si/sing-box/package.nix)
- [Pinned hostapd module](https://github.com/NixOS/nixpkgs/blob/da6dc0e7b26060f2f71ce3ef7088fb56ee44fa36/nixos/modules/services/networking/hostapd.nix)
- [sing-box TPROXY](https://sing-box.sagernet.org/configuration/inbound/tproxy/), [DNS FakeIP server](https://sing-box.sagernet.org/configuration/dns/server/fakeip/), and [routing actions](https://sing-box.sagernet.org/configuration/route/rule_action/) — live documentation may describe later versions; the pinned executable is the schema check used here.
