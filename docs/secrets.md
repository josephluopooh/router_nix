# Runtime secrets

No production private key, password, token, or proxy URL belongs in Nix source, Git, command output, or the world-readable Nix store. Options ending in `File` are **quoted strings**, not Nix paths. Never use `builtins.readFile` on a secret or interpolate a secret into a derivation.

Default paths are `/run/secrets/router-us-outbound.json`, `/run/secrets/router-wireguard`, and `/run/secrets/router-wifi`. `/run` is cleared on reboot. Use an existing encrypted secret provisioner such as sops-nix/agenix, or explicitly change the options to root-owned persistent paths under `/var/lib/router-secrets`. The repository does not add an encryption key or assume a secret-management service.

For a simple console-provisioned installation, create `/var/lib/router-secrets` with mode `0700`, create the files with mode `0600` owned by root, and set:

```nix
router.proxy.outboundFile = "/var/lib/router-secrets/us.json";
router.wireguard.privateKeyFile = "/var/lib/router-secrets/wg.key";
router.wifi.passwordFile = "/var/lib/router-secrets/wifi-password";
```

Store backups encrypted. Provision before the first service start. sing-box uses systemd `LoadCredential`, merges the outbound into a private runtime config, and validates it using the pinned binary before starting. Missing or malformed credentials cause startup failure, with no automatic direct fallback. WireGuard and hostapd read their root-owned runtime files through their NixOS service modules. If a separate secret service creates these files, add the appropriate `requires`/`after` dependency for each consuming service.

The proxy credential file contains **one outbound object**, with tag `us`, using a protocol supported by sing-box 1.13.19. For example, replace all capitalized values in this Trojan/TLS outline outside the repository:

```json
{
  "type": "trojan",
  "tag": "us",
  "server": "YOUR_REAL_PROXY_HOSTNAME",
  "server_port": 443,
  "password": "YOUR_REAL_PASSWORD",
  "tls": {
    "enabled": true,
    "server_name": "YOUR_CERTIFICATE_HOSTNAME"
  }
}
```

Use the real provider's exact supported protocol and fields; the outline is not a working subscription. Certificate verification must remain enabled. The renderer rejects `direct` as the US proxy, insecure TLS, and outbound detour/mark overrides. It intentionally accepts only one remote outbound; selectors and multiple fallback nodes require an explicit extension and tests. It does not convert subscription URLs.

Generate each WireGuard private key locally on its router with `umask 077; wg genkey > <private-file>` and obtain only the corresponding public key with `wg pubkey < <private-file>`. Exchange public keys between sites. Optional preshared keys are also runtime files. The VM test contains deliberately insecure fixed test keys; they provide reproducibility and must never be reused outside its isolated network.

The hostapd password file contains the chosen SAE password, not a Nix expression or JSON. Keep it root-readable only. Restart the relevant service after rotating runtime credentials; verify site handshakes and proxy egress after rotation.
