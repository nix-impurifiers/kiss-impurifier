# Testing

A QEMU NixOS guest runs the actual pinned kiss-community shell implementation. Native inventory entries describe already-present Nix and Python; they do not install either. Application closures are absent initially and networking is disabled. Tests cover dependencies, configuration, batching, service lifecycle/admin intent, arbitrary driver updates through the global hook, foreign-root safety, removal and rooted GC. Source recipe and full KISS boot coverage remain separate.
