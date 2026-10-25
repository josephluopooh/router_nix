{ config, lib, ... }:
let cfg = config.router; wg = cfg.wireguard; in {
  config = lib.mkIf (cfg.enable && wg.enable) {
    networking.wireguard.interfaces.wg-sites = {
      ips = [ wg.address ];
      listenPort = wg.port;
      mtu = wg.mtu;
      privateKeyFile = wg.privateKeyFile;
      allowedIPsAsRoutes = true;
      # The networkd backend refreshes endpoints at interface level.
      dynamicEndpointRefreshSeconds =
        if builtins.any (p: p.endpoint != null && builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+:[0-9]+" p.endpoint == null) wg.peers
        then wg.endpointRefreshSeconds else 0;
      peers = map (p: {
        inherit (p) publicKey allowedIPs;
        persistentKeepalive = p.keepalive;
      } // lib.optionalAttrs (p.endpoint != null) { inherit (p) endpoint; }
        // lib.optionalAttrs (p.presharedKeyFile != null) { inherit (p) presharedKeyFile; }) wg.peers;
    };
  };
}
