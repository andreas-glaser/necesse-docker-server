# Changelog

All notable changes to this project are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.3] - 2025-11-07
### Fixed
- Auto-update watcher now reads SteamCMD manifests from the install directory, preventing hourly restarts when no new Necesse build is available (`entrypoint.sh`).

## [1.3.2] - 2025-10-28
### Fixed
- Container now falls back to the previous server build when SteamCMD fails (e.g. `state is 0x6`) instead of restarting in a loop, and logs where to inspect the failure (`entrypoint.sh`).

## [1.3.1] - 2025-10-27
### Added
- Image-level healthcheck matching the Compose probe so `docker run` users get liveness status (`Dockerfile`).
### Changed
- Compose service now relies on the baked-in healthcheck and enforces memory limits with `mem_limit`/`mem_reservation` so limits work outside Swarm (`docker-compose.yml`).
- README Compose example mirrors the actual service definition, listing explicit environment variables instead of `env_file` (`README.md`).
- Docker Hub overview now matches the Compose configuration and documents the built-in healthcheck and memory hints (`docs/DOCKER_HUB_OVERVIEW.md`, `docs/index.md`).

## [1.3.0] - 2025-10-24
### Added
- README badges for CI status, latest release, Docker pulls, and image size.
- Necesse trailer GIF below the badges.
### Changed
- README examples now default to the `latest` image tag and reference the bundled `docker-compose.yml` / `.env.example`.

## [1.2.0] - 2025-10-23
### Added
- Contributor documentation under `docs/` (Git workflow, commit, and release guides plus index).

## [1.1.0] - 2025-10-22
### Added
- GitHub Actions publishes Docker images to Docker Hub (`andreasgl4ser/necesse-server`) on tagged releases.
### Changed
- `docker-compose.yml` now defaults to the published Docker Hub image and accepts an optional `IMAGE_TAG`.
- README refocused on Docker Hub workflows with updated quickstart examples.

## [1.0.0] - 2025-10-22
### Added
- Automatic update watcher controlled by `AUTO_UPDATE_INTERVAL_MINUTES` that checks Steam for new builds and restarts the server.
### Changed
- Reworked README for server admins with clearer quickstart, management guidance, and streamlined feature notes.
- Auto-update now logs when periodic checks are enabled so admins know the cadence.

## [0.1.0] - 2025-10-19
### Added
- Debian-based Docker image that installs Necesse via SteamCMD and exposes configurable server flags.
- Compose file with health check, persistent data volume, and environment-driven configuration.
- Hardened entrypoint with optional auto-update, UID/GID remapping, and safe argument construction.
- Documentation and sample `.env` covering setup, updates, and troubleshooting.
- GitHub Actions CI workflow running shellcheck and docker build.
