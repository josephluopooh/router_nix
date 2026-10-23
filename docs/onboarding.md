# Onboard the mini PC

Perform installation with a local console, a NixOS USB installer, and a separate test client. Keep the existing router available until all checks pass. These instructions describe operations on the intended mini PC; nothing in this repository automatically runs them.

## Record the real values

Fill in the following before replacing a working router:

| Item | Where it goes |
| --- | --- |
| CPU/NIC drivers, disk UUIDs, boot partition, UEFI versus BIOS | Generated `hosts/router/hardware-configuration.nix` and bootloader options |
| Physical WAN/LAN mapping, stable interface names or MAC-based `.link` rules | `router.wan.interface`, `router.lan.ports` |
| ISP DHCP/static address, gateway, VLAN/PPPoE and MTU | WAN profile and any extra NixOS link modules |
| Unique RFC1918 `/24` LAN per site and DHCP range | `router.lan` |
| Your SSH public key | `router.management.sshKeys` |
| Direct/US domain suffixes, IP networks, default route | `router.proxy` |
| Real proxy protocol, endpoint, authentication, TLS server name | Runtime outbound JSON |
| Site tunnel IPs, LAN routes, peer public keys and reachable endpoints | `router.wireguard` at every site |
| Optional AP-capable radio, actual country and channel | `router.wifi` |

Use `ip -br link`, `ip -br address`, `ethtool -i <interface>`, and the physical port LEDs to identify NICs. Verify MAC addresses across reboot. Do not guess which port is WAN. Check that WAN and all site LAN/tunnel ranges do not conflict, especially when WAN itself uses RFC1918 addressing.

## Prepare the configuration

1. Clone this repository on a Linux Nix builder or onto the mini PC's installer environment. The build can happen in Codex cloud/CI; hardware discovery and eventual installation must target the actual mini PC.
2. Partition and mount the intended disks using the NixOS installation manual for your hardware. No disk names are supplied here because that would risk the wrong disk. Once mounted at `/mnt`, run `nixos-generate-config --root /mnt` on that mini PC. Copy only the generated `hardware-configuration.nix` into `hosts/router/`.
3. Edit `hosts/router/site.nix` using the table above. Remove `example.com`; leave the US domain list empty if you have no policy yet. Insert your real SSH public key. Replace the placeholder NIC names. The production configuration asserts these steps are complete.
4. Review `hosts/router/default.nix`: it assumes UEFI and systemd-boot. For BIOS hardware, replace those bootloader options with a verified GRUB configuration. Review generated storage and initrd drivers. Set the appropriate timezone.
5. Start with an external AP or wired client. Leave hostapd and WireGuard disabled until their parameters and runtime secrets are ready. If the proxy is enabled, provision its outbound before boot; otherwise set `router.proxy.enable = false` for an explicitly direct first-boot router.
6. Add the hardware file and edited public configuration to Git so flakes can see them. Keep all secret files outside the checkout.

```sh
git add hosts/router
nix eval --json .#nixosConfigurations.router.config.router | python3 scripts/validate-site.py
nix flake check --no-build
nix build .#nixosConfigurations.router.config.system.build.toplevel -L
```

The build also runs site validation and nftables' packaged checker. Run the policy/schema checks and VM test from the README on a capable Linux builder. A successful build does not prove NIC names, Wi-Fi capabilities, the ISP connection, or real proxy credentials.

## Provision and install deliberately

Follow [secrets](secrets.md) first. If using persistent root-owned secret files, place them under the target's `/mnt/var/lib/router-secrets/` during installation and configure the matching paths without `/mnt`. If using `/run/secrets`, arrange a boot-time secret provisioner before services start; `/run` is ephemeral.

After verifying the disk, NICs, credentials, SSH key, and console access, the standard installation command on the mini PC is:

```sh
sudo nixos-install --root /mnt --flake .#router
```

Reboot with WAN disconnected and attach the test client to LAN. Expect a DHCP address in the site's configured range, gateway/DNS at `<prefix>.1`, and SSH accessible with your key. Check `networkctl`, `systemctl --failed`, and `journalctl -b -u dnsmasq -u router-proxy`. Only then attach WAN.

## Verify each function

- LAN: renew the test client's DHCP lease; check its address, default route, DNS, and local `home.arpa` name resolution.
- WAN: check the WAN lease or static route and router-originated name resolution. Test an external real-IP ping from LAN.
- DNS/proxy: run `dig @<router-LAN-IP> <selected-domain> A`. Transparent mode should return `198.18.x.x` or `198.19.x.x`. Use a domain in the direct list and another in the US list and verify each server-observed egress IP with a service you control or trust. Do not infer geography merely from the tag.
- Management: verify SSH on LAN; from a genuinely external network verify WAN TCP 22/53/7893 and UDP 53 are closed. Only the intended WireGuard port should accept new WAN traffic.
- Sites: enable reciprocal peers, inspect `wg show`, then ping and access a remote LAN service in both directions. Remote service logs should see the original LAN source address. Avoid overlapping AllowedIPs. Confirm access when one WAN reconnects.
- Failure: locally stop `router-proxy`, verify selected traffic cannot escape directly, and verify LAN SSH and site links still work. Restart it afterward.
- Wi-Fi: check `iw list` for AP mode and `iw reg get` before enabling hostapd with the correct country. Verify association, DHCP, and recovery via the wired port. Physical radio operation is not simulated by the VM test.

For later changes, keep a console or second management session open, build first, and use `sudo nixos-rebuild test --flake .#router`. Validate connectivity before making the generation persistent with `sudo nixos-rebuild switch --flake .#router`. `test` is temporary until reboot but is not an automatic timed rollback. See [recovery](recovery.md).
