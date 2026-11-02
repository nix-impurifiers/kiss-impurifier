# Commands

```sh
nix flake check -L
nix fmt
nix build ".#hello-offline"
```

Publish core changes, converge pins, and test published inputs before landing. Temporary local core overrides must not be committed.
