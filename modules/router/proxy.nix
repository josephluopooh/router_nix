{ config, lib, pkgs, ... }:
let
  cfg = config.router;
  proxy = cfg.proxy;
  rule = field: values: outbound: lib.optional (values != [ ]) {
    ${field} = values;
    action = "route";
    inherit outbound;
  };
  settings = {
    log = { level = "warn"; timestamp = true; };
    inbounds = [
      { type = "tproxy"; tag = "lan"; listen = "0.0.0.0"; listen_port = 7893; }
      { type = "direct"; tag = "dns-in"; listen = "127.0.0.1"; listen_port = 5353; }
    ];
    outbounds = [ { type = "direct"; tag = "direct"; } ];
    dns = {
      servers = [
        { type = "udp"; tag = "upstream"; server = builtins.head cfg.dns.upstream; }
        { type = "fakeip"; tag = "fakeip"; inet4_range = "198.18.0.0/15"; }
      ];
      rules = [ { query_type = [ "A" ]; action = "route"; server = "fakeip"; } ];
      final = "upstream";
      strategy = "ipv4_only";
    };
    route = {
      default_domain_resolver = "upstream";
      rules = [
        { inbound = [ "dns-in" ]; action = "hijack-dns"; }
        { action = "sniff"; timeout = "300ms"; }
      ]
      ++ rule "domain_suffix" proxy.directDomains "direct"
      ++ rule "domain_suffix" proxy.usDomains "us"
      ++ [ { action = "resolve"; strategy = "ipv4_only"; } ]
      ++ rule "ip_cidr" proxy.directCIDRs "direct"
      ++ rule "ip_cidr" proxy.usCIDRs "us";
      final = proxy.defaultRoute;
    };
    experimental.cache_file = {
      enabled = true;
      path = "/var/lib/router-proxy/cache.db";
      store_fakeip = true;
    };
  };
  base = pkgs.writeText "router-sing-box-base.json" (builtins.toJSON settings);
  prepare = pkgs.writeShellScript "router-proxy-prepare" ''
    set -eu
    umask 077
    ${pkgs.python3}/bin/python3 ${../../scripts/render-proxy.py} \
      ${base} "$CREDENTIALS_DIRECTORY/outbound.json" /run/router-proxy/config.json
    ${pkgs.sing-box}/bin/sing-box check -c /run/router-proxy/config.json
  '';
in {
  config = lib.mkIf (cfg.enable && proxy.enable) {
    router.proxy.settings = settings;
    users.groups.router-proxy = { };
    users.users.router-proxy = { isSystemUser = true; group = "router-proxy"; };
    systemd.services.router-proxy = {
      description = "LAN transparent policy proxy (sing-box)";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" "nftables.service" "systemd-networkd.service" ];
      serviceConfig = {
        User = "router-proxy";
        Group = "router-proxy";
        LoadCredential = [ "outbound.json:${proxy.outboundFile}" ];
        ExecStartPre = prepare;
        ExecStart = "${pkgs.sing-box}/bin/sing-box run -c /run/router-proxy/config.json";
        Restart = "on-failure";
        RestartSec = 3;
        RuntimeDirectory = "router-proxy";
        RuntimeDirectoryMode = "0700";
        StateDirectory = "router-proxy";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/router-proxy";
        UMask = "0077";
        AmbientCapabilities = [ "CAP_NET_ADMIN" ];
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_UNIX" "AF_NETLINK" ];
      };
    };
  };
}
