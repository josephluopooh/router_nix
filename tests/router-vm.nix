{ pkgs }:
let
  # PUBLIC, INSECURE, TEST-ONLY keys. Never use either on a real router.
  keyA = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=";
  pubA = "pOCSkrZRwni5dyxWn1+puxPZBrRqtoyd+dwrRAn4ogk=";
  keyB = "AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=";
  pubB = "zo060cy2M+x7cMF4FKXHbs0CloUFDTRHRboFhw5YfVk=";
  common = { lib, ... }: {
    system.stateVersion = "26.05";
    virtualisation.memorySize = 384;
    networking.useDHCP = false;
    environment.systemPackages = with pkgs; [ curl bind netcat-openbsd wireguard-tools tcpdump ];
  };
  site = { address, prefix, key, peerKey, peerIP, peerLAN, wanIP, extraRoutes ? [ ] }: { lib, ... }: {
    imports = [ common ../modules/router ];
    router = {
      enable = true;
      wan = { interface = "eth1"; dhcp = false; address = "${wanIP}/24"; gateway = "192.0.2.254"; };
      lan = { ports = [ "eth2" ]; inherit prefix; };
      dns.upstream = [ "192.0.2.254" ];
      wireguard = {
        enable = true;
        inherit address;
        privateKeyFile = "/etc/test-wg-key";
        peers = [ {
          publicKey = peerKey;
          endpoint = if peerIP == null then null else "${peerIP}:51820";
          allowedIPs = [ "${if prefix == "192.168.10" then "10.77.0.2" else "10.77.0.1"}/32" "${peerLAN}.0/24" ] ++ extraRoutes;
        } ];
      };
    };
    environment.etc."test-wg-key" = { text = key; mode = "0600"; };
  };
in pkgs.testers.runNixOSTest {
  name = "router-routing-and-proxy";
  nodes = {
    router = { lib, ... }: {
      imports = [ (site {
        address = "10.77.0.1/24"; prefix = "192.168.10"; key = keyA; peerKey = pubB;
        peerIP = null; peerLAN = "192.168.20"; wanIP = "192.0.2.1";
        extraRoutes = [ "198.51.100.12/32" ];
      }) ];
      virtualisation.interfaces = { eth1.vlan = 1; eth2.vlan = 2; };
      router.proxy = {
        enable = true;
        outboundFile = "/etc/test-outbound.json";
        directDomains = [ "direct.test" ];
        usDomains = [ "proxy.test" ];
        usCIDRs = [ "198.51.100.11/32" ];
      };
      environment.etc."test-outbound.json".text = builtins.toJSON {
        type = "socks"; tag = "us"; server = "192.0.2.254"; server_port = 1080;
      };
      specialisation.without-sites.configuration = {
        # Keep the peer list while disabling sites, as during staged onboarding.
        router.wireguard.enable = lib.mkForce false;
        router.proxy.usCIDRs = [ "198.51.100.12/32" ];
      };
    };
    siteb = { ... }: {
      imports = [ (site {
        address = "10.77.0.2/24"; prefix = "192.168.20"; key = keyB; peerKey = pubA;
        peerIP = "site-a.test"; peerLAN = "192.168.10"; wanIP = "192.0.2.2";
      }) ];
      router.wireguard.endpointRefreshSeconds = 2;
      systemd.timers.wireguard-dynamic-refresh-wg-sites.timerConfig.AccuracySec = "1s";
      virtualisation.interfaces = { eth1.vlan = 1; eth2.vlan = 3; };
    };
    client = { ... }: {
      imports = [ common ];
      virtualisation.interfaces.eth1.vlan = 2;
      networking.interfaces.eth1.useDHCP = true;
      networking.firewall.enable = false;
    };
    remote = { ... }: {
      imports = [ common ];
      virtualisation.interfaces.eth1.vlan = 3;
      networking.interfaces.eth1.ipv4.addresses = [ { address = "192.168.20.50"; prefixLength = 24; } ];
      networking.defaultGateway = "192.168.20.1";
      networking.firewall.enable = false;
    };
    internet = { ... }: {
      imports = [ common ];
      virtualisation.interfaces.eth1.vlan = 1;
      # The scripted backend does not reliably activate extra loopback addresses.
      # Put the simulated public hosts on the configured NIC and verify them below.
      networking.interfaces.eth1.ipv4.addresses = [
        { address = "192.0.2.254"; prefixLength = 24; }
        { address = "198.51.100.10"; prefixLength = 32; }
        { address = "198.51.100.11"; prefixLength = 32; }
        { address = "198.51.100.12"; prefixLength = 32; }
      ];
      networking.firewall.enable = false;
      services.dnsmasq = {
        enable = true;
        resolveLocalQueries = false;
        settings = { no-resolv = true; address = [ "/test/198.51.100.10" ]; addn-hosts = "/run/site-endpoints"; };
      };
      systemd.services.dnsmasq.preStart = ''
        test -e /run/site-endpoints || echo '192.0.2.1 site-a.test' > /run/site-endpoints
      '';
      services.sing-box = {
        enable = true;
        settings = {
          inbounds = [ { type = "socks"; listen = "0.0.0.0"; listen_port = 1080; } ];
          outbounds = [ { type = "direct"; tag = "direct"; inet4_bind_address = "192.0.2.254"; } ];
          dns.servers = [ { type = "udp"; tag = "dns"; server = "127.0.0.1"; } ];
          route.default_domain_resolver = "dns";
        };
      };
      systemd.services.origin = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 ${pkgs.writeText "origin.py" ''
          from http.server import BaseHTTPRequestHandler, HTTPServer
          class Handler(BaseHTTPRequestHandler):
              def do_GET(self):
                  self.send_response(200)
                  self.end_headers()
                  self.wfile.write(self.client_address[0].encode())
          HTTPServer(('0.0.0.0', 8080), Handler).serve_forever()
        ''}";
      };
    };
  };
  testScript = ''
    def remove_site_tunnel():
        # networkd owns this netdev. Remove its definition before deleting it so
        # the outage is stable until restore_site_tunnel explicitly recreates it.
        router.succeed("mv /etc/systemd/network/40-wg-sites.netdev /run/test-wg-sites.netdev")
        router.succeed("networkctl reload; networkctl delete wg-sites")

    def restore_site_tunnel():
        router.succeed("mv /run/test-wg-sites.netdev /etc/systemd/network/40-wg-sites.netdev; networkctl reload")
        router.wait_until_succeeds("ip route show 198.51.100.12/32 | grep wg-sites", timeout=60)

    def diagnostics():
        for machine in (router, siteb, client, remote, internet):
            for command in (
                "ip -br address; ip route show table all; ip rule; ss -lntup",
                "systemctl --failed --no-pager; nft list ruleset; wg show",
                "journalctl -b --no-pager -n 80 -u router-proxy -u sing-box -u dnsmasq -u origin -u systemd-networkd",
            ):
                try:
                    print(machine.name, command, machine.execute(command, timeout=15))
                except Exception as error:
                    print("Diagnostic collection failed:", error)

    try:
        start_all()
        router.wait_for_unit("dnsmasq.service", timeout=120)
        router.wait_for_unit("router-proxy.service", timeout=120)
        siteb.wait_for_unit("dnsmasq.service", timeout=120)
        internet.wait_for_unit("origin.service", timeout=120)
        internet.wait_for_unit("sing-box.service", timeout=120)
        internet.wait_for_unit("network-addresses-eth1.service", timeout=120)
        with subtest("fixture addresses and origin are reachable before testing policy"):
            internet.succeed("ip -4 addr show eth1 | grep '198.51.100.10/32'")
            internet.succeed("ip -4 addr show eth1 | grep '198.51.100.11/32'")
            internet.succeed("ip -4 addr show eth1 | grep '198.51.100.12/32'")
            internet.succeed("curl -fsS --max-time 5 http://198.51.100.10:8080")
            internet.succeed("curl -fsS --max-time 5 http://198.51.100.12:8080")
            router.wait_until_succeeds("ip route get 198.51.100.10 | grep 'via 192.0.2.254'", timeout=60)
            router.succeed("curl -fsS --max-time 5 http://198.51.100.10:8080 | grep -x 192.0.2.1")
        client.wait_until_succeeds("ip -4 addr show eth1 | grep '192.168.10.'", timeout=60)
        client.wait_until_succeeds("ip route | grep 'default via 192.168.10.1'", timeout=60)
        client.succeed("nc -z -w 2 192.168.10.1 22")
        internet.fail("nc -z -w 2 192.0.2.1 22")
        internet.fail("nc -z -w 2 192.0.2.1 53")
        internet.fail("dig @192.0.2.1 proxy.test A +time=1 +tries=1")
        internet.fail("nc -z -w 2 192.0.2.1 7893")
        router.succeed("test $(cat /proc/sys/net/ipv6/conf/all/disable_ipv6) = 1")
        router.succeed("ip rule | grep 'fwmark 0x1 lookup 100'")
        router.succeed("ip route show table 100 | grep 'local default dev lo'")
        client.succeed("dig @192.168.10.1 proxy.test A +short | grep '^198.1[89].'")
        # A hardcoded external DNS address must still be redirected locally.
        client.succeed("dig @203.0.113.53 proxy.test A +short +time=2 +tries=1 | grep '^198.1[89].'")
        client.succeed("test -z \"$(dig @192.168.10.1 proxy.test AAAA +short)\"")
        client.wait_until_succeeds("curl -fsS --max-time 5 http://direct.test:8080 | grep -x 192.0.2.1", timeout=60)
        client.succeed("curl -fsS --max-time 5 http://proxy.test:8080 | grep -x 192.0.2.254")
        client.succeed("curl -fsS --max-time 5 http://198.51.100.11:8080 | grep -x 192.0.2.254")
        client.succeed("curl -fsS --max-time 5 http://198.51.100.10:8080 | grep -x 192.0.2.1")
        # NAT for non-proxied traffic, plus routed LAN-to-LAN reachability in both directions.
        client.succeed("ping -c 2 192.0.2.254")
        client.wait_until_succeeds("ping -c 1 -W 2 192.168.20.50", timeout=60)
        client_ip = client.succeed("ip -4 -o addr show dev eth1 | awk '{print $4}' | cut -d/ -f1").strip()
        remote.succeed(f"ping -c 2 {client_ip}")
        # Site B must see the original site A LAN source (no masquerade across WireGuard).
        remote.succeed("systemd-run --unit=capture ${pkgs.coreutils}/bin/timeout 10 ${pkgs.tcpdump}/bin/tcpdump -U -n -i eth1 -c 1 'icmp and src net 192.168.10.0/24' -w /tmp/site.pcap")
        remote.wait_for_unit("capture.service", timeout=120)
        client.succeed("ping -c 2 192.168.20.50")
        remote.wait_until_succeeds("tcpdump -nn -r /tmp/site.pcap 2>/dev/null | grep '192.168.10.'", timeout=60)
        router.succeed("systemctl stop router-proxy")
        client.fail("curl -fsS --max-time 3 http://198.51.100.11:8080")
        client.succeed("nc -z -w 2 192.168.10.1 22")
        client.succeed("ping -c 1 192.168.20.50")
        router.succeed("systemctl start router-proxy")
        router.wait_for_unit("router-proxy.service", timeout=120)
        client.wait_until_succeeds("curl -fsS --max-time 5 http://proxy.test:8080 | grep -x 192.0.2.254", timeout=60)
        with subtest("missing WireGuard routes cannot send site traffic through WAN"):
            remove_site_tunnel()
            router.succeed("ip route get 198.51.100.12 | grep 'via 192.0.2.254'")
            # This origin is reachable over WAN, but its address belongs to an active site.
            # Without the site guard the request succeeds with the router's NATed source.
            client.fail("curl -fsS --max-time 3 http://198.51.100.12:8080")
            client.succeed("curl -fsS --max-time 5 http://198.51.100.10:8080 | grep -x 192.0.2.1")
            client.succeed("nc -z -w 2 192.168.10.1 22")
            restore_site_tunnel()
            client.wait_until_succeeds("ping -c 1 -W 2 192.168.20.50", timeout=60)
        with subtest("hostname endpoint recovers after its WAN address changes"):
            # A has no configured B endpoint. Restart A's tunnel to discard its learned
            # endpoint so recovery requires B to resolve A's new address, not roaming.
            remove_site_tunnel()
            router.succeed("ip address add 192.0.2.3/24 dev eth1; ip address del 192.0.2.1/24 dev eth1; ip route replace default via 192.0.2.254 dev eth1")
            internet.succeed("echo '192.0.2.3 site-a.test' > /run/site-endpoints; systemctl reload dnsmasq")
            restore_site_tunnel()
            siteb.wait_until_succeeds("wg show wg-sites endpoints | grep '192.0.2.3:51820'", timeout=60)
            remote.wait_until_succeeds(f"ping -c 1 -W 2 {client_ip}", timeout=60)
            client.succeed("ping -c 1 -W 2 192.168.20.50")
            # Restore the fixture before the ordinary NixOS configuration switch below.
            router.succeed("ip address add 192.0.2.1/24 dev eth1; ip address del 192.0.2.3/24 dev eth1; ip route replace default via 192.0.2.254 dev eth1")
            internet.succeed("echo '192.0.2.1 site-a.test' > /run/site-endpoints; systemctl reload dnsmasq")
            siteb.wait_until_succeeds("wg show wg-sites endpoints | grep '192.0.2.1:51820'", timeout=60)
        with subtest("disabled WireGuard peers no longer bypass proxy policy"):
            remove_site_tunnel()
            router.succeed("/run/current-system/specialisation/without-sites/bin/switch-to-configuration test", timeout=120)
            router.wait_for_unit("router-proxy.service", timeout=120)
            router.fail("ip link show wg-sites")
            client.wait_until_succeeds("curl -fsS --max-time 5 http://198.51.100.12:8080 | grep -x 192.0.2.254", timeout=60)
            client.succeed("curl -fsS --max-time 5 http://proxy.test:8080 | grep -x 192.0.2.254")
            client.succeed("nc -z -w 2 192.168.10.1 22")
        router.succeed("nft list ruleset")
    except Exception:
        diagnostics()
        raise
  '';
}
