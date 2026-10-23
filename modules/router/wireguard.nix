{ config, lib, ... }:
let cfg = config.router; wg = cfg.wireguard; in {
  config = lib.mkIf (cfg.enable && wg.enable) {
    networking.wireguard.interfaces.wg-sites = {
      ips = [ wg.address ];
      listenPort = wg.port;
      mtu = wg.mtu;
      privateKeyFile = wg.privateKeyFile;
      allowedIPsAsRoutes = true;
      peers = map (p: {
        inherit (p) publicKey allowedIPs;
        persistentKeepalive = p.keepalive;
      } // lib.optionalAttrs (p.endpoint != null) { inherit (p) endpoint; }
        // lib.optionalAttrs (p.presharedKeyFile != null) { inherit (p) presharedKeyFile; }) wg.peers;
    };
  };
}
