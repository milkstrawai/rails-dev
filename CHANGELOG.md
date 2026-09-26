# Changelog

## Unreleased

- Restore Foreman's process colors in terminals, respecting `NO_COLOR` and `TERM=dumb`.

## 0.1.0 - 2026-09-24

- Run app Procfiles through Foreman on available ports, including multiple instances from the same checkout.
- Provide local HTTPS URLs and optional Tailscale sharing.
- Start and reuse Docker Compose services on available loopback ports with explicit connection mappings.
- Support global and app configuration, lifecycle hooks, optional processes, and configurable readiness checks.
- Configure Rails hostnames, URLs, cookies, and PID files, with an optional helper for Rails Vite apps.
- List instances across projects and recover interrupted runs while preserving shared services.
- Support Ruby 3.4 and newer on macOS and Linux, with ERB or Vite apps.
