{ config, lib, ... }:
let cfg = config.router; in {
  config = lib.mkIf cfg.enable {
    networking = {
      useNetworkd = true;
      useDHCP = false;
      enableIPv6 = false;
      networkmanager.enable = false;
      dhcpcd.enable = false;
      nameservers = cfg.dns.upstream;
      # This repository owns forwarding/filtering/NAT in one nftables table.
      firewall.enable = false;
      nat.enable = false;
    };
    services.resolved.enable = false;
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv4.conf.all.rp_filter" = 0;
      "net.ipv4.conf.default.rp_filter" = 0;
      "net.ipv4.conf.all.send_redirects" = 0;
      "net.ipv4.conf.default.send_redirects" = 0;
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv6.conf.all.disable_ipv6" = 1;
      "net.ipv6.conf.default.disable_ipv6" = 1;
    };
    systemd.network = {
      enable = true;
      netdevs."20-lan" = { netdevConfig = { Kind = "bridge"; Name = cfg.lan.interface; }; };
      networks = {
        "10-wan" = {
          matchConfig.Name = cfg.wan.interface;
          networkConfig = { DHCP = if cfg.wan.dhcp then "ipv4" else "no"; IPv6AcceptRA = false; LinkLocalAddressing = "no"; };
          dhcpV4Config = { UseDNS = false; UseNTP = false; UseRoutes = true; RouteMetric = 100; };
          address = lib.optional (!cfg.wan.dhcp) cfg.wan.address;
          routes = lib.optional (!cfg.wan.dhcp) { Gateway = cfg.wan.gateway; };
          linkConfig.RequiredForOnline = "no";
        };
        "20-lan-ports" = {
          matchConfig.Name = cfg.lan.ports;
          networkConfig = { Bridge = cfg.lan.interface; LinkLocalAddressing = "no"; IPv6AcceptRA = false; };
          linkConfig.RequiredForOnline = "no";
        };
        "30-lan" = {
          matchConfig.Name = cfg.lan.interface;
          address = [ "${cfg.lan.address}/24" ];
          networkConfig = { ConfigureWithoutCarrier = true; LinkLocalAddressing = "no"; IPv6AcceptRA = false; };
          linkConfig.RequiredForOnline = "no";
        };
      };
      # Management must boot even with the WAN cable disconnected.
      wait-online.enable = false;
    };
  };
}
