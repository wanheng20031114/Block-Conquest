"""Build/check the isolated Tokyo Block Conquest relay without logging credentials.

The authorized credential source is Documents/.env (Tokyo only). The public trust
certificate is shipped to clients; the private key and SSH pin stay under .local.
Only block-conquest-relay.service and its own /opt directory may be modified.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import ipaddress
import json
import logging
import os
import re
import shlex
import sys
import subprocess
import time
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT / ".local" / "network"
CERT = ROOT / "scripts" / "network" / "relay_trust.crt"
KEY = LOCAL / "relay-private.key"
BASE = "/opt/block-conquest-relay"
SERVICE = "block-conquest-relay.service"
USER = "blockconquest"
TLS_NAME = "block-conquest-relay"
PORT = 42300
RUNTIME_VERSION = "4.7.2-stable"
RUNTIME_ARCHIVES = {
    "linux.x86_64": "cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4",
    "win64.exe": "731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953",
}
TEMPLATE_ARCHIVE_SHA256 = "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011"
TEMPLATE_RELEASE_SHA256 = {
    "linux_release.x86_64": "d9f79ab89b5ae369aeed11c6052d402e8218cd503bf85b4a235f9c30c46a7c63",
    "windows_release_x86_64.exe": "d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562",
}
SOURCE_FILES = (
    "scripts/network/war_protocol.gd",
    "server/war_relay_rooms.gd",
    "server/war_relay_server.gd",
    "server/relay_main.gd",
    "server/relay_bootstrap.gd",
    "server/relay.tscn",
    "data/block_war/network_manifest.json",
)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def runtime(platform: str) -> Path:
    folder = LOCAL / "runtime"
    folder.mkdir(parents=True, exist_ok=True)
    name = "Godot_v" + RUNTIME_VERSION + "_" + platform
    archive = folder / (name + ".zip")
    expected = RUNTIME_ARCHIVES[platform]
    if not archive.exists() or digest(archive.read_bytes()) != expected:
        partial = archive.with_suffix(".download")
        url = "https://github.com/godotengine/godot-builds/releases/download/" + RUNTIME_VERSION + "/" + archive.name
        with urllib.request.urlopen(url, timeout=60) as source, partial.open("wb") as target:
            if source.status != 200:
                raise RuntimeError("Runtime download returned an incomplete response")
            while block := source.read(1048576):
                target.write(block)
        if digest(partial.read_bytes()) != expected:
            raise RuntimeError("Official runtime archive checksum mismatch")
        partial.replace(archive)
    with zipfile.ZipFile(archive) as package:
        executable = folder / name
        data = package.read(name)
        if not executable.exists() or digest(executable.read_bytes()) != digest(data):
            executable.write_bytes(data)
        console = name.replace(".exe", "_console.exe")
        if platform == "win64.exe" and console in package.namelist():
            (folder / console).write_bytes(package.read(console))
    if platform == "win64.exe":
        # Portable editor settings and doc caches must stay in this workspace.
        (folder / "_sc_").touch()
    return executable


def templates() -> Path:
    folder = LOCAL / "templates"
    folder.mkdir(parents=True, exist_ok=True)
    receipt_path = folder / "receipt.json"
    if receipt_path.exists():
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        if (receipt.get("version") == RUNTIME_VERSION and receipt.get("archive_sha256") == TEMPLATE_ARCHIVE_SHA256
                and receipt.get("official_checksum_verified") is True
                and all((folder / name).is_file() and digest((folder / name).read_bytes()) == record.get("sha256")
                        for name, record in receipt.get("files", {}).items())
                and set(receipt.get("files", {})) == {"windows_release_x86_64.exe", "windows_debug_x86_64.exe", "linux_release.x86_64"}):
            return folder
    archive = folder / "Godot_v4.7.2-stable_export_templates.tpz"
    release = "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/"
    if not archive.exists() or digest(archive.read_bytes()) != TEMPLATE_ARCHIVE_SHA256:
        partial = archive.with_suffix(".download")
        with urllib.request.urlopen(release + archive.name, timeout=90) as response, partial.open("wb") as target:
            while block := response.read(4 * 1048576):
                target.write(block)
        if digest(partial.read_bytes()) != TEMPLATE_ARCHIVE_SHA256:
            raise RuntimeError("Official template archive checksum mismatch")
        partial.replace(archive)
    files = {}
    with zipfile.ZipFile(archive) as package:
        for name in ("windows_release_x86_64.exe", "windows_debug_x86_64.exe", "linux_release.x86_64"):
            data = package.read("templates/" + name)
            if name in TEMPLATE_RELEASE_SHA256 and digest(data) != TEMPLATE_RELEASE_SHA256[name]:
                raise RuntimeError("Official release template checksum mismatch")
            (folder / name).write_bytes(data)
            files[name] = {"sha256": digest(data), "bytes": len(data)}
    # Keep the official published checksums as independently reviewable evidence.
    with urllib.request.urlopen(release + "SHA512-SUMS.txt", timeout=45) as source:
        published = source.read().decode("utf-8")
    archive_sha512 = hashlib.sha512(archive.read_bytes()).hexdigest()
    entries = {line.split()[-1].lstrip("*"): line.split()[0] for line in published.splitlines() if len(line.split()) >= 2}
    if entries.get(archive.name) != archive_sha512:
        raise RuntimeError("Official published SHA512 template checksum mismatch")
    (folder / "SHA512-SUMS.txt").write_text(published, encoding="utf-8")
    (folder / "receipt.json").write_text(json.dumps({"version": RUNTIME_VERSION, "source_url": release + archive.name, "archive_sha256": TEMPLATE_ARCHIVE_SHA256, "archive_sha512": archive_sha512, "official_checksum_verified": True, "files": files}, indent=2), encoding="utf-8")
    return folder


def build_relay() -> Path:
    """Produce a server-only PCK and unchanged, checksum-verified release templates."""
    folder = LOCAL / "relay-package"
    project = folder / "project"
    project.mkdir(parents=True, exist_ok=True)
    native_templates = templates()
    editor = runtime("win64.exe")
    source_hashes = {}
    for name in SOURCE_FILES:
        data = (ROOT / name).read_bytes()
        destination = project / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        source_hashes[name] = digest(data)
    project_config = (ROOT / "server/relay_project.godot").read_bytes()
    (project / "project.godot").write_bytes(project_config)
    source_hashes["server/relay_project.godot"] = digest(project_config)
    linux_template = native_templates / "linux_release.x86_64"
    if digest(linux_template.read_bytes()) != TEMPLATE_RELEASE_SHA256[linux_template.name]:
        raise RuntimeError("Linux release template checksum mismatch")
    preset = f'''[preset.0]
name="Relay Linux"
platform="Linux"
runnable=true
dedicated_server=true
custom_features="dedicated_server"
export_filter="all_resources"
include_filter="data/block_war/*.json"
exclude_filter=""
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]
custom_template/release={json.dumps(linux_template.as_posix())}
binary_format/architecture="x86_64"
binary_format/embed_pck=false
'''
    (project / "export_presets.cfg").write_text(preset, encoding="utf-8")
    steps = {}
    for name, arguments in (("import", ["--editor", "--import", "--quit"]), ("export", ["--export-pack", "Relay Linux", str(folder / "block-conquest-relay.pck")])):
        log = folder / (name + ".engine.log")
        with (folder / (name + ".stdout.log")).open("wb") as stdout, (folder / (name + ".stderr.log")).open("wb") as stderr:
            flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
            process = subprocess.Popen([str(editor), "--headless", "--path", str(project), "--log-file", str(log), *arguments], stdout=stdout, stderr=stderr, creationflags=flags)
            try:
                code = process.wait(timeout=90)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=5)
        output = log.read_text(encoding="utf-8", errors="replace")
        if code != 0 or "SCRIPT ERROR" in output or any("ERROR:" in line and "root certificate store" not in line for line in output.splitlines()):
            raise RuntimeError("Relay release export failed; inspect local build logs")
        steps[name] = {"pid": process.pid, "exit_code": code, "exited": process.poll() is not None}
    (folder / "block-conquest-relay").write_bytes(linux_template.read_bytes())
    (folder / "block-conquest-relay.exe").write_bytes((native_templates / "windows_release_x86_64.exe").read_bytes())
    receipt = {"runtime": RUNTIME_VERSION, "source_sha256": source_hashes, "files": {name: digest((folder / name).read_bytes()) for name in ("block-conquest-relay", "block-conquest-relay.exe", "block-conquest-relay.pck")}, "steps": steps}
    (folder / "build-receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    return folder


def certificate() -> None:
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

    if KEY.exists() != CERT.exists():
        raise RuntimeError("Refusing to replace an incomplete certificate pair")
    LOCAL.mkdir(parents=True, exist_ok=True)
    if KEY.exists():
        private = serialization.load_pem_private_key(KEY.read_bytes(), password=None)
        public = x509.load_pem_x509_certificate(CERT.read_bytes())
        identity = public.subject.get_attributes_for_oid(NameOID.COMMON_NAME)
        if private.public_key().public_numbers() != public.public_key().public_numbers() or len(identity) != 1 or identity[0].value != TLS_NAME:
            raise RuntimeError("Existing trust pair or certificate identity is inconsistent")
        return
    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    now = dt.datetime.now(dt.timezone.utc)
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, TLS_NAME)])
    public = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject)
              .public_key(private.public_key()).serial_number(x509.random_serial_number())
              .not_valid_before(now - dt.timedelta(days=1)).not_valid_after(now + dt.timedelta(days=1095))
              .add_extension(x509.SubjectAlternativeName([x509.DNSName(TLS_NAME)]), critical=False)
              .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
              .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
              .sign(private, hashes.SHA256()))
    KEY.write_bytes(private.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL, serialization.NoEncryption()))
    CERT.write_bytes(public.public_bytes(serialization.Encoding.PEM))


def credentials() -> dict[str, str]:
    source = Path.home() / "Documents" / ".env"
    blocks: list[dict[str, str]] = []
    current: dict[str, str] = {}
    for raw in source.read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if re.fullmatch(r"\[[^\]]+\]", line):
            if current:
                blocks.append(current)
            current = {"server_name": line[1:-1].lower()}
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip().lower().removeprefix("export ")
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        if key == "server_name" and current:
            blocks.append(current)
            current = {}
        current[key] = value
    if current:
        blocks.append(current)
    choices = [block for block in blocks if block.get("server_name", "").lower() == "tokyo"]
    if not choices and len(blocks) == 1 and not blocks[0].get("server_name"):
        choices = blocks  # User explicitly identified this single Documents/.env as Tokyo.
    if len(choices) != 1 or not choices[0].get("ip") or not choices[0].get("password"):
        raise RuntimeError("The authorized Tokyo credential block is incomplete or ambiguous")
    selected = choices[0].copy()
    ipaddress.ip_address(selected["ip"])
    selected.setdefault("username", "root")
    return selected


def configure_client() -> None:
    selected = credentials()
    source = ROOT / "scripts/network/war_online.gd"
    content = source.read_text(encoding="utf-8")
    changed, count = re.subn(r'^const DEFAULT_ADDRESS := "[^"]*"$', 'const DEFAULT_ADDRESS := ' + json.dumps(selected["ip"]), content, count=1, flags=re.MULTILINE)
    if count != 1:
        raise RuntimeError("Default endpoint declaration was not found exactly once")
    source.write_text(changed, encoding="utf-8", newline="\n")
    LOCAL.mkdir(parents=True, exist_ok=True)
    (LOCAL / "endpoint.json").write_text(json.dumps({"server_name": "tokyo", "address": selected["ip"], "port": PORT}), encoding="utf-8")


def connect_ssh():
    import paramiko

    logging.getLogger("paramiko.transport").addHandler(logging.NullHandler())
    logging.getLogger("paramiko.transport").propagate = False
    config = credentials()
    LOCAL.mkdir(parents=True, exist_ok=True)
    known_hosts = LOCAL / "tokyo_known_hosts"
    client = paramiko.SSHClient()
    client.load_system_host_keys()
    if known_hosts.exists():
        client.load_host_keys(str(known_hosts))
        client.set_missing_host_key_policy(paramiko.RejectPolicy())
    else:
        # First-use pin is saved only after authenticating the explicitly named
        # server. Subsequent deployments reject identity changes.
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(config["ip"], port=int(config.get("port", "22")), username=config["username"], password=config["password"], timeout=15, banner_timeout=40, auth_timeout=20, allow_agent=False, look_for_keys=False)
    if not known_hosts.exists():
        client.save_host_keys(str(known_hosts))
    return client


def remote(client, command: str, timeout: int = 30) -> str:
    stdin, stdout, stderr = client.exec_command(command, timeout=timeout)
    stdin.close()
    output = stdout.read().decode("utf-8", "replace")
    stderr.read()
    if stdout.channel.recv_exit_status() != 0:
        raise RuntimeError("Bounded isolated relay operation failed")
    return output.strip()


def identity(client) -> dict[str, str]:
    output = remote(client, "systemctl show " + SERVICE + " -p MainPID -p ActiveState -p SubState -p InvocationID -p NRestarts")
    return dict(line.split("=", 1) for line in output.splitlines() if "=" in line)


def unrelated_relays(client) -> dict[str, str]:
    listing = remote(client, "systemctl list-units --type=service --all --no-legend --plain")
    result = {}
    for line in listing.splitlines():
        service = line.split()[0] if line.split() else ""
        if "relay" in service and service != SERVICE and re.fullmatch(r"[A-Za-z0-9_.@-]+\.service", service):
            result[service] = remote(client, "systemctl show " + shlex.quote(service) + " -p MainPID -p ActiveState -p InvocationID")
    return result


def probe() -> None:
    client = connect_ssh()
    try:
        account = remote(client, "id -u")
        machine = remote(client, "uname -m")
        listeners = remote(client, "ss -H -lunp 'sport = :42300'")
        relays = unrelated_relays(client)
        memory = remote(client, "awk '/MemTotal:|MemAvailable:|SwapTotal:|SwapFree:/ {print $1, $2}' /proc/meminfo")
        memory_kib = {line.split()[0].rstrip(":"): int(line.split()[1]) for line in memory.splitlines()}
        print(json.dumps({"server": "tokyo", "administrative_account": account == "0", "architecture": machine, "port_available": not bool(listeners), "other_relay_services": list(relays), "service": identity(client), "memory_kib": memory_kib}, ensure_ascii=False))
    finally:
        client.close()


def deploy(max_rooms: int) -> None:
    if not 1 <= max_rooms <= 64:
        raise ValueError("Room capacity must be 1..64")
    certificate()
    package = build_relay()
    executable = package / "block-conquest-relay"
    executable_hash = digest(executable.read_bytes())
    payload = {name: (package / name).read_bytes() for name in ("block-conquest-relay", "block-conquest-relay.pck", "build-receipt.json")}
    release_hash = digest(b"".join(name.encode() + payload[name] for name in sorted(payload)))[:16]
    release = BASE + "/releases/" + release_hash
    client = connect_ssh()
    previous = ""
    previous_files: dict[str, bytes] = {}
    changed = False
    try:
        if remote(client, "id -u") != "0" or remote(client, "uname -m") != "x86_64":
            raise RuntimeError("Authorized server requires an x86_64 administrative deployment")
        preserved = unrelated_relays(client)
        previous_state = identity(client)
        listener = remote(client, "ss -H -lunp 'sport = :42300'")
        previous_pid = previous_state.get("MainPID", "0")
        if listener and (previous_pid == "0" or ("pid=" + previous_pid + ",") not in listener):
            raise RuntimeError("UDP 42300 is occupied by a service outside this deployment")
        if previous_state.get("ActiveState") == "active":
            previous = remote(client, "readlink -f " + BASE + "/current")
            if not re.fullmatch(re.escape(BASE) + r"/releases/[0-9a-f]{16}", previous):
                raise RuntimeError("Cannot verify previous isolated release for rollback")
            with client.open_sftp() as sftp:
                for name in ("relay.cfg", "relay.crt", "relay-private.key", SERVICE):
                    with sftp.open(BASE + "/config/" + name, "rb") as handle:
                        previous_files[name] = handle.read()
        remote(client, "install -d -m 755 " + BASE + " " + BASE + "/bin " + BASE + "/config")
        remote(client, "id -u " + USER + " >/dev/null 2>&1 || useradd --system --home-dir " + BASE + " --shell /usr/sbin/nologin " + USER)

        def upload(sftp, path: str, data: bytes, mode: int = 0o644) -> None:
            if not path.startswith(BASE + "/"):
                raise RuntimeError("Upload escaped the isolated application")
            remote(client, "install -d -m 755 " + shlex.quote(path.rsplit("/", 1)[0]))
            with sftp.open(path, "wb") as handle:
                sftp.chmod(path, mode)
                handle.write(data)

        with client.open_sftp() as sftp:
            for name, data in payload.items():
                path = release + "/" + name
                present = remote(client, "if [ -f " + shlex.quote(path) + " ]; then sha256sum " + shlex.quote(path) + "; fi")
                if present and not present.startswith(digest(data) + " "):
                    raise RuntimeError("Immutable release content conflict")
                if not present:
                    upload(sftp, path + ".uploading", data, 0o755 if name == "block-conquest-relay" else 0o644)
                    if not remote(client, "sha256sum " + shlex.quote(path + ".uploading")).startswith(digest(data) + " "):
                        raise RuntimeError("Uploaded source checksum mismatch")
                    remote(client, "mv -T -- " + shlex.quote(path + ".uploading") + " " + shlex.quote(path))
            changed = True
            upload(sftp, BASE + "/config/relay-private.key", KEY.read_bytes(), 0o600)
            upload(sftp, BASE + "/config/relay.crt", CERT.read_bytes())
            config = f'[relay]\nbind="*"\nport={PORT}\nmax_rooms={max_rooms}\n\n[tls]\nprivate_key="{BASE}/config/relay-private.key"\ncertificate="{BASE}/config/relay.crt"\n'
            upload(sftp, BASE + "/config/relay.cfg", config.encode(), 0o600)
            unit = f'''[Unit]
Description=Block Conquest encrypted room relay
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User={USER}
Group={USER}
WorkingDirectory={BASE}/current
Environment=BLOCK_CONQUEST_RELAY_CONFIG={BASE}/config/relay.cfg
Environment=HOME={BASE}/state
ExecStart={release}/block-conquest-relay --headless
Restart=on-failure
RestartSec=3
TimeoutStopSec=10
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths={BASE}/state
MemoryHigh=128M
MemoryMax=192M
TasksMax=64
LimitNOFILE=1024

[Install]
WantedBy=multi-user.target
'''
            upload(sftp, BASE + "/config/" + SERVICE, unit.encode())
        remote(client, "install -d -m 750 -o " + USER + " -g " + USER + " " + BASE + "/state")
        remote(client, "chown -R " + USER + ":" + USER + " " + BASE + "/config")
        remote(client, "ln -sfn " + shlex.quote(release) + " " + BASE + "/current")
        remote(client, "install -m 644 " + BASE + "/config/" + SERVICE + " /etc/systemd/system/" + SERVICE)
        remote(client, "systemctl daemon-reload")
        remote(client, "systemctl enable " + SERVICE)
        remote(client, "systemctl restart " + SERVICE)
        invocation = identity(client)
        identifier = invocation.get("InvocationID", "")
        if not re.fullmatch(r"[0-9a-f]{32}", identifier):
            raise RuntimeError("Service did not acquire a valid invocation")
        deadline = time.monotonic() + 15
        ready = False
        while time.monotonic() < deadline:
            journal = remote(client, "journalctl _SYSTEMD_INVOCATION_ID=" + identifier + " --no-pager -o cat")
            if "SCRIPT ERROR" in journal or "ERROR:" in journal:
                # Save only application journal, never credential variables.
                (LOCAL / "deployment-startup.log").write_text(journal, encoding="utf-8")
                raise RuntimeError("Relay startup failed; see local bounded application log")
            if "BLOCK_CONQUEST_RELAY_READY" in journal:
                ready = True
                break
            time.sleep(0.25)
        final = identity(client)
        if not ready or final != invocation or final.get("ActiveState") != "active":
            raise RuntimeError("Service did not remain healthy during readiness")
        if unrelated_relays(client) != preserved:
            raise RuntimeError("An unrelated relay changed identity during deployment")
        listener = remote(client, "ss -H -lunp 'sport = :42300'")
        if ("pid=" + final["MainPID"] + ",") not in listener:
            raise RuntimeError("Relay service does not own the expected UDP listener")
        receipt = {"server": "tokyo", "service": SERVICE, "port": PORT, "release": release_hash, "runtime": RUNTIME_VERSION, "runtime_sha256": executable_hash, "source_sha256": {name: digest(data) for name, data in payload.items()}, "state": final, "unrelated_relays_preserved": True, "max_rooms": max_rooms, "deployed_utc": dt.datetime.now(dt.timezone.utc).isoformat()}
        (LOCAL / "deployment-receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
        print(json.dumps({key: receipt[key] for key in ("server", "service", "port", "release", "runtime", "state", "unrelated_relays_preserved", "max_rooms")}))
    except Exception:
        if changed:
            remote(client, "systemctl stop " + SERVICE)
            if previous:
                with client.open_sftp() as sftp:
                    for name, data in previous_files.items():
                        upload(sftp, BASE + "/config/" + name, data, 0o600 if name in ("relay-private.key", "relay.cfg") else 0o644)
                remote(client, "ln -sfn " + shlex.quote(previous) + " " + BASE + "/current")
                remote(client, "install -m 644 " + BASE + "/config/" + SERVICE + " /etc/systemd/system/" + SERVICE)
                remote(client, "systemctl daemon-reload")
                remote(client, "systemctl start " + SERVICE)
            else:
                remote(client, "systemctl disable " + SERVICE)
        raise
    finally:
        client.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group(required=True)
    actions.add_argument("--certificate", action="store_true")
    actions.add_argument("--configure-client", action="store_true")
    actions.add_argument("--runtimes", action="store_true")
    actions.add_argument("--templates", action="store_true")
    actions.add_argument("--build-relay", action="store_true")
    actions.add_argument("--probe", action="store_true")
    actions.add_argument("--deploy", action="store_true")
    parser.add_argument("--max-rooms", type=int, default=8)
    args = parser.parse_args()
    try:
        if args.certificate:
            certificate()
            print("BLOCK_CONQUEST_CERTIFICATE_READY")
        elif args.configure_client:
            configure_client()
            print("BLOCK_CONQUEST_TOKYO_ENDPOINT_CONFIGURED")
        elif args.runtimes:
            runtime("win64.exe")
            runtime("linux.x86_64")
            print("BLOCK_CONQUEST_RUNTIMES_VERIFIED version=" + RUNTIME_VERSION)
        elif args.templates:
            templates()
            print("BLOCK_CONQUEST_TEMPLATES_VERIFIED version=" + RUNTIME_VERSION)
        elif args.build_relay:
            build_relay()
            print("BLOCK_CONQUEST_RELAY_RELEASE_BUILT")
        elif args.probe:
            probe()
        else:
            deploy(args.max_rooms)
        return 0
    except Exception as error:
        # Network exception text may include credential source addresses.
        print("BLOCK_CONQUEST_RELAY_OPERATION_FAILED type=" + type(error).__name__, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
