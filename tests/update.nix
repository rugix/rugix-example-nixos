{
  app-v1-bundle,
  app-v2-bundle,
  image-test,
  v2-bundle,
  v3-delta-bundle,
  ...
}:

{
  name = "rugix-ota-update";

  globalTimeout = 1800;

  # Give the interactive driver an out-of-band SSH route to the raw appliance
  # without changing the automated test or the production appliance image.
  interactive.sshBackdoor.enable = true;

  nodes = {
    # `pkgs` here is the server node's own package set, so the
    # `ssh-to-appliance` wrapper is built for the server's platform.
    # Pulling it from a top-level argument would wrongly use the build
    # platform's packages in a cross-compilation scenario.
    server =
      { pkgs, ... }:
      let
        ssh-to-appliance = pkgs.writeShellScriptBin "ssh-to-appliance" ''
          exec ${pkgs.openssh}/bin/ssh \
            -F /dev/null \
            -i /etc/ssh-to-appliance-key \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            -o ConnectTimeout=10 \
            root@192.168.1.100 \
            "$@"
        '';
      in
      {
        environment.systemPackages = [ ssh-to-appliance ];
        environment.etc."ssh-to-appliance-key" = {
          source = ./test-key;
          mode = "0600";
        };

        services.nginx = {
          enable = true;
          virtualHosts."default" = {
            default = true;
            root = pkgs.runCommand "rugix-www" { } ''
              mkdir -p "$out"
              ln -s ${app-v1-bundle}/python-web-server.rugixb "$out/python-web-app-v1.rugixb"
              ln -s ${app-v1-bundle}/python-web-server.rugixb-hash "$out/python-web-app-v1.rugixb-hash"
              ln -s ${app-v2-bundle}/python-web-server.rugixb "$out/python-web-app-v2.rugixb"
              ln -s ${app-v2-bundle}/python-web-server.rugixb-hash "$out/python-web-app-v2.rugixb-hash"
              ln -s ${v2-bundle}/update.rugixb "$out/update.rugixb"
              ln -s ${v3-delta-bundle}/update.rugixb "$out/update-delta.rugixb"
            '';
          };
        };

        services.dnsmasq = {
          enable = true;
          settings = {
            interface = [ "eth1" ];
            bind-interfaces = true;
            dhcp-range = [ "192.168.1.100,192.168.1.150,12h" ];
            # Pin the appliance to a known IP. The NixOS test driver assigns
            # MACs as 52:54:00:12:<net>:<node>; eth0 on the appliance (node 1
            # on the test network) gets 52:54:00:12:01:01.
            dhcp-host = [ "52:54:00:12:01:01,192.168.1.100" ];
            # Resolve `update-server` to the server's IP so the appliance
            # doesn't need to know the address.
            address = [ "/update-server/192.168.1.2" ];
            dhcp-option = [
              "option:router,192.168.1.2"
              "option:dns-server,192.168.1.2"
            ];
            log-dhcp = true;
          };
        };

        networking.firewall.allowedTCPPorts = [
          53
          80
        ];
        networking.firewall.allowedUDPPorts = [
          53
          67
          68
        ];

        virtualisation.diskSize = 4096;
      };

    appliance = {
      # turn off everything with test instrumentation etc. and just boot
      # the image.
      virtualisation.directBoot.enable = false;
      virtualisation.useEFIBoot = true;
      virtualisation.diskImage = null;

      boot.loader.grub.enable = false;
      boot.loader.systemd-boot.enable = false;

      virtualisation.qemu.guestAgent.enable = false;
      virtualisation.memorySize = 2048;
      virtualisation.cores = 2;

      virtualisation.qemu.options = [
        "-drive"
        "file=${image-test}/appliance_1.raw,format=raw,snapshot=on,index=0"
      ];
    };
  };

  testScript = builtins.readFile ./interactive.py + ''
    # ════════════════════════════════════════════════════════════════════
    # The real test follows here.
    #
    # It walks the full A/B lifecycle, committing after each successful boot:
    #
    #   v1 (group a) --full bundle--> v2 (group b) --delta bundle--> v3 (group a)
    # ════════════════════════════════════════════════════════════════════

    def test_server_hosts_all_bundles():
        """Verify that the update server exposes every lifecycle artifact."""
        with subtest("server hosts both apps, the v2 full bundle, and the v3 delta"):
            server.succeed("curl -fsSI http://localhost/python-web-app-v1.rugixb")
            server.succeed("curl -fsSI http://localhost/python-web-app-v2.rugixb")
            server.succeed("curl -fsSI http://localhost/update.rugixb")
            server.succeed("curl -fsSI http://localhost/update-delta.rugixb")

    def test_initial_image_boots_into_group_a():
        """Verify that the factory image boots from its committed A group."""
        with subtest("v1: the initial image boots into group a"):
            wait_ssh()
            info = boot_info()
            assert info["activeGroup"] == "a" and info["defaultGroup"] == "a", info
            ssh("test -f /boot/EFI/Linux/nixos-a.efi")

    def test_management_services_and_install_app():
        """Verify management services and the complete container app lifecycle."""
        with subtest("Rugix Admin and Nexigon provisioning are available"):
            ssh("systemctl is-active --quiet rugix-admin.service")
            ssh("curl --fail --silent http://127.0.0.1:7492/ >/dev/null")
            ssh("curl --fail --silent http://127.0.0.1:6947/ | grep -q ready")

        with subtest("Docker Compose is available as a declared runtime capability"):
            server.wait_until_succeeds(
                "ssh-to-appliance -- docker info >/dev/null", timeout=120
            )
            ssh("systemctl is-active --quiet docker.service")
            ssh("docker compose version")
            ssh("grep -q 'runtime.docker-compose' /etc/rugix/components/docker-compose.toml")

        with subtest("the bundled Python image installs without registry access"):
            assert not ssh("docker image ls -q").strip()
            ssh("ip route replace unreachable default")
            install_app(1)
            assert_app("1.0.0", 1)
            image_metadata = json.loads(ssh(
                "cat /var/lib/rugix/apps/python-web-server/generations/1/images/rugix-images.json"
            ))
            bundled_image = image_metadata["images"][0]
            assert bundled_image["source"] == "docker-archive", bundled_image
            tag = bundled_image["bundleTag"]
            assert tag.startswith("localhost/rugix-apps/python-web-server/image-0:m-"), tag
            ssh(f"docker image inspect {tag}")

        with subtest("the app updates, rolls back, and retains persistent data"):
            install_app(2)
            assert_app("2.0.0", 2)
            rollback_app()
            assert_app("1.0.0", 1)
            activate_app(2)
            assert_app("2.0.0", 2)

    def test_full_bundle_switches_to_group_b():
        """Verify full system update trial, rollback, commit, and app recovery."""
        with subtest("v2: installing the full bundle switches to group b"):
            install_update("http://update-server/update.rugixb")
            ssh("test -f /boot/EFI/Linux/nixos-b.efi")
            # A trial boot must not change the committed slot. Reboot without
            # committing and verify that systemd-boot returns to the old image.
            reboot_into_spare()
            assert boot_info()["activeGroup"] == "b"
            assert boot_info()["defaultGroup"] == "a"
            server.execute("ssh-to-appliance -- systemctl reboot", timeout=20)
            server.sleep(15)
            wait_ssh()
            assert boot_info()["activeGroup"] == "a"
            assert boot_info()["defaultGroup"] == "a"
            reboot_and_commit(expected_group="b")
            assert_app("2.0.0", 2)
            ssh("systemctl is-active --quiet rugix-admin.service")

    def test_delta_bundle_switches_back_to_group_a():
        """Verify the delta system update and container app recovery in group A."""
        with subtest("v3: installing the delta bundle switches back to group a"):
            install_update("http://update-server/update-delta.rugixb")
            reboot_and_commit(expected_group="a")
            assert_app("2.0.0", 2)
            ssh("curl --fail --silent http://127.0.0.1:6947/ | grep -q ready")


    start_demo()
    test_server_hosts_all_bundles()
    test_initial_image_boots_into_group_a()
    test_management_services_and_install_app()
    test_full_bundle_switches_to_group_b()
    test_delta_bundle_switches_back_to_group_a()
  '';
}
