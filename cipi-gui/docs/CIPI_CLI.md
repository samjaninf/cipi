# Cipi CLI integration

This package ships ready-to-copy stubs under `stubs/cipi-cli/` for the [cipi-sh/cipi](https://github.com/cipi-sh/cipi) repository.

## Files to add in `cipi-sh/cipi`

| Action | Path |
|--------|------|
| Copy | `stubs/cipi-cli/lib/gui.sh` → `lib/gui.sh` |
| Edit | Main `cipi` router |
| Edit | `setup.sh` installer |

## 1. Router (`cipi`)

Add help text and command dispatch:

```bash
# In help / usage section:
#   gui <domain>     Configure web control panel (requires cipi api on managed servers)

# In case statement:
gui) require_root; source "${CIPI_LIB}/gui.sh"; gui_command "$@" ;;
```

## 2. Installer (`setup.sh`)

The **`cipi/gui`** Composer package is **not** bundled in the Cipi CLI repo. It is installed at runtime from GitHub:

```bash
# https://github.com/cipi-sh/gui — handled by lib/gui.sh (Composer VCS)
```

## 3. Server paths

| Resource | Path |
|----------|------|
| Laravel host | `/opt/cipi/gui` |
| Package (Composer) | `/opt/cipi/gui/vendor/cipi/gui` |
| Config (vault) | `/etc/cipi/gui.json` |
| Nginx vhost | `/etc/nginx/sites-available/cipi-gui` |
| FPM pool | `/etc/php/8.5/fpm/pool.d/cipi-gui.conf` |
| Cron | `/etc/cron.d/cipi-gui` |

## 4. Usage on server

```bash
# Requires cipi api on servers you want to manage
cipi gui gui.example.com
cipi gui ssl
cipi gui status
cipi gui update
cipi gui upgrade
cipi gui remove
cipi gui fix-permissions
```

## 5. Differences from `cipi api`

| | API | GUI |
|---|-----|-----|
| Auth | Sanctum tokens | Session + optional 2FA |
| Queue worker | Required (`cipi-queue.service`) | Not required (polls remote API jobs) |
| `SESSION_DRIVER` | `array` | `file` |
| Seed command | `cipi:seed-user` | `cipi:seed-gui-user` |
| Package source | Bundled `/opt/cipi/cipi-api` | GitHub VCS `cipi-sh/gui` |
| Depends on | Cipi CLI sudoers | **Remote** `cipi api` on managed servers |
