# Module fragment for site B; use unique site B hardware and secrets there.
# Replace both public keys and site A's endpoint. No live key is included here.
{ lib, ... }:
{
  networking.hostName = lib.mkForce "router-b";
  router.lan.prefix = lib.mkForce "192.168.20";
  router.wireguard = {
    enable = lib.mkForce true;
    address = lib.mkForce "10.77.0.2/24";
    peers = [ {
      publicKey = "REPLACE_WITH_SITE_A_PUBLIC_KEY";
      endpoint = "site-a.example.net:51820";
      allowedIPs = [ "10.77.0.1/32" "192.168.10.0/24" ];
      keepalive = 25;
    } ];
  };
  # At site A configure the reciprocal peer:
  # publicKey = "REPLACE_WITH_SITE_B_PUBLIC_KEY";
  # allowedIPs = [ "10.77.0.2/32" "192.168.20.0/24" ];
  # endpoint can be omitted for a roaming/NATed site B.
}
