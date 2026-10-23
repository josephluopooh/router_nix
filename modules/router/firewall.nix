{ config, lib, ... }:
let
  cfg = config.router;
  q = builtins.toJSON;
  lan = q cfg.lan.interface;
  wan = q cfg.wan.interface;
  remote = lib.concatMap (p: p.allowedIPs) cfg.wireguard.peers;
  bypass = lib.unique (cfg.proxy.bypassCIDRs ++ [ cfg.lan.subnet ] ++ remote);
  set = xs: "{ ${lib.concatStringsSep ", " xs} }";
in {
  config = lib.mkIf cfg.enable {
    boot.kernelModules = lib.optionals cfg.proxy.enable [ "nft_tproxy" "nf_tproxy_ipv4" ];
    networking.nftables = {
      enable = true;
      tables.router = {
        family = "inet";
        content = ''
          set bypass4 { type ipv4_addr; flags interval; auto-merge; elements = ${set bypass}; }
          ${lib.optionalString (remote != [ ]) ''
          set sites4 { type ipv4_addr; flags interval; auto-merge; elements = ${set remote}; }
          ''}
          chain input {
            type filter hook input priority filter; policy drop;
            iifname "lo" accept
            meta nfproto ipv6 drop
            ct state invalid drop
            ct state established,related accept
            iifname ${wan} udp sport 67 udp dport 68 accept
            iifname ${lan} udp sport 68 udp dport 67 accept
            iifname ${lan} ip saddr != ${cfg.lan.subnet} drop
            iifname ${lan} tcp dport { 22, 53 } accept
            iifname ${lan} udp dport 53 accept
            iifname ${lan} ip protocol icmp accept
            ${lib.optionalString cfg.proxy.enable ''
            iifname ${lan} meta mark 0x1 meta l4proto { tcp, udp } accept
            ''}
            ${lib.optionalString cfg.wireguard.enable ''
            iifname ${wan} udp dport ${toString cfg.wireguard.port} accept
            ${lib.optionalString cfg.management.fromWireguard ''
            iifname "wg-sites" tcp dport 22 accept
            iifname "wg-sites" ip protocol icmp accept
            ''}
            ''}
            ip protocol icmp icmp type { destination-unreachable, time-exceeded, parameter-problem } accept
          }
          chain forward {
            type filter hook forward priority filter; policy drop;
            meta nfproto ipv6 drop
            iifname ${lan} ip saddr != ${cfg.lan.subnet} drop
            ct state invalid drop
            ${lib.optionalString cfg.proxy.enable ''
            # Never leak FakeIP traffic or unhandled public TCP/UDP to the WAN.
            ip daddr 198.18.0.0/15 drop
            iifname ${lan} oifname ${wan} meta l4proto { tcp, udp } ip daddr != @bypass4 drop
            ''}
            ct state established,related accept
            iifname ${lan} oifname ${wan} accept
            ${lib.optionalString (cfg.wireguard.enable && remote != [ ]) ''
            iifname ${lan} oifname "wg-sites" ip daddr @sites4 accept
            iifname "wg-sites" oifname ${lan} ip saddr @sites4 ip daddr ${cfg.lan.subnet} accept
            iifname "wg-sites" oifname "wg-sites" ip saddr @sites4 ip daddr @sites4 accept
            ''}
          }
          chain output {
            type filter hook output priority filter; policy accept;
            meta nfproto ipv6 drop
          }
          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;
            oifname ${wan} ip saddr ${cfg.lan.subnet} masquerade
          }
          ${lib.optionalString cfg.dns.forceLanDNS ''
          chain dns_redirect {
            type nat hook prerouting priority dstnat; policy accept;
            iifname ${lan} ip saddr ${cfg.lan.subnet} meta l4proto { tcp, udp } th dport 53 redirect to :53
          }
          ''}
          ${lib.optionalString cfg.proxy.enable ''
          chain transparent {
            type filter hook prerouting priority mangle; policy accept;
            iifname != ${lan} return
            meta nfproto != ipv4 return
            ip saddr != ${cfg.lan.subnet} return
            fib daddr type local return
            # DNS goes to dnsmasq, then sing-box DNS. DHCP stays local.
            meta l4proto { tcp, udp } th dport { 53, 67, 68 } return
            ip daddr @bypass4 return
            meta l4proto { tcp, udp } tproxy ip to :7893 meta mark set 0x1 accept
          }
          ''}
        '';
      };
    };
    systemd.network.networks."05-proxy-loopback" = lib.mkIf cfg.proxy.enable {
      matchConfig.Name = "lo";
      routes = [ { Destination = "0.0.0.0/0"; Type = "local"; Table = 100; } ];
      routingPolicyRules = [ { FirewallMark = 1; Priority = 100; Table = 100; Family = "ipv4"; } ];
      linkConfig.RequiredForOnline = "no";
    };
  };
}
