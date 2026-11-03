# Testing

A QEMU NixOS guest runs the actual pinned kiss-community shell implementation. Native inventory entries describe already-present Nix and Python; they do not install either. Application closures are absent initially and networking is disabled. Tests cover dependencies, configuration, batching, service lifecycle/admin intent, arbitrary driver updates through the global hook, foreign-root safety, removal and rooted GC. Source recipe and full KISS boot coverage remain separate.

Native-payload coverage installs, executes, upgrades and removes a static
producer-prepared payload in a target root without `/nix`. The bundled variant
repeats the full original lifecycle suite with actual static Nix and an
incompatible external candidate.
Configuration tests require native 33-byte BLAKE3 digest lines in manifest
order, upgrade unchanged files and retain edited files with `.new` candidates.
