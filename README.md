# kiss-impurifier

Native KISS archives backed by atomic, GC-rooted Nix profiles. Original code is
MIT licensed. The VM fixture preserves upstream KISS's MIT notices.

```nix
let impurifier = inputs.kiss-impurifier.lib.kiss-impurifier { inherit pkgs; };
in impurifier.makeOfflinePackage { pkg = pkgs.hello; }
```

Install the runtime with `kiss install /path/to/runtime-output/*.tar.gz`.
Nix/Python must already exist and have native provider inventory entries;
`makeRuntimePackage` accepts `nixDependency` and `pythonDependency` names.
Nix installation is deferred, not excluded.

Use `/usr/sbin/kiss-impurifier install /path/to/app-output/*.tar.gz` and
`/usr/sbin/kiss-impurifier remove app-name` for managed transactions. This thin
wrapper appends `/usr/sbin/kiss-impurifier-hook` to `KISS_HOOK`, preserving user
hooks, then executes native kiss. Alternatively configure that hook in your
own KISS_HOOK environment. **The hook is required for activation and removal**;
plain kiss without it changes native inventory only. Reconcile manually after
repair with `/usr/sbin/nix-profile-engine reconcile`. Use plain kiss to remove
the runtime itself after removing all managed applications.

The native SIGEXIT hook reconciles once after a command, including removals and
unrelated driver updates. Existing custom hooks run first. Engine failure leaves
the previous profile published, while the native filesystem may already have
changed. A failed native transaction can disable its EXIT trap; repair native
inventory and reconcile explicitly. This is activation atomicity, not native
filesystem rollback. Foreign KISS_ROOT activation is rejected.

`makeNetPackage` retains the declared installable; `makeOfflinePackage` contains
the complete closure. The same native package name uses different release
suffixes for the flavors. `makePackage` accepts the shared application arguments
plus `release` and `hostDependencies`; explicit dependencies apply to CLI tools
as well. Native KISS enforces dependency names; the pre-install hook additionally
checks the source-derived runtime version because KISS dependencies are not
versioned. These native versions do not imply SemVer releases.

Configuration uses native KISS checksums and preservation rules. Explicit
systemd, OpenRC or runit declarations use the shared host integration; consumers
supply native host dependency names. No particular KISS init choice is assumed.
`buildPackage` accepts a raw payload and dependency names without automatic
application activation.

`makeRepository { packages = [ artifact ]; }` emits native build recipes that
repack the Nix artifact. Keep the output in the Nix store and root it while
building: recipes retain artifact references. Set `KISS_PATH` to that output and
run `kiss build name`. Choose one version/flavor per name. Compilation stays in
Nix, and actual kiss owns the native package construction. Copying recipes out
of the Nix store does not make their referenced payloads portable.

`nix flake check -L` boots QEMU and executes pinned upstream kiss-community KISS
6.2.0. It tests native dependency rejection, net failure/offline recovery,
configuration preservation, batch activation, service/account lifecycle and
admin intent, unrelated native driver updates, foreign-root safety, removal and
GC. The guest kernel and outer init are NixOS; Nix is preinstalled. This is not
a complete KISS boot test. It also exercises native recipe construction.
