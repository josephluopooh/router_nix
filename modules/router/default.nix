{ config, lib, pkgs, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.router;
  interface = types.strMatching "[a-zA-Z0-9_.-]{1,15}";
  strings = default: mkOption { type = types.listOf types.str; inherit default; };
  secret = default: mkOption {
    type = types.strMatching "/[^\n]+";
    inherit default;
    description = "Absolute runtime secret path; never use a Nix path or builtins.readFile.";
  };
in {
  imports = [ ./network.nix ./firewall.nix ./dns.nix ./wireguard.nix ./wifi.nix ./proxy.nix ];
  options.router = {
    enable = lib.mkEnableOption "the IPv4 router";
    wan = {
      interface = mkOption { type = interface; default = "wan0"; };
      dhcp = mkOption { type = types.bool; default = true; };
      address = mkOption { type = types.str; default = ""; description = "Static WAN IPv4/prefix, if DHCP is disabled."; };
      gateway = mkOption { type = types.str; default = ""; };
    };
    lan = {
      interface = mkOption { type = interface; default = "br-lan"; };
      ports = mkOption { type = types.listOf interface; default = [ "lan0" ]; };
      prefix = mkOption { type = types.strMatching "[0-9]+\\.[0-9]+\\.[0-9]+"; default = "192.168.10"; description = "First three octets of the site's non-overlapping /24 LAN."; };
      address = mkOption { type = types.str; readOnly = true; default = "${cfg.lan.prefix}.1"; };
      subnet = mkOption { type = types.str; readOnly = true; default = "${cfg.lan.prefix}.0/24"; };
      dhcpStart = mkOption { type = types.ints.between 2 254; default = 100; };
      dhcpEnd = mkOption { type = types.ints.between 2 254; default = 199; };
      domain = mkOption { type = types.strMatching "[a-zA-Z0-9.-]+"; default = "home.arpa"; };
    };
    management = {
      sshKeys = strings [ ];
      fromWireguard = mkOption { type = types.bool; default = false; };
    };
    dns = {
      upstream = strings [ "1.1.1.1" "9.9.9.9" ];
      forceLanDNS = mkOption { type = types.bool; default = true; };
    };
    wireguard = {
      enable = lib.mkEnableOption "routed site-to-site WireGuard";
      address = mkOption { type = types.str; default = "10.77.0.1/24"; };
      port = mkOption { type = types.port; default = 51820; };
      mtu = mkOption { type = types.ints.between 1280 1500; default = 1380; };
      privateKeyFile = secret "/run/secrets/router-wireguard";
      peers = mkOption {
        default = [ ];
        type = types.listOf (types.submodule {
          options = {
            publicKey = mkOption { type = types.str; };
            endpoint = mkOption { type = types.nullOr types.str; default = null; };
            allowedIPs = strings [ ];
            presharedKeyFile = mkOption { type = types.nullOr types.str; default = null; };
            keepalive = mkOption { type = types.ints.between 0 65535; default = 25; };
          };
        });
      };
    };
    wifi = {
      enable = lib.mkEnableOption "a hostapd access point bridged onto LAN";
      interface = mkOption { type = interface; default = "wlan0"; };
      country = mkOption { type = types.str; default = ""; };
      ssid = mkOption { type = types.str; default = "Router LAN"; };
      channel = mkOption { type = types.ints.between 1 196; default = 6; };
      band = mkOption { type = types.enum [ "2g" "5g" ]; default = "2g"; };
      passwordFile = secret "/run/secrets/router-wifi";
    };
    proxy = {
      enable = lib.mkEnableOption "LAN-transparent sing-box policy routing";
      outboundFile = secret "/run/secrets/router-us-outbound.json";
      defaultRoute = mkOption { type = types.enum [ "direct" "us" ]; default = "direct"; };
      directDomains = strings [ ];
      usDomains = strings [ ];
      directCIDRs = strings [ ];
      usCIDRs = strings [ ];
      # These addresses must never enter the proxy; remote WireGuard networks are added automatically.
      bypassCIDRs = strings [ "0.0.0.0/8" "10.0.0.0/8" "100.64.0.0/10" "127.0.0.0/8" "169.254.0.0/16" "172.16.0.0/12" "192.168.0.0/16" "224.0.0.0/4" "240.0.0.0/4" ];
      settings = mkOption { type = types.attrs; default = { }; internal = true; };
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      { assertion = cfg.lan.ports != [ ]; message = "router.lan.ports must contain a wired recovery/management port."; }
      { assertion = !(builtins.elem cfg.wan.interface (cfg.lan.ports ++ [ cfg.lan.interface cfg.wifi.interface ])); message = "WAN must be separate from LAN and Wi-Fi."; }
      { assertion = !(builtins.elem cfg.lan.interface cfg.lan.ports); message = "LAN bridge cannot be its own member."; }
      { assertion = cfg.lan.dhcpStart <= cfg.lan.dhcpEnd; message = "DHCP range must be ordered."; }
      { assertion = cfg.dns.upstream != [ ]; message = "At least one explicit upstream DNS IPv4 address is required."; }
      { assertion = cfg.wan.dhcp || (cfg.wan.address != "" && cfg.wan.gateway != ""); message = "Static WAN requires address and gateway."; }
      { assertion = !cfg.wireguard.enable || cfg.wireguard.peers != [ ]; message = "Enabled WireGuard requires at least one peer."; }
      { assertion = !cfg.wifi.enable || builtins.match "[A-Z]{2}" cfg.wifi.country != null; message = "Set the actual two-letter country code before enabling hostapd."; }
      { assertion = !cfg.wifi.enable || !(builtins.elem cfg.wifi.interface cfg.lan.ports); message = "hostapd manages the Wi-Fi bridge member; omit it from wired LAN ports."; }
      { assertion = builtins.all (p: !(builtins.elem "0.0.0.0/0" p.allowedIPs)) cfg.wireguard.peers; message = "Site WireGuard must use specific remote subnets, never a default route."; }
    ];
    services.openssh = {
      enable = true;
      openFirewall = false;
      settings = { PasswordAuthentication = false; KbdInteractiveAuthentication = false; PermitRootLogin = "prohibit-password"; };
    };
    users.users.root.openssh.authorizedKeys.keys = cfg.management.sshKeys;
    system.extraDependencies = [ (pkgs.runCommand "router-site-validation" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python3 ${../../scripts/validate-site.py} ${pkgs.writeText "router-site.json" (builtins.toJSON cfg)}
      touch $out
    '') ];
    environment.systemPackages = with pkgs; [ nftables dnsmasq wireguard-tools iproute2 tcpdump ethtool bind sing-box ];
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
  };
}
