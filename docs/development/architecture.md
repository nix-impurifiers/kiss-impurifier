# Architecture

Archives contain native installed-database manifests, dependency names, versions and configuration checksums. The supported KISS_HOOK SIGEXIT event drives activation after native mutations. A thin wrapper preserves existing user hooks. Pre-install validates minimum runtime metadata before replacing native files. KISS can disable EXIT handling during failed native transactions; recovery must repair inventory and reconcile. Engine publication remains atomic, not a rollback of native files.
