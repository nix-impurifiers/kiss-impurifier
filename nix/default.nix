# SPDX-License-Identifier: MIT
{
  pkgs,
  coreSrc,
  sourceInfo ? { },
}:
let
  inherit (pkgs) lib;
  core = import (coreSrc + "/nix") {
    inherit pkgs;
    sourceInfo = {
      # Native updates must include adapter-only releases, not just engine pins.
      lastModified = pkgs.lib.max (if builtins.isAttrs coreSrc then coreSrc.lastModified or 0 else 0) (
        if builtins.isAttrs sourceInfo then sourceInfo.lastModified or 0 else 0
      );
    };
    namespace = "kiss-impurifier";
  };
  hook = pkgs.writeText "kiss-impurifier-hook" ''
    #!/bin/sh
    set -eu
    if [ -n "''${KISS_ROOT:-}" ] && [ "$KISS_ROOT" != / ]; then
      echo 'kiss-impurifier: foreign KISS_ROOT cannot activate the host' >&2
      exit 1
    fi
    case "$1" in
      pre-install)
        required="$3/var/db/kiss/installed/$2/impurifier-runtime-version"
        if [ -f "$required" ]; then
          /usr/bin/python3 -c '
    from pathlib import Path
    import sys
    version = lambda path: tuple(map(int, Path(path).read_text().strip().split(".")))
    if version("/usr/share/kiss-impurifier/runtime-version") < version(sys.argv[1]):
        sys.exit("kiss-impurifier: upgrade the runtime first")
    ' "$required"
        fi
        ;;
      SIGEXIT)
        [ "$(id -u)" = 0 ] || exit 0
        [ ! -x /usr/sbin/nix-profile-engine ] || /usr/sbin/nix-profile-engine reconcile
        ;;
    esac
  '';
  wrapper = pkgs.writeText "kiss-impurifier" ''
    #!/bin/sh
    set -eu
    case "''${1:-}" in
      i|install|r|remove|U|upgrade) ;;
      *) exec kiss "$@" ;;
    esac
    export KISS_HOOK="''${KISS_HOOK:+$KISS_HOOK:}/usr/sbin/kiss-impurifier-hook"
    exec kiss "$@"
  '';
  buildPackage =
    {
      name,
      version,
      payload,
      release ? "1",
      dependencies ? [ ],
      requiredRuntime ? null,
      postInstall ? "",
    }:
    assert lib.assertMsg (
      builtins.match "[a-z0-9][a-z0-9+_.-]*" name != null
      && lib.all (v: builtins.match "[A-Za-z0-9_.+]+" v != null) [
        version
        release
      ]
    ) "invalid KISS package metadata";
    assert lib.assertMsg (lib.all (
      v: builtins.match "[a-z0-9][a-z0-9+_.-]*" v != null
    ) dependencies) "invalid KISS dependency name";
    pkgs.runCommand "${name}-${version}-${release}-kiss-package"
      {
        nativeBuildInputs = [
          pkgs.gnutar
          pkgs.gzip
          pkgs.python3
          pkgs.b3sum
        ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
        passthru.nativeName = name;
        passthru.filename = "${name}@${version}-${release}.tar.gz";
      }
      ''
        mkdir -p root/var/db/kiss/installed/${name} $out
        cp -r ${payload}/. root/
        chmod -R u+w root
        database=root/var/db/kiss/installed/${name}
        printf '%s %s\n' ${lib.escapeShellArg version} ${lib.escapeShellArg release} > "$database/version"
        printf '%s' ${
          lib.escapeShellArg (lib.concatMapStringsSep "" (v: "${v}\n") dependencies)
        } > "$database/depends"
        ${lib.optionalString (
          requiredRuntime != null
        ) "echo ${lib.escapeShellArg requiredRuntime} > \"$database/impurifier-runtime-version\""}
        ${lib.optionalString (postInstall != "") ''
          cat > "$database/post-install" <<'SCRIPT'
          #!/bin/sh
          set -eu
          ${postInstall}
          SCRIPT
          chmod 755 "$database/post-install"
        ''}
        touch "$database/manifest"
        if [ -d root/etc ]; then touch "$database/etcsums"; fi
        python3 - <<'PYTHON'
        from pathlib import Path
        root = Path('root')
        entries = ['/' + str(p.relative_to(root)) + ('/' if p.is_dir() and not p.is_symlink() else "") for p in root.rglob('*')]
        (root / 'var/db/kiss/installed/${name}/manifest').write_text('\n'.join(sorted(entries, reverse=True)) + '\n')
        PYTHON
        if [ -d root/etc ]; then
          (cd root; find etc -type f -exec b3sum {} + | sed 's,  etc/,  /etc/,') > "$database/etcsums"
        fi
        tar -C root --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner -czf $out/${name}@${version}-${release}.tar.gz .
      '';
  makePackage =
    args@{
      pkg,
      release ? "1",
      hostDependencies ? [ ],
      ...
    }:
    let
      payload = core.makePayload (
        builtins.removeAttrs args [
          "release"
          "hostDependencies"
        ]
      );
    in
    buildPackage {
      name = payload.name;
      inherit (payload) version;
      inherit payload;
      release = "${release}_${if payload.offline then "offline" else "net"}";
      dependencies = [ "kiss-impurifier" ] ++ hostDependencies;
      requiredRuntime = core.runtimeVersion;
    };
  makeRuntimePackage =
    {
      nixDependency ? "nix",
      pythonDependency ? "python3",
    }:
    buildPackage {
      name = "kiss-impurifier";
      version = core.runtimeVersion;
      dependencies = [
        nixDependency
        pythonDependency
      ];
      payload = pkgs.runCommand "kiss-impurifier-runtime-payload" { } ''
        mkdir -p $out
        cp -r ${core.makeRuntimeTree { }}/. $out/
        chmod -R u+w $out
        install -Dm755 ${hook} $out/usr/sbin/kiss-impurifier-hook
        install -Dm755 ${wrapper} $out/usr/sbin/kiss-impurifier
        mkdir -p $out/usr/share/kiss-impurifier
        echo ${core.runtimeVersion} > $out/usr/share/kiss-impurifier/runtime-version
      '';
      postInstall = "/usr/sbin/nix-profile-engine reconcile";
    };
  makeRepository =
    { packages }:
    assert lib.assertMsg (
      lib.length (lib.unique (map (p: p.nativeName) packages)) == lib.length packages
    ) "choose one version/flavor per native repository name";
    pkgs.runCommand "kiss-impurifier-repository"
      {
        nativeBuildInputs = [
          pkgs.gnutar
          pkgs.gzip
        ];
      }
      ''
        mkdir -p $out
        ${lib.concatMapStringsSep "\n" (package: ''
          mkdir -p $out/${package.nativeName}
          for field in version depends; do
            tar -xOzf ${package}/${lib.escapeShellArg package.filename} ./var/db/kiss/installed/${package.nativeName}/$field > $out/${package.nativeName}/$field
          done
          cat > $out/${package.nativeName}/build <<'SCRIPT'
          #!/bin/sh
          # SPDX-License-Identifier: MIT
          set -eu
          tar -xzf ${package}/${lib.escapeShellArg package.filename} -C "$1"
          SCRIPT
          chmod 755 $out/${package.nativeName}/build
        '') packages}
      '';

in
{
  inherit (core)
    engine
    offlineCache
    unit
    runtimeVersion
    ;
  inherit
    buildPackage
    makePackage
    makeRuntimePackage
    makeRepository
    ;
  runtimePackage = makeRuntimePackage { };
  makeNetPackage = args: makePackage (args // { offline = false; });
  makeOfflinePackage = args: makePackage (args // { offline = true; });
}
