# ADR-0001 — Monorepo boundaries

**Status:** accepted. **Original decision:** 22 October 2026. **Starter update:** 23 October 2026.

Use one repository with `ios-ui/`, `ios-backend/`, `server/`, `contracts/` and `docs/`. iOS Backend means non-UI code running on the iPhone, not the remote server.

VIPER modules live in iOS UI and share entities/repository interfaces from Domain. CompositionRoot wires Data implementations. The starter enforces Domain → no Data/UI imports through separate Swift package targets; Data depends on Domain. Application/Platform remain reserved until required.

A contract change can span all areas in one PR. Each runtime has its own tooling. No monorepo task orchestrator is needed for the starter. See [Architecture](../architecture.md).
