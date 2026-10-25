import copy
import importlib.util
import unittest
from pathlib import Path


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).parents[1] / "scripts" / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


site = load("validate-site")
proxy = load("render-proxy")


class SiteValidation(unittest.TestCase):
    def setUp(self):
        self.cfg = {
            "lan": {"subnet": "192.168.10.0/24", "ports": ["eth2"], "dhcpStart": 100, "dhcpEnd": 199},
            "wan": {"interface": "eth1", "dhcp": True},
            "dns": {"upstream": ["1.1.1.1"]},
            "wireguard": {"enable": False},
            "wifi": {"enable": False},
            "proxy": {"enable": True, "outboundFile": "/run/secrets/outbound", "bypassCIDRs": ["192.168.0.0/16"], "directCIDRs": [], "usCIDRs": [], "directDomains": [], "usDomains": ["example.com"]},
        }

    def test_valid(self):
        self.assertTrue(site.validate(self.cfg))

    def test_reject_bad_sites(self):
        changes = [
            ("lan", "subnet", "8.8.8.0/24"),
            ("lan", "subnet", "192.168.10.5/24"),
            ("lan", "subnet", "192.168.10.0/25"),
            ("lan", "subnet", "192.168.999.0/24"),
            ("lan", "ports", ["eth1"]),
            ("lan", "ports", ["eth2", "eth2"]),
            ("lan", "dhcpStart", 1),
            ("lan", "dhcpEnd", 50),
            ("dns", "upstream", ["127.0.0.1"]),
            ("dns", "upstream", ["192.168.10.1"]),
            ("proxy", "outboundFile", "/nix/store/not-a-secret"),
            ("proxy", "bypassCIDRs", ["0.0.0.0/0"]),
            ("proxy", "usCIDRs", ["192.168.10.0/24"]),
            ("proxy", "usCIDRs", ["::/0"]),
            ("proxy", "directDomains", ["a.example.com"]),
            ("proxy", "usDomains", ["https://example.com"]),
            ("proxy", "usDomains", ["*.example.com"]),
        ]
        for section, key, value in changes:
            with self.subTest(section=section, key=key, value=value):
                cfg = copy.deepcopy(self.cfg)
                cfg[section][key] = value
                with self.assertRaises(ValueError):
                    site.validate(cfg)

    def test_site_routes(self):
        wg = self.cfg["wireguard"] = {
            "enable": True, "privateKeyFile": "/run/secrets/wg", "address": "10.77.0.1/24",
            "peers": [{"publicKey": "zo060cy2M+x7cMF4FKXHbs0CloUFDTRHRboFhw5YfVk=", "allowedIPs": ["10.77.0.2/32", "192.168.20.0/24"], "presharedKeyFile": None}],
        }
        self.assertTrue(site.validate(self.cfg))
        for route in ["0.0.0.0/0", "192.168.10.0/24", "10.77.0.1/32"]:
            with self.subTest(route=route):
                wg["peers"][0]["allowedIPs"] = [route]
                with self.assertRaises(ValueError):
                    site.validate(self.cfg)

    def test_conflicting_peers(self):
        self.cfg["wireguard"] = {
            "enable": True, "privateKeyFile": "/run/secrets/wg", "address": "10.77.0.1/24",
            "peers": [{"publicKey": "zo060cy2M+x7cMF4FKXHbs0CloUFDTRHRboFhw5YfVk=", "allowedIPs": ["192.168.20.0/24"], "presharedKeyFile": None}] * 2,
        }
        with self.assertRaises(ValueError):
            site.validate(self.cfg)

    def test_wireguard_connected_networks_do_not_overlap(self):
        self.cfg["wan"].update(dhcp=False, address="192.0.2.1/24", gateway="192.0.2.254")
        wg = self.cfg["wireguard"] = {
            "enable": True, "privateKeyFile": "/run/secrets/wg", "address": "10.77.0.1/24",
            "peers": [{"publicKey": "zo060cy2M+x7cMF4FKXHbs0CloUFDTRHRboFhw5YfVk=", "allowedIPs": ["10.77.0.2/32", "192.168.20.0/24"], "presharedKeyFile": None}],
        }
        self.assertTrue(site.validate(self.cfg))
        for address in ["192.168.11.1/16", "192.0.2.1/24", "192.0.3.1/16"]:
            with self.subTest(address=address):
                wg["address"] = address
                with self.assertRaises(ValueError):
                    site.validate(self.cfg)


class OutboundRendering(unittest.TestCase):
    def setUp(self):
        self.base = {"outbounds": [{"type": "direct", "tag": "direct"}]}
        self.outbound = {"type": "socks", "tag": "us", "server": "192.0.2.1", "server_port": 1080}

    def test_merge(self):
        result = proxy.render(self.base, self.outbound)
        self.assertEqual(len(result["outbounds"]), 2)
        self.assertEqual(len(self.base["outbounds"]), 1)

    def test_reject_unsafe_or_incomplete_outbound(self):
        for key, value in [("type", "direct"), ("tag", "direct"), ("server", ""), ("server_port", 0), ("server_port", True), ("tls", []), ("tls", {"insecure": True}), ("detour", "direct"), ("routing_mark", 1)]:
            with self.subTest(key=key):
                outbound = dict(self.outbound, **{key: value})
                with self.assertRaises(ValueError):
                    proxy.render(self.base, outbound)


if __name__ == "__main__":
    unittest.main()
