# Share the automated test's topology and lifecycle helpers with the interactive demo.
{ pkgs, driver }:
let
  interactiveHelpers = pkgs.writeText "rugix-demo-startup.py" (builtins.readFile ./interactive.py);
  wrapper = pkgs.writeShellScriptBin "rugix-demo" ''
    # OpenSSH treats the VSOCK proxy target as a hostname and
    # lowercases it. Keep this runtime path lowercase so the
    # case-sensitive UNIX socket remains addressable.
    rugix_demo_runtime_dir="/tmp/rugix-demo.$$"
    ${pkgs.coreutils}/bin/mkdir -m 0700 -- "$rugix_demo_runtime_dir"

    cleanup() {
      ${pkgs.coreutils}/bin/chmod -R u+w "$rugix_demo_runtime_dir"
      ${pkgs.coreutils}/bin/rm -rf -- "$rugix_demo_runtime_dir"
    }
    trap cleanup EXIT

    ${pkgs.coreutils}/bin/mkdir -p "$rugix_demo_runtime_dir/ipython/profile_default/startup"
    ${pkgs.coreutils}/bin/ln -s ${interactiveHelpers} \
      "$rugix_demo_runtime_dir/ipython/profile_default/startup/00-rugix-demo.py"
    ${pkgs.coreutils}/bin/install -m 0600 ${./test-key} \
      "$rugix_demo_runtime_dir/ssh-key"
    export IPYTHONDIR="$rugix_demo_runtime_dir/ipython"
    export RUGIX_DEMO_SSH="${pkgs.openssh}/bin/ssh"
    export RUGIX_DEMO_SSH_CONFIG="${pkgs.systemd}/lib/systemd/ssh_config.d/20-systemd-ssh-proxy.conf"
    export RUGIX_DEMO_TEST_KEY="$rugix_demo_runtime_dir/ssh-key"
    export XDG_RUNTIME_DIR="$rugix_demo_runtime_dir"

    cat <<'EOF'

    ── Complete Rugix NixOS demo ─────────────────────────────────────

      Two VMs come up: 'server' hosts the system and app bundles;
      'appliance' runs Rugix Ctrl, Rugix Admin, and Nexigon.

      The demo helpers are loaded automatically. Start with:
        start_demo()
        wait_ssh()

      Then try:
        ssh("rugix-ctrl system info")
        provision_nexigon()
        install_app(1)
        app_page()
        install_app(2)
        rollback_app()
        install_update("http://update-server/update.rugixb")
        reboot_and_commit("b")
        appliance_shell()

    ──────────────────────────────────────────────────────────────────

    EOF
    ${driver}/bin/nixos-test-driver "$@"
  '';
in
{
  type = "app";
  program = "${wrapper}/bin/rugix-demo";
  meta.description = "Run the complete Rugix NixOS appliance demo";
}
