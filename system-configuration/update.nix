{
  services.rugix = {
    enable = true;
    apps.enable = true;
    apps.dockerCompose.enable = true;

    daemon = {
      enable = true;
      features = {
        systemCommit = true;
        systemReboot = true;
        appLifecycle = true;
      };
    };

    settings = {
      config-partition.disabled = true;
      data-partition.disabled = true;

      boot-flow = {
        type = "systemd-boot";
        entries = {
          a = "nixos-a.efi";
          b = "nixos-b.efi";
        };
      };

      slots = {
        system-a = {
          type = "block";
          partition = 2;
          immutable = true;
        };
        system-b = {
          type = "block";
          partition = 3;
          immutable = true;
        };
        boot-a = {
          type = "file";
          path = "/boot/EFI/Linux/nixos-a.efi";
        };
        boot-b = {
          type = "file";
          path = "/boot/EFI/Linux/nixos-b.efi";
        };
      };

      boot-groups = {
        a.slots = {
          system = "system-a";
          boot = "boot-a";
        };
        b.slots = {
          system = "system-b";
          boot = "boot-b";
        };
      };
    };
  };

  services.rugix-admin.enable = true;

  services.nexigon-agent = {
    enable = true;
    provisioning = {
      enable = true;
      openFirewall = true;
    };
    settings = {
      exports = [
        {
          protocol = "http";
          name = "rugix-admin";
          port = 7492;
        }
        {
          protocol = "http";
          name = "python-web-server";
          port = 8080;
        }
      ];
    };
  };
}
