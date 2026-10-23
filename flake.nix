{
  description = "Modular x86_64 NixOS router: dnsmasq, nftables, WireGuard and sing-box";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/da6dc0e7b26060f2f71ce3ef7088fb56ee44fa36";
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      example = nixpkgs.lib.nixosSystem { inherit system; modules = [ ./tests/example.nix ]; };
      wifiExample = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./tests/example.nix ({ lib, ... }: { router.wifi = { enable = lib.mkForce true; country = lib.mkForce "US"; }; }) ];
      };
      cfg = example.config;
      manifest = pkgs.writeText "router-example.json" (builtins.toJSON cfg.router);
      base = pkgs.writeText "sing-box-base.json" (builtins.toJSON cfg.router.proxy.settings);
      fixture = pkgs.writeText "test-outbound.json" (builtins.toJSON {
        type = "socks"; tag = "us"; server = "192.0.2.2"; server_port = 1080;
      });
    in {
      nixosModules.default = import ./modules/router;
      # No fabricated hardware file: this output appears only after onboarding.
      nixosConfigurations = nixpkgs.lib.optionalAttrs (builtins.pathExists ./hosts/router/hardware-configuration.nix) {
        router = nixpkgs.lib.nixosSystem { inherit system; modules = [ ./hosts/router ]; };
      };
      formatter.${system} = pkgs.nixfmt;
      packages.${system} = {
        example-manifest = manifest;
        example-proxy-config = base;
      };
      lib = {
        exampleConfig = cfg;
        exampleManifest = cfg.router;
        exampleNftables = cfg.networking.nftables.tables.router.content;
        exampleDnsmasq = cfg.services.dnsmasq.settings;
        wifiExampleConfig = wifiExample.config;
      };
      checks.${system} = {
        configuration = assert builtins.all (a: a.assertion) cfg.assertions;
          pkgs.runCommand "router-configuration" { } ''
            # Evaluating drvPath forces the complete NixOS toplevel configuration.
            # Discard dependency context: this check evaluates, but does not build, the systems.
            echo ${builtins.unsafeDiscardStringContext cfg.system.build.toplevel.drvPath} > $out
            echo ${builtins.unsafeDiscardStringContext wifiExample.config.system.build.toplevel.drvPath} >> $out
          '';
        policy = pkgs.runCommand "router-policy-tests" { nativeBuildInputs = [ pkgs.python3 ]; } ''
          cd ${self}
          python3 -m unittest discover -s tests -v
          python3 scripts/validate-site.py ${manifest}
          touch $out
        '';
        sing-box-config = pkgs.runCommand "router-sing-box-config" { nativeBuildInputs = [ pkgs.python3 pkgs.sing-box ]; } ''
          python3 ${./scripts/render-proxy.py} ${base} ${fixture} config.json
          sing-box check -c config.json
          touch $out
        '';
        router-vm = import ./tests/router-vm.nix { inherit pkgs; };
      };
    };
}
