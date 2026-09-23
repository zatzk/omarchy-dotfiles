# Changelog

## [1.1.2] - 2026-09-22

### Security

- Move probe caches to a private runtime directory and use descriptor-relative, no-follow atomic writes and checked reads.

### Changed

- The bar hover now shows current CPU usage, available RAM, and free root-disk space.
- Entering the bar icon refreshes telemetry before the hover appears, preventing stale values from the widget's startup probe or previous panel session.
