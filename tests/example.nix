# Evaluation fixture only; never install this onto hardware.
{ lib, ... }:
{
  imports = [ ../modules/router ../hosts/router/site.nix ];
  boot.loader.grub.enable = false;
  fileSystems."/" = { device = "/dev/disk/by-label/TEST_ONLY"; fsType = "ext4"; };
  router = {
    wan.interface = lib.mkForce "eth1";
    lan.ports = lib.mkForce [ "eth2" ];
  };
}
