import getpass
import json
import os
import re
import subprocess
import tempfile


def start_demo():
    """Start both VMs and wait for the update server to become ready."""
    appliance.start(allow_reboot=True)
    server.start()

    server.wait_for_unit("multi-user.target")
    server.wait_for_unit("nginx.service")
    server.wait_for_unit("dnsmasq.service")
    server.wait_for_open_port(80)


def ssh(command, timeout=120):
    """Run a shell command on the appliance and return its stdout."""
    return server.succeed(f"ssh-to-appliance -- {command}", timeout=timeout)


def wait_ssh(timeout=300):
    """Block until the appliance accepts SSH logins again."""
    server.wait_until_succeeds("ssh-to-appliance -- true", timeout=timeout)


def appliance_shell():
    """Open an interactive SSH session without consuming the driver shell."""
    assert appliance.vsock_host is not None, "the interactive SSH relay is disabled"
    subprocess.run(
        [
            os.environ["RUGIX_DEMO_SSH"],
            "-F",
            os.environ["RUGIX_DEMO_SSH_CONFIG"],
            "-i",
            os.environ["RUGIX_DEMO_TEST_KEY"],
            "-o",
            "IdentitiesOnly=yes",
            "-o",
            "LogLevel=ERROR",
            "-o",
            "User=root",
            "-t",
            f"vsock-mux/{appliance.vsock_host}",
        ],
        check=True,
    )


def provision_nexigon():
    """Pair the appliance with Nexigon using a value read without echo."""
    pairing_value = getpass.getpass("Nexigon pairing value: ")
    guest_path = "/run/nexigon-pairing-value"

    try:
        with tempfile.NamedTemporaryFile(mode="w") as pairing_file:
            pairing_file.write(pairing_value)
            pairing_file.flush()
            server.copy_from_host(pairing_file.name, guest_path)

        response = server.succeed(
            "curl --fail --silent --show-error "
            f"--data-binary @{guest_path} http://192.168.1.100:6947/pair"
        )
    finally:
        server.succeed(f"rm -f {guest_path}")

    result = json.loads(response)
    assert result["status"] == "paired", result
    server.wait_until_succeeds(
        "ssh-to-appliance -- "
        "test -s /var/lib/nexigon/agent/credentials.json",
        timeout=30,
    )
    return result


def boot_info():
    """Return Rugix's view of the active and default A/B groups."""
    return json.loads(ssh("rugix-ctrl system info"))["boot"]


def install_update(url):
    """Download a bundle and write it into the inactive A/B slot."""
    ssh(
        f"rugix-ctrl update install {url} "
        "--insecure-skip-bundle-verification --reboot no",
        timeout=900,
    )


observed_app_start_count = 0


def install_app(version):
    """Install one verified version of the containerized Rugix App."""
    bundle_name = f"python-web-app-v{version}.rugixb"
    bundle_hash = server.succeed(
        f"curl --fail --silent http://localhost/{bundle_name}-hash"
    ).strip()
    ssh(
        "rugix-ctrl apps install "
        f"--bundle-hash {bundle_hash} "
        f"http://update-server/{bundle_name}",
        timeout=600,
    )


def app_page():
    """Return the page served by the active container generation."""
    return ssh("curl --fail --silent http://127.0.0.1:8080/")


def assert_app(expected_version, expected_generation):
    """Verify app status, version, generation, and persistent start count."""
    global observed_app_start_count
    apps = json.loads(ssh("rugix-ctrl apps list"))
    app = apps["python-web-server"]
    assert app["status"]["state"] == "running", app
    assert app["generation"] == expected_generation, app

    page = app_page()
    match = re.search(
        r'data-app-version="([^"]+)" data-start-count="([0-9]+)"', page
    )
    assert match is not None, page
    assert match.group(1) == expected_version, page
    start_count = int(match.group(2))
    assert start_count > observed_app_start_count, (
        start_count,
        observed_app_start_count,
    )
    observed_app_start_count = start_count


def rollback_app():
    """Roll the example app back to its preceding generation."""
    ssh("rugix-ctrl apps rollback python-web-server", timeout=300)


def activate_app(generation):
    """Activate a selected generation of the example app."""
    ssh(f"rugix-ctrl apps activate python-web-server {generation}", timeout=300)


def reboot_into_spare():
    """Reboot once into the freshly updated spare group."""
    server.execute("ssh-to-appliance -- rugix-ctrl system reboot --spare", timeout=20)
    server.sleep(15)
    wait_ssh()


def reboot_and_commit(expected_group):
    """Reboot into the spare group, verify its store, and commit it."""
    reboot_into_spare()
    assert boot_info()["activeGroup"] == expected_group
    ssh("mount | grep -q squashfs")
    ssh("rugix-ctrl system commit")
    assert boot_info()["defaultGroup"] == expected_group
