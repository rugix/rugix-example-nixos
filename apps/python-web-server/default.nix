{
  buildPkgs,
  mkComposeBundle,
  targetPkgs,
  version,
}:

let
  appName = "python-web-server";
  imageName = "localhost/rugix-example-nixos/${appName}";
  image = targetPkgs.dockerTools.buildLayeredImage {
    name = imageName;
    tag = version;
    contents = [ targetPkgs.python3Minimal ];
    extraCommands = ''
      mkdir -p app
      cp ${./index.html} app/index.html
      cp ${./server.py} app/server.py
    '';
    config = {
      Cmd = [
        "/bin/python3"
        "/app/server.py"
      ];
      Env = [
        "APP_VERSION=${version}"
        "PYTHONDONTWRITEBYTECODE=1"
        "PYTHONUNBUFFERED=1"
      ];
      ExposedPorts."8080/tcp" = { };
      Labels = {
        "org.opencontainers.image.title" = "Rugix Python Web Server";
        "org.opencontainers.image.version" = version;
      };
      WorkingDir = "/app";
    };
  };
  compose.services.web = {
    image = "${imageName}:${version}";
    restart = "unless-stopped";
    read_only = true;
    init = true;
    security_opt = [ "no-new-privileges:true" ];
    cap_drop = [ "ALL" ];
    cap_add = [
      "SETGID"
      "SETUID"
    ];
    ports = [ "127.0.0.1:8080:8080" ];
    volumes = [ "\${RUGIX_APP_DATA_DIR}:/data" ];
    tmpfs = [ "/tmp:size=16m,mode=1777" ];
    healthcheck = {
      test = [
        "CMD"
        "python3"
        "-c"
        "from urllib.request import urlopen; response = urlopen('http://127.0.0.1:8080/', timeout=2); assert response.status == 200"
      ];
      interval = "2s";
      timeout = "2s";
      retries = 30;
    };
  };
  componentFile = (buildPkgs.formats.toml { }).generate "${appName}-${version}-component.toml" {
    id = "app.${appName}";
    inherit version;
    claims = [ { id = "network.tcp.8080"; } ];
    requires = [
      {
        id = "runtime.docker-compose";
        version = ">=2.20";
      }
    ];
  };
in
mkComposeBundle {
  name = appName;
  inherit version compose;
  images.web = image;
  platform = "linux/${if targetPkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "amd64"}";
  components = [ componentFile ];
  healthCheckTimeout = 90;
  metadata = {
    name = "Python Web Server";
    summary = "Serve a device-local status page from a Nix-built Python container.";
    inherit version;
  };
}
