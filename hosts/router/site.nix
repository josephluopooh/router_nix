# Replace every hardware/site-specific example before onboarding.
{
  networking.hostName = "router-a";
  time.timeZone = "Etc/UTC";
  system.stateVersion = "26.05";
  router = {
    enable = true;
    wan = { interface = "wan0"; dhcp = true; };
    lan = { ports = [ "lan0" ]; prefix = "192.168.10"; domain = "home.arpa"; };
    management.sshKeys = [ ]; # Insert your real SSH public key, never a private key.
    dns.upstream = [ "1.1.1.1" "9.9.9.9" ];
    proxy = {
      enable = true;
      outboundFile = "/run/secrets/router-us-outbound.json";
      defaultRoute = "direct";
      directDomains = [ ];
      usDomains = [ "example.com" ]; # EXAMPLE: replace with your policy.
      directCIDRs = [ ];
      usCIDRs = [ ];
    };
    wireguard = {
      enable = false;
      address = "10.77.0.1/24";
      privateKeyFile = "/run/secrets/router-wireguard";
      # Enable after copying/adapting docs/site-b.nix and exchanging public keys.
      peers = [ ];
    };
    wifi = {
      enable = false; # Default: connect a separate AP to a LAN port in bridge/AP mode.
      interface = "wlan0";
      country = ""; # Set the actual country, verify AP support with `iw list`.
      ssid = "Router LAN";
      passwordFile = "/run/secrets/router-wifi";
    };
  };
}
