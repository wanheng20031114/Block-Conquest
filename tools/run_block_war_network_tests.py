"""Run native DTLS clients against an isolated release relay, optionally impaired UDP.

All helper PIDs are owned and terminated in finally. Tokyo is never contacted.
Packet impairment acts on encrypted UDP datagrams, preserving the actual native
ENet/DTLS handshake/retransmission path rather than mocking application delivery.
"""
from __future__ import annotations

import argparse
import heapq
import json
import os
import random
import selectors
import socket
import subprocess
import threading
import time
from pathlib import Path

import deploy_block_war_relay as deploy

ROOT = deploy.ROOT
LOCAL = ROOT / ".local" / "network-tests"


class ImpairedUDP:
    def __init__(self, target: tuple[str, int], clients: int, loss: float, latency_ms: float, jitter_ms: float, duplicate: float):
        self.target = target
        self.loss, self.delay, self.jitter, self.duplicate = loss, latency_ms / 2000, jitter_ms / 1000, duplicate
        self.random = random.Random(71309)
        self.selector = selectors.DefaultSelector()
        self.pending: list[tuple[float, int, socket.socket, bytes, tuple]] = []
        self.counter = 0
        self.received = self.dropped = self.duplicated = self.delivered = 0
        self.stop_event = threading.Event()
        self.ports = []
        self.sockets = []
        for _index in range(clients):
            downstream = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            downstream.bind(("127.0.0.1", 0))
            downstream.setblocking(False)
            state = {"downstream": downstream, "sessions": {}}
            self.selector.register(downstream, selectors.EVENT_READ, (state, True))
            self.ports.append(downstream.getsockname()[1])
            self.sockets.append(downstream)
        self.thread = threading.Thread(target=self.run, name="block-conquest-udp-test", daemon=True)
        self.thread.start()

    def schedule(self, endpoint: socket.socket, data: bytes, recipient: tuple) -> None:
        self.counter += 1
        delay = max(0.0, self.delay + self.random.uniform(-self.jitter, self.jitter))
        heapq.heappush(self.pending, (time.monotonic() + delay, self.counter, endpoint, data, recipient))

    def run(self) -> None:
        while not self.stop_event.is_set():
            for event, _mask in self.selector.select(0.002):
                state, client_side = event.data
                try:
                    data, source = event.fileobj.recvfrom(65536)
                except (BlockingIOError, ConnectionResetError):
                    continue
                self.received += 1
                if client_side:
                    # Every recreated ENet host has its own source endpoint.
                    # Preserve that identity at the relay and retain old return
                    # paths; rewriting old DTLS datagrams into a new connection
                    # would test broken NAT remapping instead of packet loss.
                    if source not in state["sessions"]:
                        upstream = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                        upstream.bind(("127.0.0.1", 0))
                        upstream.setblocking(False)
                        session = {"downstream": state["downstream"], "upstream": upstream, "client": source}
                        state["sessions"][source] = session
                        self.selector.register(upstream, selectors.EVENT_READ, (session, False))
                        self.sockets.append(upstream)
                    endpoint, recipient = state["sessions"][source]["upstream"], self.target
                else:
                    endpoint, recipient = state["downstream"], state["client"]
                if self.random.random() < self.loss:
                    self.dropped += 1
                    continue
                self.schedule(endpoint, data, recipient)
                if self.random.random() < self.duplicate:
                    self.duplicated += 1
                    self.schedule(endpoint, data, recipient)
            now = time.monotonic()
            while self.pending and self.pending[0][0] <= now:
                _at, _serial, endpoint, data, recipient = heapq.heappop(self.pending)
                try:
                    endpoint.sendto(data, recipient)
                    self.delivered += 1
                except (BlockingIOError, ConnectionResetError):
                    self.dropped += 1

    def close(self) -> None:
        self.stop_event.set()
        self.thread.join(timeout=3)
        self.selector.close()
        for endpoint in self.sockets:
            endpoint.close()
        if self.thread.is_alive():
            raise RuntimeError("Impairment thread did not terminate")


def run(args) -> dict:
    LOCAL.mkdir(parents=True, exist_ok=True)
    package = deploy.build_relay() if args.build else deploy.LOCAL / "relay-package"
    editor = deploy.runtime("win64.exe")
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    label = (f"weaknet-loss{int(args.loss * 100)}-rtt{int(args.latency)}-jitter{int(args.jitter)}-dup{int(args.duplicate * 100)}"
             if args.loss or args.latency else "release-native")
    config = LOCAL / (label + ".cfg")
    config.write_text(f'[relay]\nbind="127.0.0.1"\nport={port}\nmax_rooms=2\n\n[tls]\nprivate_key="{deploy.KEY.as_posix()}"\ncertificate="{deploy.CERT.as_posix()}"\n', encoding="utf-8")
    environment = os.environ.copy()
    environment["BLOCK_CONQUEST_RELAY_CONFIG"] = str(config)
    server_log = LOCAL / (label + "-server.engine.log")
    client_log = LOCAL / (label + "-clients.engine.log")
    processes = []
    proxy = None
    result = {}
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    try:
        with (LOCAL / (label + "-server.stdout.log")).open("wb") as stdout, (LOCAL / (label + "-server.stderr.log")).open("wb") as stderr:
            server = subprocess.Popen([str(package / "block-conquest-relay.exe"), "--headless", "--log-file", str(server_log)], cwd=package, env=environment, stdout=stdout, stderr=stderr, creationflags=flags)
            processes.append(server)
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                if server.poll() is not None:
                    raise RuntimeError("Release relay exited before readiness")
                if server_log.exists() and "BLOCK_CONQUEST_RELAY_READY" in server_log.read_text(encoding="utf-8", errors="replace"):
                    break
                time.sleep(0.05)
            else:
                raise RuntimeError("Release relay did not report readiness")
            endpoint = {"address": "127.0.0.1", "port": port}
            if args.loss or args.latency or args.jitter or args.duplicate:
                proxy = ImpairedUDP(("127.0.0.1", port), 3, args.loss, args.latency, args.jitter, args.duplicate)
                endpoint["ports"] = proxy.ports
            endpoint_file = LOCAL / (label + "-endpoint.json")
            endpoint_file.write_text(json.dumps(endpoint), encoding="utf-8")
            environment["BLOCK_CONQUEST_NETWORK_TEST_ENDPOINT"] = str(endpoint_file)
            with (LOCAL / (label + "-clients.stdout.log")).open("wb") as child_stdout, (LOCAL / (label + "-clients.stderr.log")).open("wb") as child_stderr:
                client = subprocess.Popen([str(editor), "--headless", "--path", str(ROOT), "--log-file", str(client_log), "--script", "res://tests/block_war_native_network_test.gd"], env=environment, stdout=child_stdout, stderr=child_stderr, creationflags=flags)
                processes.append(client)
                code = client.wait(timeout=90)
            text = client_log.read_text(encoding="utf-8", errors="replace")
            summary = next((line for line in text.splitlines() if line.startswith("BLOCK_WAR_NATIVE_NETWORK")), "")
            if code != 0 or not summary.endswith("failures=0") or "SCRIPT ERROR" in text:
                raise RuntimeError("Native client verification failed; inspect the local test logs")
            result = {"test": label, "summary": summary, "runtime": deploy.RUNTIME_VERSION, "loss": args.loss, "rtt_ms": args.latency, "jitter_ms": args.jitter, "duplicate": args.duplicate}
            if proxy:
                result["encrypted_datagrams"] = {"received": proxy.received, "dropped": proxy.dropped, "duplicated": proxy.duplicated, "delivered": proxy.delivered}
    finally:
        if proxy:
            proxy.close()
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
        result["processes"] = [{"pid": process.pid, "exit_code": process.poll(), "exited": process.poll() is not None} for process in processes]
        (LOCAL / (label + "-receipt.json")).write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", action="store_true")
    parser.add_argument("--loss", type=float, default=0.0)
    parser.add_argument("--latency", type=float, default=0.0, help="Round trip delay in milliseconds for each client-to-relay leg")
    parser.add_argument("--jitter", type=float, default=0.0)
    parser.add_argument("--duplicate", type=float, default=0.0)
    args = parser.parse_args()
    if not 0 <= args.loss <= 0.3 or not 0 <= args.duplicate <= 0.3 or not 0 <= args.latency <= 1000 or not 0 <= args.jitter <= 300:
        parser.error("Impairment parameters exceed supported bounded test range")
    print(json.dumps(run(args), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
