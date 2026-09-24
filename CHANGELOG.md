# Changelog

## Unreleased

- Report command exit statuses and signals, retain stdout-only failure details, and explain readiness timeouts and recovery refusals.
- Recover interrupted instances with `rails-dev stop INSTANCE`, verifying recorded process identities and preserving shared Docker services and the HTTPS proxy.
- Show instance IDs and distinguish orphaned processes, stale records, and unverified ownership in `rails-dev list`.
- Handle terminal hangup explicitly and keep cleanup running when terminal or pipe output closes.
- List active app instances across projects with their checkout paths, startup status, and public URLs; filter with `rails-dev list --root PATH`.
- Run the app's original Procfile through Foreman's public CLI, preserving its environment-file behavior, process lifecycle, and exit statuses.
- Keep Foreman's stdin open for ordinary asset watchers, including Tailwind's `--watch`.
- Remove automatic Mise, package-manager, and preparation-task discovery. Keep all preparation in app-owned hooks after service connection discovery.
- Remove `prepare`, `database_prepare`, `--skip-prepare`, and hook-based long-running process launching.
- Support explicit optional Compose, a conventional configurable web endpoint, additional declared HTTP endpoints, and app-owned `--with` process selections.
- Check startup readiness over HTTP or through app callbacks, with configurable requests, success conditions, timing, and opt-out.
- Support Ruby 3.4 and plain ERB apps without JavaScript or Docker. Separate the explicitly loaded Rails and Rails Vite helpers.
- Preserve concurrent-run isolation, local HTTPS, Tailscale sharing, and shared Compose services for the generic endpoint list.

## 0.1.0

- Start host Rails and Vite on available loopback ports.
- Start or reuse Docker Compose PostgreSQL and pass its discovered port to preparation and app processes.
- Load global and app-owned configuration using the app's Mise runtime.
- Coordinate checkout use, database preparation, and cooperating port allocation.
- Stop owned process groups on interrupts, startup failures, or web process exits.
