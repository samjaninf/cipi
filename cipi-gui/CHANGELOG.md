# Changelog

## Unreleased

### Changed

- New Cipi logo and SVG favicon (replaces generic server icon and missing tab icon)
- Package installed by Cipi CLI from GitHub VCS (`https://github.com/cipi-sh/gui`), not bundled path copy

### Added

- Initial release of Cipi GUI control panel
- Multi-server management with encrypted API token storage
- Dashboard with live server status from Cipi API
- App management (Laravel and custom): create, edit, delete, suspend, deploy, SSL, aliases, basic auth
- Database management: list, create, delete, backup, restore, password regeneration
- Async job monitoring with interactive spinner and terminal output
- Terminal-style log viewer with pagination and auto-refresh
- Admin authentication with optional TOTP two-factor authentication
- `cipi:seed-gui-user` Artisan command
