{ config, lib, ... }:
let cfg = config.router; wifi = cfg.wifi; in {
  config = lib.mkIf (cfg.enable && wifi.enable) {
    services.hostapd = {
      enable = true;
      radios.${wifi.interface} = {
        countryCode = wifi.country;
        inherit (wifi) band channel;
        wifi4.capabilities = [ ];
        wifi5.enable = wifi.band == "5g";
        networks.${wifi.interface} = {
          inherit (wifi) ssid;
          settings.bridge = cfg.lan.interface;
          authentication = {
            mode = "wpa3-sae";
            saePasswords = [ { passwordFile = wifi.passwordFile; } ];
          };
        };
      };
    };
    systemd.services.hostapd.after = [ "systemd-networkd.service" ];
    systemd.network.networks."25-wifi" = {
      matchConfig.Name = wifi.interface;
      networkConfig = { LinkLocalAddressing = "no"; IPv6AcceptRA = false; ConfigureWithoutCarrier = true; };
      linkConfig.RequiredForOnline = "no";
    };
  };
}
