# Complete Rugix NixOS Appliance Example

This repository builds a NixOS appliance with two system slots, A and B. Rugix
installs an update into the inactive slot without overwriting the running
system. The example includes:

- Atomic A/B system updates and rollback with [Rugix Ctrl](https://rugix.org/docs/ctrl/)
- Full and delta Rugix update bundles
- Container application updates and rollback with [Rugix Apps](https://rugix.org/docs/ctrl/application-management/)
- Local device management with [Rugix Admin](https://rugix.org/docs/admin/)
- Fleet connectivity and pairing-key provisioning with [Nexigon](https://docs.nexigon.dev/)
- Images, system updates, and application bundles for x86-64 and AArch64

The example is based on NixOS 26.05 and builds the complete stack from source.
It consumes the upstream flakes for Rugix revision `e9c3a26`, Nexigon revision
`4a838dd`, and Rugix Admin revision `1812c99`. Their nixpkgs
inputs follow this example's NixOS 26.05 pin, so the project uses one package set.
Rugix Admin's flake builds both its frontend and Rust service from source and
manages its Sidex code generator dependency.

The example uses upstream `nixosModules.rugix`, `lib.mkBundle`, and
`lib.mkComposeBundle`, including support for bundling prebuilt container images.

## Architecture

Each system slot consists of a read-only Nix store and a unified kernel image
(UKI). The disk uses the following partition layout:

| Partition | Label       | Format     | Purpose                                           |
| --------- | ----------- | ---------- | ------------------------------------------------- |
| 1         | boot        | vfat (ESP) | EFI system partition containing the A/B UKIs      |
| 2         | nix-store-a | squashfs   | NixOS store slot A                                |
| 3         | nix-store-b | squashfs   | NixOS store slot B                                |
| 4         | root        | ext4       | Persistent state, Rugix Apps, and device identity |

systemd-boot selects `nixos-a.efi` or `nixos-b.efi`. A generator in the initial
RAM disk (initrd) reads the `LoaderEntrySelected` EFI variable and mounts the
corresponding Nix store slot. Missing or unrecognized boot entries cause the
generator to fail instead of guessing a slot; the selected store mount is a
required dependency of the initrd filesystem target. Rugix writes an update to
the spare system and boot slots, marks that boot group for a one-shot boot, and
commits it only after the updated system is known to work.

Rugix Apps stores its generations and application data on the persistent root
partition. The example's Docker data also lives there. Its recovery service
waits for Docker and completes interrupted app transitions after every boot.
System updates replace only the immutable NixOS slots, so container generations
and application data survive operating-system updates and rollback.

Rugix Admin listens on the loopback interface and talks to the privileged Rugix
Ctrl daemon. The daemon policy grants only system commit, system reboot, and
application lifecycle operations. Factory reset remains disabled because this
layout deliberately has no Rugix data or configuration partition.

The Nexigon Agent starts without credentials and exposes its pairing endpoint on
port 6947. After pairing, it connects to Nexigon and exports loopback-only Rugix
Admin and the example Python web app through Nexigon's secure remote access
path.

## Run the Interactive Demo

On Linux, run:

```console
nix run
```

This starts the NixOS integration-test driver with two QEMU machines:

- `server` provides DHCP, DNS, and nginx hosting the system and app bundles.
- `appliance` boots the real raw A/B image and is controlled over SSH from the
  server.

The driver opens a Python REPL with helpers for the complete lifecycle:

```python
start_demo()
wait_ssh()
ssh("rugix-ctrl system info")

install_app(1)
app_page()

install_app(2)
app_page()
rollback_app()
activate_app(2)

install_update("http://update-server/update.rugixb")
reboot_and_commit("b")

install_update("http://update-server/update-delta.rugixb")
reboot_and_commit("a")

appliance_shell()
```

Type `exit` to leave the appliance and return to the Python prompt. The helper
uses the NixOS test framework's interactive-only VSOCK relay, so it does not
consume the test driver's command channel. The appliance itself still boots the
raw production-style image.

The app helper verifies each bundle against the hash produced during its Nix
build. System-update helpers disable signature verification only for locally
generated bundles on the private test network. Production systems should use a
trusted bundle hash or signing certificate for every bundle.

### Pair the Appliance with Nexigon

Create a pairing key in the Nexigon EU instance, start the machines, and paste
the UI's complete pairing value into the hidden REPL prompt:

```python
start_demo()
wait_ssh()
provision_nexigon()
# Enter the pairing value at the hidden "Nexigon pairing value:" prompt.
```

The helper copies the value to the server VM through a temporary mode-0600 file,
submits it to the appliance, and removes the file. The value is neither echoed
nor recorded in the REPL history. The pairing value may contain only a key. In
that case, the agent tries the configured European and US Nexigon endpoints.
Provisioned credentials are stored on the persistent root partition and are not
placed in the Nix store. On success, the helper returns the paired device ID and
Hub URL after verifying that the agent stored its credentials.

Before pairing, check the provisioning endpoint with:

```python
server.succeed("curl --fail http://192.168.1.100:6947/")
```

After pairing, the endpoint closes and the agent connects to Nexigon. Useful
service checks from the interactive driver include:

```python
ssh("curl --fail http://127.0.0.1:7492/")
ssh("test -s /var/lib/nexigon/agent/credentials.json")
ssh("systemctl status rugix-admin.service")
ssh("systemctl status nexigon-agent.service")
```

## Run the Automated Test

The NixOS integration test performs a complete lifecycle:

1. Boot v1 in group A and verify Rugix Admin, Nexigon provisioning, Docker, and
   Docker Compose.
2. Install version 1 of the Python web app and verify its health check and HTTP
   page.
3. Install app version 2, roll back to version 1, reactivate version 2, and
   verify that the persistent start count increases across every transition.
4. Install the v2 full system bundle and trial-boot group B.
5. Reboot without committing, verify fallback to A, then trial-boot B again,
   commit it, and verify app recovery and Admin.
6. Install the v3 delta, reboot into group A, and commit it.
7. Verify the container app and Nexigon provisioning again after both system
   updates.

Run the formatting, app-bundle, and integration checks with:

```console
nix flake check
```

The checks also exercise slot selection with both valid EFI entries and missing,
empty, and unsupported entries.

Run only the lifecycle test on x86-64 with:

```console
nix build .#checks.x86_64-linux.update-test
```

Linux with KVM is recommended for the integration test.

The [Python web app](apps/python-web-server/README.md) is also a standalone flake.
It can be copied and built independently of the appliance. The appliance consumes
its `lib.mkApp` function, while the reusable Compose packaging helper lives in
the upstream Rugix flake.

## Build the Artifacts

Build the initial disk image:

```console
nix build .#image-v1
nix build .#image-v1-x86_64
nix build .#image-v1-aarch64
```

Build the system update bundles:

```console
nix build .#update-v2
nix build .#update-v3
nix build .#update-v3-delta
```

Build both generations of the example Rugix App:

```console
nix build .#python-web-app-v1
nix build .#python-web-app-v2
```

Use `python-web-app-v1-x86_64` or `python-web-app-v1-aarch64` to select an app
bundle's target architecture explicitly. Version 2 provides the same suffixes.

Architecture-specific image and update variants use the `-x86_64` and
`-aarch64` suffixes. For example,
`nix build .#update-v3-delta-aarch64` creates an AArch64 delta bundle.
The upstream Rugix and Nexigon flakes provide native packages per target
system, so cross-architecture images require a compatible native or remote
builder for those target packages.

## Customize the Appliance

`nixosConfigurations.appliance` is the configuration used directly by the image
and update packages. It is headless, keeps the firewall enabled, and has no SSH,
password login, or autologin. It enables Nexigon's pairing endpoint and opens
only its port so a new appliance can be provisioned. Test artifacts extend this
configuration with `test-extras.nix`.

For example, extend the appliance with your own SSH key:

```nix
rugix-example.nixosConfigurations.appliance.extendModules {
  modules = [
    {
      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          PermitRootLogin = "prohibit-password";
        };
      };
      users.users.root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 REPLACE_WITH_YOUR_PUBLIC_KEY"
      ];
    }
  ];
}
```

Keep `system.stateVersion` fixed when upgrading devices with existing persistent
state. Changing the NixOS input does not require changing this compatibility
setting. The root partition is shared by both slots, so an OS rollback does not
roll back application data or reverse state migrations.

## Use the Upstream NixOS Modules

The appliance imports its service modules directly from the Rugix, Rugix Admin,
and Nexigon inputs. For your own system, declare those inputs as shown in
[`flake.nix`](./flake.nix), then import their modules and package overlays:

```nix
nixosConfigurations.device = inputs.nixpkgs.lib.nixosSystem {
  modules = [
    inputs.rugix.nixosModules.rugix
    inputs.rugix-admin.nixosModules.rugix-admin
    inputs.nexigon.nixosModules.nexigon-agent
    {
      nixpkgs.overlays = [
        inputs.rugix.overlays.default
        inputs.rugix-admin.overlays.default
        inputs.nexigon.overlays.default
      ];
      services.rugix = {
        apps.dockerCompose.enable = true;
        daemon.features.appLifecycle = true;
      };
      services.rugix-admin.enable = true;
      services.nexigon-agent = {
        enable = true;
        provisioning.enable = true;
      };
    }
    ./configuration.nix
  ];
};
```

Supply the device platform, storage layout, and Rugix boot settings in your
`configuration.nix`.

`services.rugix-admin.enable` also enables Rugix Ctrl and its privileged daemon,
but it does not grant optional privileged operations. Enable only the daemon
features the device needs.

`services.rugix.apps.dockerCompose.enable` enables Docker, declares its Compose
runtime capability to Rugix, and orders app recovery after Docker. Leave it
disabled for binary or generic apps that do not use containers.

`services.nexigon-agent.settings` is serialized through Nix and is therefore
world-readable in the Nix store. Do not put a deployment token there. Use the
provisioning workflow or install a private credentials file under the configured
agent data path.

## Understand the Implementation

[`system-configuration/configuration.nix`](./system-configuration/configuration.nix)
is the small top-level appliance configuration. It imports the image, Rugix
integration, and update-bundle modules.

[`system-configuration/image.nix`](./system-configuration/image.nix) defines the
partition layout, boot files, and initrd slot-selection generator.

[`system-configuration/update.nix`](./system-configuration/update.nix) enables
the reusable modules and supplies the example's boot groups, Admin daemon
policy, Nexigon provisioning, and remote-access exports.

[`system-configuration/update-package.nix`](./system-configuration/update-package.nix)
selects the NixOS system image and UKI and packages them with upstream
`lib.mkBundle`. Payload selection, delivery slots, and block encoding remain
appliance configuration.

[`apps/python-web-server`](./apps/python-web-server/) defines the Python server,
its status page, the Nix-built container image, and the two self-contained
Docker Compose app bundles.

Upstream [`nixosModules.rugix`](https://github.com/rugix/rugix/blob/main/nix/nixos-module.md)
provides Rugix Ctrl, Rugix Apps recovery, and privileged daemon options.

Upstream [`nixosModules.rugix-admin`](https://github.com/rugix/rugix-admin/blob/main/nix/README.md) provides the
local web interface without exposing it on the network by default.

Upstream [`nixosModules.nexigon-agent`](https://github.com/nexigon/nexigon/blob/main/nix/README.md) provides
the agent, a private runtime configuration file, persistent credentials, and
pairing-key provisioning.

[`system-configuration/test-extras.nix`](./system-configuration/test-extras.nix)
adds SSH and smaller partitions to the image used only by the test.

[`tests/update.nix`](./tests/update.nix) drives the complete lifecycle through a
separate update-server VM. [`tests/demo.nix`](./tests/demo.nix) wraps its
interactive driver with the demo helpers.

[`flake.nix`](./flake.nix) composes the upstream package flakes with the local
modules, architecture-specific artifacts, checks, and interactive driver.

## Security Notes

The test-only image configuration contains a fixed SSH key, short boot timeout,
and smaller partitions; it is used by `image-test`, not by the production image
outputs. The interactive driver additionally provides a host-local VSOCK relay
for its SSH helper. The normal appliance has no interactive login and keeps its
firewall enabled.

The example listens for Nexigon pairing requests on all interfaces and opens
port 6947 so the provisioning flow can be exercised. A product should restrict
the listener or firewall to a trusted provisioning network when appropriate.

The lifecycle test verifies app bundles with their build-time hashes. It bypasses
verification only for the locally built system-update bundles on its private
network. Production deployments must configure bundle verification and an
appropriate trust policy.

The Python server binds only to loopback on the appliance and drops privileges
after initializing its persistent counter. Its standard-library HTTP server is
appropriate for this example, not for a production web workload.

Rugix Admin remains loopback-only, and the privileged daemon exposes only the
operations explicitly enabled in `system-configuration/update.nix`.

## References

- [Rugix documentation](https://rugix.org/docs/)
- [Rugix 1.3.0 release](https://github.com/rugix/rugix/releases/tag/v1.3.0)
- [Rugix Admin 0.5.0 release](https://github.com/rugix/rugix-admin/releases/tag/v0.5.0)
- [NixOS 26.05 release](https://nixos.org/blog/announcements/2026/nixos-2605/)
- [Nexigon documentation](https://docs.nexigon.dev/)
- [systemd-repart](https://www.freedesktop.org/software/systemd/man/latest/systemd-repart.html)
- [systemd-boot](https://www.freedesktop.org/software/systemd/man/latest/systemd-boot.html)
