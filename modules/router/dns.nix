{ config, lib, ... }:
let cfg = config.router; in {
  config = lib.mkIf cfg.enable {
    services.dnsmasq = {
      enable = true;
      resolveLocalQueries = false;
      settings = {
        interface = [ cfg.lan.interface "lo" ];
        bind-dynamic = true;
        domain-needed = true;
        bogus-priv = true;
        no-resolv = true;
        no-poll = true;
        server = if cfg.proxy.enable then [ "127.0.0.1#5353" ] else cfg.dns.upstream;
        local = "/${cfg.lan.domain}/";
        domain = cfg.lan.domain;
        expand-hosts = true;
        dhcp-authoritative = true;
        dhcp-range = "${cfg.lan.prefix}.${toString cfg.lan.dhcpStart},${cfg.lan.prefix}.${toString cfg.lan.dhcpEnd},255.255.255.0,12h";
        dhcp-option = [ "option:router,${cfg.lan.address}" "option:dns-server,${cfg.lan.address}" ];
        dhcp-leasefile = "/var/lib/dnsmasq/dnsmasq.leases";
        filter-AAAA = true;
        # sing-box owns mapping lifetimes; don't cache FakeIP answers in a second daemon.
        cache-size = if cfg.proxy.enable then 0 else 1000;
      };
    };
    systemd.services.dnsmasq = {
      after = [ "systemd-networkd.service" ];
      serviceConfig.StateDirectory = "dnsmasq";
    };
  };
}
