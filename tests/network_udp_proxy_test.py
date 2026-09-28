"""The impairment proxy must preserve distinct DTLS transport identities."""
from pathlib import Path
import socket
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from run_block_war_network_tests import ImpairedUDP


class ProxyIdentityTest(unittest.TestCase):
    def test_recreated_client_keeps_separate_upstream_and_return_paths(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as relay, \
                socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as old_client, \
                socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as new_client:
            for endpoint in (relay, old_client, new_client):
                endpoint.bind(("127.0.0.1", 0))
                endpoint.settimeout(2.0)
            proxy = ImpairedUDP(relay.getsockname(), 1, 0.0, 0.0, 0.0, 0.0)
            try:
                address = ("127.0.0.1", proxy.ports[0])
                old_client.sendto(b"old session", address)
                payload, old_upstream = relay.recvfrom(1024)
                self.assertEqual(payload, b"old session")
                new_client.sendto(b"new session", address)
                payload, new_upstream = relay.recvfrom(1024)
                self.assertEqual(payload, b"new session")
                self.assertNotEqual(old_upstream, new_upstream)
                relay.sendto(b"old delayed response", old_upstream)
                relay.sendto(b"new response", new_upstream)
                self.assertEqual(old_client.recvfrom(1024)[0], b"old delayed response")
                self.assertEqual(new_client.recvfrom(1024)[0], b"new response")
                old_client.sendto(b"old retransmission", address)
                payload, upstream = relay.recvfrom(1024)
                self.assertEqual((payload, upstream), (b"old retransmission", old_upstream))
            finally:
                proxy.close()
            self.assertFalse(proxy.thread.is_alive())


if __name__ == "__main__":
    unittest.main()
