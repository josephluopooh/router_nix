{ config, ... }:
{
  imports = [ ../../modules/router ./site.nix ./hardware-configuration.nix ];
  # The generated hardware file must contain the actual root/boot devices and drivers.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  assertions = [
    {
      assertion = config.router.management.sshKeys != [ ];
      message = "Add an SSH public key and review hosts/router/site.nix before building a real router.";
    }
    {
      assertion = config.router.wan.interface != "wan0" && config.router.lan.ports != [ "lan0" ];
      message = "Replace example WAN/LAN names with verified NIC names (or explicitly configure matching .link renames).";
    }
    {
      assertion = config.router.proxy.usDomains != [ "example.com" ];
      message = "Replace the example proxy domain policy before installing.";
    }
  ];
}
