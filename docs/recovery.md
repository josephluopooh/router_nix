# Recovery

Keep a local keyboard/display or serial console and a known-good NixOS generation. Label the wired LAN port. Save the current site profile and an encrypted backup of runtime secrets before changing the router.

If DHCP fails, manually give a recovery client an unused address in the configured LAN `/24`, such as `<prefix>.2/24`, and connect directly to the wired LAN port. The router's address is `<prefix>.1`; SSH uses the configured public key. This depends on the bridge and NIC configuration being correct, so retain console access.

At the router console:

```sh
ip -br address
ip route
ip rule
networkctl status
systemctl --failed
journalctl -b -u systemd-networkd -u nftables -u dnsmasq -u router-proxy
nft list table inet router
wg show
```

If transparent traffic fails, check table `100`, mark rule `1`, the `router-proxy` service, and credential permissions. If DNS fails, test dnsmasq at the LAN address, sing-box DNS on `127.0.0.1:5353`, and the configured upstream separately. Router-originated DNS intentionally bypasses the LAN resolver chain.

If a site tunnel is unavailable, LAN traffic addressed to that site's configured routes remains blocked from WAN. Check systemd-networkd, the `wireguard-dynamic-refresh-wg-sites` timer, and upstream DNS; hostname endpoints refresh every `router.wireguard.endpointRefreshSeconds` (300 seconds by default). Disabling WireGuard deliberately removes site-specific routing exemptions and blocks, even if its peer list is retained.

When disabling WireGuard, reboot into the changed generation to remove its old kernel interface and routes. A networkd configuration reload alone can leave an existing virtual interface present. The disabled-site integration test explicitly removes the old interface before activating its alternate configuration.

Stopping sing-box is **not** direct-mode recovery: the firewall intentionally blocks missed public TCP/UDP and dnsmasq still forwards to sing-box. For an intentional direct-mode fallback, change `router.proxy.enable = false`, rebuild, and activate from the console. That changes DNS and interception together. Flush client DNS caches to discard FakeIP answers and reconnect applications. Keep a prebuilt direct-mode generation if rapid outage recovery is important.

For a bad activation, use the local console to run `sudo nixos-rebuild switch --rollback`, or reboot and choose the previous system generation in the boot menu. If you used `nixos-rebuild test`, reboot returns to the previously selected boot generation. If storage or the bootloader is broken, boot the NixOS installer, mount the intended system, and repair using the installation manual. Do not run a generic disk-writing command from memory.

After rollback, verify that runtime secrets still exist: NixOS generations do not restore external secret files. A Wi-Fi failure should not remove the wired recovery path. A WAN failure should not prevent LAN addressing or SSH from starting. Do not flush the whole firewall as a shortcut while WAN is connected.
