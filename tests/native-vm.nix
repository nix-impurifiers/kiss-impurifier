# SPDX-License-Identifier: MIT
{ pkgs, impurifier }:
let
  client = import ./kiss.nix { inherit pkgs; };
  app =
    version:
    impurifier.makeNativePackage {
      name = "native-proof";
      inherit version;
      payload = pkgs.runCommand "native-proof-tree-${version}" { } ''
        mkdir -p $out/usr/bin $out/etc
        cp ${pkgs.pkgsStatic.busybox}/bin/busybox $out/usr/bin/busybox
        echo ${version} > $out/etc/native-proof-version
        echo ${version} > $out/etc/native-proof-local
      '';
    };
in
pkgs.testers.runNixOSTest {
  name = "kiss-native-payload";
  requiredFeatures.kvm = false;
  requiredFeatures.devnet = false;
  nodes.machine = { lib, ... }: {
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    environment.systemPackages = [
      client
      pkgs.b3sum
    ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /srv/native/var/db/kiss/installed /tmp/kiss-cache")
    machine.succeed("env LOGNAME=root KISS_PROMPT=0 KISS_ROOT=/srv/native KISS_CACHE_DIR=/tmp/kiss-cache kiss install ${app "1"}/*.tar.gz")
    machine.succeed("chroot /srv/native /usr/bin/busybox echo native-execution | grep native-execution")
    machine.succeed("test ! -e /srv/native/nix; grep '^1$' /srv/native/etc/native-proof-version")
    machine.succeed("echo local > /srv/native/etc/native-proof-local")
    machine.succeed("env LOGNAME=root KISS_PROMPT=0 KISS_ROOT=/srv/native KISS_CACHE_DIR=/tmp/kiss-cache kiss install ${app "2"}/*.tar.gz")
    machine.succeed("grep '^2$' /srv/native/etc/native-proof-version && grep '^local$' /srv/native/etc/native-proof-local && grep '^2$' /srv/native/etc/native-proof-local.new")
    machine.succeed("env LOGNAME=root KISS_PROMPT=0 KISS_ROOT=/srv/native KISS_CACHE_DIR=/tmp/kiss-cache kiss remove native-proof")
    machine.succeed("test ! -e /srv/native/usr/bin/busybox; test ! -e /srv/native/etc/native-proof-version; test ! -e /srv/native/nix")
  '';
}
