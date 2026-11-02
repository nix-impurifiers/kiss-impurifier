# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  hardwareFixture,
}:
let
  kiss = import ./kiss.nix { inherit pkgs; };
  tool =
    version:
    pkgs.runCommand "kiss-tool-${version}"
      {
        pname = "kiss-tool";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/kiss-tool
        chmod +x $out/bin/kiss-tool
      '';
  app =
    offline: version:
    impurifier.makePackage {
      pkg = tool version;
      inherit offline;
      configFiles."/etc/kiss-tool.conf" = pkgs.writeText "kiss-config" "version=${version}\n";
    };
  daemon =
    version:
    pkgs.runCommand "kiss-service-${version}"
      {
        pname = "kiss-service";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        cat > $out/bin/kiss-service <<'SCRIPT'
        #!${pkgs.busybox}/bin/sh
        echo ${version} > /var/lib/kiss-service/version
        exec ${pkgs.busybox}/bin/sleep infinity
        SCRIPT
        chmod +x $out/bin/kiss-service
      '';
  service =
    version:
    impurifier.makeOfflinePackage {
      pkg = daemon version;
      users.kiss-service = { };
      directories."/var/lib/kiss-service" = {
        owner = "kiss-service:kiss-service";
        mode = "0750";
      };
      lifecycle = {
        onInstall = ''
          /usr/bin/python3 -c "import pwd; pwd.getpwnam('kiss-service')"
          test -x /opt/nix/profile/bin/kiss-service
          echo initialized > /var/lib/kiss-service/initialized
        '';
        onUpgrade = "echo ${version} > /var/lib/kiss-service/migrated";
      };
      systemd.unit = pkgs.writeText "kiss-service.service" ''
        [Service]
        Type=exec
        User=kiss-service
        ExecStart=/opt/nix/profile/bin/kiss-service
        [Install]
        WantedBy=multi-user.target
      '';
    };
  hostDriver =
    version:
    impurifier.buildPackage {
      name = "impurifier-host-driver";
      inherit version;
      payload = hardwareFixture.driver version;

    };
  hardware = impurifier.makeOfflinePackage {
    hostDependencies = [ "impurifier-host-driver" ];
    pkg = hardwareFixture.tool;
    inherit (hardwareFixture) hardware;
  };
in
pkgs.testers.runNixOSTest {
  name = "kiss-impurifier";
  requiredFeatures = {
    kvm = false;
    devnet = false;
  };
  nodes.machine = { lib, ... }: {
    virtualisation.memorySize = 2048;
    virtualisation.useNixStoreImage = true;
    virtualisation.writableStore = true;
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    environment.systemPackages = [
      kiss
      pkgs.b3sum
      pkgs.curl
      pkgs.gnutar
      pkgs.xz
      pkgs.gzip
      pkgs.bzip2
      pkgs.file
      pkgs.util-linux
      pkgs.gnused
      pkgs.gnugrep
      pkgs.findutils
      pkgs.which
      pkgs.nix
      pkgs.python3
    ];
    systemd.tmpfiles.rules = [
      "d /usr/bin 0755 root root -"
      "d /bin 0755 root root -"
      "d /sbin 0755 root root -"
      "L+ /bin/bash - - - - ${pkgs.bash}/bin/bash"
      "L+ /bin/du - - - - ${pkgs.coreutils}/bin/du"
      "L+ /usr/bin/python3 - - - - ${pkgs.python3}/bin/python3"
      "L+ /usr/bin/nix-store - - - - ${pkgs.nix}/bin/nix-store"
      "L+ /usr/bin/systemctl - - - - ${pkgs.systemd}/bin/systemctl"
      "L+ /usr/bin/systemd-sysusers - - - - ${pkgs.systemd}/bin/systemd-sysusers"
      "L+ /usr/bin/systemd-tmpfiles - - - - ${pkgs.systemd}/bin/systemd-tmpfiles"
    ];
    nix.settings.substituters = lib.mkForce [ ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /tmp/packages")
    machine.succeed("cp ${app false "1"}/*.tar.gz ${app true "1"}/*.tar.gz ${app true "2"}/*.tar.gz ${service "1"}/*.tar.gz ${service "2"}/*.tar.gz ${hostDriver "1"}/*.tar.gz ${hostDriver "2"}/*.tar.gz ${hardware}/*.tar.gz /tmp/packages/")
    machine.succeed("cp -rL /etc/systemd/system /tmp/systemd-system; chmod -R u+w /tmp/systemd-system; rm /etc/systemd/system; mv /tmp/systemd-system /etc/systemd/system; systemctl daemon-reload")
    machine.succeed("systemctl stop dhcpcd; ip link set eth0 down")
    env = "env LOGNAME=root KISS_PROMPT=0 KISS_CHK=sha256sum "
    install = env + "/usr/sbin/kiss-impurifier install "
    remove = env + "/usr/sbin/kiss-impurifier remove "
    machine.succeed(env + "kiss install ${
      impurifier.buildPackage {
        name = "nix";
        version = "1";
        payload =
          pkgs.runCommand "nix-inventory" { }
            "mkdir -p $out/usr/share/kiss-fixture; touch $out/usr/share/kiss-fixture/nix";
      }
    }/*.tar.gz ${
      impurifier.buildPackage {
        name = "python3";
        version = "1";
        payload =
          pkgs.runCommand "python-inventory" { }
            "mkdir -p $out/usr/share/kiss-fixture; touch $out/usr/share/kiss-fixture/python";
      }
    }/*.tar.gz ${impurifier.runtimePackage}/*.tar.gz")
    machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
    with subtest("native script failure preserves the published profile"):
        before = machine.succeed("readlink /opt/nix/profile").strip()
        code, output = machine.execute(install + "/tmp/packages/kiss-tool@1-*_net.tar.gz 2>&1")
        assert "nix-profile-engine:" in output, output
        assert machine.succeed("readlink /opt/nix/profile").strip() == before
    with subtest("offline upgrade and native configuration policy"):
        machine.succeed(install + "/tmp/packages/kiss-tool@1-*_offline.tar.gz")
        machine.succeed("test $(/opt/nix/profile/bin/kiss-tool) = 1")
        machine.succeed("echo local > /etc/kiss-tool.conf")
        machine.succeed(install + "/tmp/packages/kiss-tool@1-*_net.tar.gz")
        machine.succeed(install + "/tmp/packages/kiss-tool@2-*_offline.tar.gz")
        machine.succeed("grep local /etc/kiss-tool.conf; test $(/opt/nix/profile/bin/kiss-tool) = 2")
    with subtest("end-of-command reconciliation batches native installs"):
        output = machine.succeed(install + "${
          impurifier.makeOfflinePackage {
            pkg = pkgs.hello;
            name = "batch-a";
            version = "1";
          }
        }/*.tar.gz ${
          impurifier.makeOfflinePackage {
            pkg = pkgs.hello;
            name = "batch-b";
            version = "1";
          }
        }/*.tar.gz")
        assert output.count("activated ") == 1, output
        machine.succeed("/opt/nix/profile/bin/hello | grep Hello")
        machine.succeed(remove + "batch-a batch-b")
    with subtest("native upgrades preserve service admin intent"):
        machine.succeed(install + "/tmp/packages/kiss-service@1-*.tar.gz")
        machine.wait_for_unit("kiss-service.service")
        machine.wait_until_succeeds("grep '^1$' /var/lib/kiss-service/version")
        machine.succeed("grep initialized /var/lib/kiss-service/initialized; test $(stat -c %U /var/lib/kiss-service) = kiss-service")
        output = machine.succeed(install + "/tmp/packages/kiss-service@2-*.tar.gz")
        assert output.count("activated ") == 1, output
        machine.wait_until_succeeds("grep '^2$' /var/lib/kiss-service/version")
        machine.succeed("grep '^2$' /var/lib/kiss-service/migrated")
        machine.succeed("systemctl disable --now kiss-service.service")
        machine.succeed(install + "/tmp/packages/kiss-service@1-*.tar.gz")
        machine.fail("systemctl is-active --quiet kiss-service.service")
        machine.fail("systemctl is-enabled --quiet kiss-service.service")
        machine.succeed("systemctl enable --now kiss-service.service")
        machine.succeed(remove + "kiss-service")
        machine.fail("systemctl is-active --quiet kiss-service.service")
    with subtest("end-of-command hook refreshes unrelated native driver changes"):
        code, output = machine.execute(install + "/tmp/packages/hardware-tool@*.tar.gz 2>&1")
        assert code != 0 and "impurifier-host-driver" in output, output
        machine.succeed(install + "/tmp/packages/impurifier-host-driver@1-*.tar.gz /tmp/packages/hardware-tool@*.tar.gz")
        machine.succeed("/opt/nix/profile/bin/hardware-tool | grep '^1$'")
        machine.succeed(install + "/tmp/packages/impurifier-host-driver@2-*.tar.gz")
        machine.succeed("/opt/nix/profile/bin/hardware-tool | grep '^2$'")
        machine.succeed(remove + "hardware-tool impurifier-host-driver")
    with subtest("foreign ROOT scripts cannot activate the host"):
        before = machine.succeed("readlink /opt/nix/profile").strip()
        code, output = machine.execute(env + "KISS_ROOT=/tmp/foreign-root KISS_FORCE=1 /usr/sbin/kiss-impurifier install /tmp/packages/kiss-tool@1-*_offline.tar.gz 2>&1")
        assert "foreign KISS_ROOT cannot activate the host" in output, output
        assert machine.succeed("readlink /opt/nix/profile").strip() == before
    with subtest("native removal and GC preserve edited configuration"):
        machine.succeed("nix-store --gc; test $(/opt/nix/profile/bin/kiss-tool) = 2")
        machine.succeed(remove + "kiss-tool")
        machine.fail("test -e /opt/nix/profile/bin/kiss-tool")
        machine.succeed("grep local /etc/kiss-tool.conf")
        machine.succeed("/usr/sbin/nix-profile-engine prune --keep 0; nix-store --gc; test -d /opt/nix/profile")
  '';
}
