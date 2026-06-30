#!/bin/bash
# lib/gui.sh — Cipi GUI panel provisioning (mirror lib/api.sh)
#
# Copy to cipi-sh/cipi/lib/gui.sh and wire in the main `cipi` router:
#   gui) require_root; source "${CIPI_LIB}/gui.sh"; gui_command "$@" ;;

# When sourced inside migrations/self-update, CIPI_GUI_* may already be readonly — only assign when unset.
if [[ -z "${CIPI_GUI_ROOT:-}" ]]; then
    readonly CIPI_GUI_ROOT="/opt/cipi/gui"
fi
if [[ -z "${CIPI_GUI_CONFIG:-}" ]]; then
    readonly CIPI_GUI_CONFIG="${CIPI_CONFIG}/gui.json"
fi

_gui_pkg_dir() {
    local pkg_dir="/opt/cipi/cipi-gui"
    [[ -d "${CIPI_LIB}/../cipi-gui" ]] && pkg_dir="${CIPI_LIB}/../cipi-gui"
    echo "$pkg_dir"
}

_gui_clear_host_routes() {
    local base="$1"
    echo '<?php' > "${base}/routes/web.php"
}

_gui_ensure_log_stack_env() {
    local envf="${CIPI_GUI_ROOT}/.env"
    [[ ! -f "$envf" ]] && return
    grep -q '^LOG_CHANNEL=' "$envf" \
        && sed -i 's|^LOG_CHANNEL=.*|LOG_CHANNEL=stack|' "$envf" \
        || echo 'LOG_CHANNEL=stack' >> "$envf"
    grep -q '^LOG_STACK=' "$envf" \
        && sed -i 's|^LOG_STACK=.*|LOG_STACK=single,stderr|' "$envf" \
        || echo 'LOG_STACK=single,stderr' >> "$envf"
}

_gui_ensure_session_driver_env() {
    local envf="${CIPI_GUI_ROOT}/.env"
    [[ ! -f "$envf" ]] && return
    grep -q '^SESSION_DRIVER=' "$envf" \
        && sed -i 's|^SESSION_DRIVER=.*|SESSION_DRIVER=file|' "$envf" \
        || echo 'SESSION_DRIVER=file' >> "$envf"
}

_gui_apply_sqlite_pragmas() {
    local envf="${CIPI_GUI_ROOT}/.env" db=""
    [[ ! -f "$envf" ]] && return
    grep -q '^DB_CONNECTION=sqlite' "$envf" 2>/dev/null || return
    local raw
    raw=$(grep '^DB_DATABASE=' "$envf" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '[:space:]"\r')
    [[ -z "$raw" || "$raw" == "null" ]] && raw="database/database.sqlite"
    [[ "$raw" =~ ^/ ]] && db="$raw" || db="${CIPI_GUI_ROOT}/${raw}"
    [[ -f "$db" ]] && command -v sqlite3 >/dev/null 2>&1 \
        && sqlite3 "$db" "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;" >/dev/null 2>&1 || true
}

ensure_cipi_gui_permissions() {
    [[ ! -d "${CIPI_GUI_ROOT}" ]] && return
    chown -R www-data:www-data "${CIPI_GUI_ROOT}/storage" "${CIPI_GUI_ROOT}/bootstrap/cache" 2>/dev/null || true
    chmod -R ug+rwx "${CIPI_GUI_ROOT}/storage" "${CIPI_GUI_ROOT}/bootstrap/cache" 2>/dev/null || true
    [[ -f "${CIPI_GUI_ROOT}/database/database.sqlite" ]] \
        && chown www-data:www-data "${CIPI_GUI_ROOT}/database/database.sqlite" 2>/dev/null || true
}

# ── Admin credentials (first install + reset) ────────────────────

_gui_validate_admin_email() {
    local email="$1"
    [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

_gui_validate_admin_password() {
    local pass="$1"
    [[ ${#pass} -ge 12 ]] || { echo "Password must be at least 12 characters"; return 1; }
    [[ "$pass" =~ [A-Z] ]] || { echo "Password must include an uppercase letter"; return 1; }
    [[ "$pass" =~ [a-z] ]] || { echo "Password must include a lowercase letter"; return 1; }
    [[ "$pass" =~ [0-9] ]] || { echo "Password must include a number"; return 1; }
    [[ "$pass" =~ [^a-zA-Z0-9] ]] || { echo "Password must include a special character"; return 1; }
    if [[ "$pass" =~ (.)\1\1\1\1 ]]; then
        echo "Password must not contain more than 4 identical characters in a row"
        return 1
    fi
    return 0
}

_gui_read_password() {
    local prompt="$1" var="$2"
    local _pw=""
    echo -ne "${CYAN}${prompt}${NC}: "
    if [[ -r /dev/tty ]]; then
        read -rs _pw < /dev/tty
    else
        read -rs _pw
    fi
    echo
    printf -v "$var" '%s' "$_pw"
}

_gui_prompt_admin_password() {
    local var="$1"
    local _pass="" _pass2="" err=""

    echo -e "${DIM}  Min 12 chars · upper + lower + digit + special · max 4 identical in a row${NC}"
    while true; do
        _gui_read_password "Admin password" _pass
        _gui_read_password "Confirm password" _pass2
        [[ "$_pass" == "$_pass2" ]] || { error "Passwords do not match"; continue; }
        if err=$(_gui_validate_admin_password "$_pass"); then
            printf -v "$var" '%s' "$_pass"
            return 0
        fi
        error "$err"
    done
}

_gui_prompt_admin_credentials() {
    local email="" pass="" err=""

    echo ""
    info "Create the GUI admin account"
    echo ""
    while true; do
        read_input "Admin email" "" email
        if _gui_validate_admin_email "$email"; then break; fi
        error "Invalid email address"
    done
    _gui_prompt_admin_password pass
    _GUI_ADMIN_EMAIL="$email"
    _GUI_ADMIN_PASSWORD="$pass"
}

_gui_resolve_admin_password() {
    local var="$1"
    local pass="${2:-}" err

    if [[ -n "$pass" ]]; then
        if err=$(_gui_validate_admin_password "$pass"); then
            printf -v "$var" '%s' "$pass"
            return 0
        fi
        error "$err"
        return 1
    fi

    if [[ -t 0 || -r /dev/tty ]]; then
        local pass=""
        _gui_prompt_admin_password pass
        printf -v "$var" '%s' "$pass"
        return 0
    fi

    error "Password required (--password=) or run from an interactive terminal"
    return 1
}

# ── Laravel host + cipi/gui package ─────────────────────────────

_gui_ensure_laravel_app() {
    if [[ ! -f "${CIPI_GUI_ROOT}/artisan" ]]; then
        step "Installing Laravel GUI app..."
        rm -rf /tmp/cipi-gui-build 2>/dev/null

        (cd /tmp && composer create-project laravel/laravel cipi-gui-build --no-interaction --prefer-dist 2>/dev/null) || {
            error "Failed to create Laravel app. Ensure composer is available."
            exit 1
        }

        local pkg_dir
        pkg_dir=$(_gui_pkg_dir)
        if [[ -d "$pkg_dir" ]]; then
            (cd /tmp/cipi-gui-build && composer config repositories.cipi-gui path "$pkg_dir" 2>/dev/null) || true
            (cd /tmp/cipi-gui-build && composer require cipi/gui:@dev --no-interaction 2>/dev/null) || true
        else
            (cd /tmp/cipi-gui-build && composer require cipi/gui --no-interaction 2>/dev/null) || true
        fi

        sed -i "s|^APP_ENV=.*|APP_ENV=production|" /tmp/cipi-gui-build/.env
        sed -i "s|^APP_DEBUG=.*|APP_DEBUG=false|" /tmp/cipi-gui-build/.env
        sed -i "s|^SESSION_DRIVER=.*|SESSION_DRIVER=file|" /tmp/cipi-gui-build/.env

        _gui_clear_host_routes /tmp/cipi-gui-build

        (cd /tmp/cipi-gui-build && php artisan vendor:publish --tag=cipi-gui-config --force 2>/dev/null) || true
        (cd /tmp/cipi-gui-build && php artisan key:generate --force 2>/dev/null) || true
        (cd /tmp/cipi-gui-build && php artisan migrate --force 2>/dev/null) || true

        local seed_cmd=(php artisan cipi:seed-gui-user)
        [[ -n "${_GUI_ADMIN_EMAIL:-}" ]] && seed_cmd+=(--email="${_GUI_ADMIN_EMAIL}")
        [[ -n "${_GUI_ADMIN_PASSWORD:-}" ]] && seed_cmd+=(--password="${_GUI_ADMIN_PASSWORD}")
        (cd /tmp/cipi-gui-build && "${seed_cmd[@]}") || {
            error "Failed to create GUI admin user"
            exit 1
        }

        rm -rf "${CIPI_GUI_ROOT}" 2>/dev/null
        mv /tmp/cipi-gui-build "${CIPI_GUI_ROOT}"
        chown -R www-data:www-data "${CIPI_GUI_ROOT}"
        success "Laravel GUI app + cipi/gui package"
    else
        step "Updating cipi/gui package..."
        _gui_update_package
    fi
}

_gui_update_package() {
    local pkg_dir
    pkg_dir=$(_gui_pkg_dir)
    if [[ -d "$pkg_dir" ]]; then
        (cd "${CIPI_GUI_ROOT}" && composer config repositories.cipi-gui path "$pkg_dir" 2>/dev/null) || true
    fi
    (cd "${CIPI_GUI_ROOT}" && composer update cipi/gui --no-interaction 2>/dev/null) || true
    chown -R www-data:www-data "${CIPI_GUI_ROOT}" 2>/dev/null || true
    (cd "${CIPI_GUI_ROOT}" && sudo -u www-data php artisan vendor:publish --tag=cipi-gui-config --force 2>/dev/null) || true
    (cd "${CIPI_GUI_ROOT}" && sudo -u www-data php artisan migrate --force 2>/dev/null) || true
    success "cipi/gui package updated"
}

# ── PHP-FPM + Nginx ───────────────────────────────────────────────

_gui_create_fpm_pool() {
    cat > /etc/php/8.5/fpm/pool.d/cipi-gui.conf <<EOF
[cipi-gui]
user = www-data
group = www-data
listen = /run/php/cipi-gui.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 20
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 8
pm.max_requests = 500
request_terminate_timeout = 300s
slowlog = /var/log/cipi-gui-fpm-slow.log
request_slowlog_timeout = 30s
catch_workers_output = yes
php_admin_value[error_log] = /var/log/cipi-gui-php-error.log
php_admin_value[open_basedir] = ${CIPI_GUI_ROOT}/:/tmp/:/proc/
EOF
    touch /var/log/cipi-gui-fpm-slow.log /var/log/cipi-gui-php-error.log 2>/dev/null || true
    chown www-data:adm /var/log/cipi-gui-fpm-slow.log /var/log/cipi-gui-php-error.log 2>/dev/null || true
}

_gui_create_nginx_vhost() {
    local domain="$1"
    cat > /etc/nginx/sites-available/cipi-gui <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};
    root ${CIPI_GUI_ROOT}/public;
    index index.php;
    client_max_body_size 64M;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \\.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/cipi-gui.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_read_timeout 300s;
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
    }

    location ~ /\\.(?!well-known).* {
        deny all;
    }
}
EOF
}

_gui_setup_cron() {
    cat > /etc/cron.d/cipi-gui <<EOF
# Cipi GUI — Laravel scheduler
* * * * * www-data /usr/bin/php ${CIPI_GUI_ROOT}/artisan schedule:run >> /dev/null 2>&1
EOF
    chmod 644 /etc/cron.d/cipi-gui
}

# ── Commands ────────────────────────────────────────────────────

gui_setup() {
    local domain="${1:-}"
    [[ -z "$domain" ]] && { error "Usage: cipi gui <domain>"; exit 1; }
    validate_domain "$domain" || { error "Invalid domain '${domain}'"; exit 1; }

    echo ""; info "Configuring Cipi GUI at ${domain}..."; echo ""

    mkdir -p "${CIPI_CONFIG}"
    echo "{\"domain\": \"${domain}\"}" | vault_write gui.json
    success "Config saved"

    if [[ ! -f "${CIPI_GUI_ROOT}/artisan" ]]; then
        if [[ ! -t 0 && ! -r /dev/tty ]]; then
            error "GUI first install requires an interactive terminal (admin email and password)"
            exit 1
        fi
        _gui_prompt_admin_credentials
    fi

    _gui_ensure_laravel_app
    ensure_cipi_gui_permissions

    if [[ -f "${CIPI_GUI_ROOT}/.env" ]]; then
        sed -i "s|^APP_URL=.*|APP_URL=https://${domain}|" "${CIPI_GUI_ROOT}/.env"
    fi
    _gui_ensure_log_stack_env
    _gui_ensure_session_driver_env
    _gui_apply_sqlite_pragmas

    step "PHP-FPM pool..."
    _gui_create_fpm_pool
    reload_php_fpm "8.5"
    success "PHP-FPM pool (cipi-gui)"

    step "Nginx vhost..."
    _gui_create_nginx_vhost "$domain"
    ln -sf /etc/nginx/sites-available/cipi-gui /etc/nginx/sites-enabled/cipi-gui
    reload_nginx
    success "Nginx → ${domain}"

    step "Scheduler cron..."
    _gui_setup_cron
    success "Cron (schedule:run)"

    log_action "GUI CONFIGURED: $domain"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e " ${GREEN}${BOLD}Cipi GUI configured${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e " Domain:  ${CYAN}https://${domain}${NC}"
    echo -e " Login:   ${CYAN}https://${domain}/login${NC}"
    [[ -n "${_GUI_ADMIN_EMAIL:-}" ]] && echo -e " Admin:   ${CYAN}${_GUI_ADMIN_EMAIL}${NC}"
    echo ""
    echo -e " ${BOLD}Next:${NC}  cipi gui ssl"
    echo -e "         cipi gui status"
    echo -e " ${DIM}Use the admin password you set during setup.${NC}"
    echo -e " ${DIM}Requires cipi api on managed servers + API tokens.${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    unset _GUI_ADMIN_PASSWORD
}

gui_ssl() {
    [[ ! -f "${CIPI_GUI_CONFIG}" ]] && { error "GUI not configured. Run: cipi gui <domain>"; exit 1; }
    local domain
    domain=$(vault_read gui.json | jq -r '.domain')
    [[ -z "$domain" || "$domain" == "null" ]] && { error "Domain not found in config."; exit 1; }
    step "Installing SSL for ${domain}..."
    certbot --nginx -d "${domain}" --non-interactive --agree-tos --redirect 2>/dev/null \
        || certbot --nginx -d "${domain}"
    reload_nginx
    success "SSL installed"
}

gui_update() {
    [[ ! -f "${CIPI_GUI_ROOT}/artisan" ]] && { error "Laravel GUI app not found."; exit 1; }
    step "Composer update..."
    _gui_update_package
    ensure_cipi_gui_permissions
    _gui_ensure_log_stack_env
    _gui_ensure_session_driver_env
    _gui_apply_sqlite_pragmas
    _gui_setup_cron
    reload_php_fpm "8.5"
    success "GUI updated"
}

gui_upgrade() {
    [[ ! -f "${CIPI_GUI_CONFIG}" ]] && { error "GUI not configured."; exit 1; }
    [[ ! -f "${CIPI_GUI_ROOT}/artisan" ]] && { error "Laravel GUI app not found."; exit 1; }

    local backup_dir="/tmp/cipi-gui-backup-$(date +%s)"
    mkdir -p "$backup_dir"
    [[ -f "${CIPI_GUI_ROOT}/.env" ]] && cp "${CIPI_GUI_ROOT}/.env" "${backup_dir}/.env"
    [[ -f "${CIPI_GUI_ROOT}/database/database.sqlite" ]] && cp "${CIPI_GUI_ROOT}/database/database.sqlite" "${backup_dir}/database.sqlite"

    rm -rf /tmp/cipi-gui-build 2>/dev/null
    (cd /tmp && composer create-project laravel/laravel cipi-gui-build --no-interaction --prefer-dist) || exit 1

    local pkg_dir
    pkg_dir=$(_gui_pkg_dir)
    if [[ -d "$pkg_dir" ]]; then
        (cd /tmp/cipi-gui-build && composer config repositories.cipi-gui path "$pkg_dir")
        (cd /tmp/cipi-gui-build && composer require cipi/gui:@dev --no-interaction)
    else
        (cd /tmp/cipi-gui-build && composer require cipi/gui --no-interaction)
    fi

    [[ -f "${backup_dir}/.env" ]] && cp "${backup_dir}/.env" /tmp/cipi-gui-build/.env
    [[ -f "${backup_dir}/database.sqlite" ]] && cp "${backup_dir}/database.sqlite" /tmp/cipi-gui-build/database/database.sqlite

    _gui_clear_host_routes /tmp/cipi-gui-build
    (cd /tmp/cipi-gui-build && php artisan vendor:publish --tag=cipi-gui-config --force)
    (cd /tmp/cipi-gui-build && php artisan migrate --force)

    rm -rf "${CIPI_GUI_ROOT}.old" 2>/dev/null
    mv "${CIPI_GUI_ROOT}" "${CIPI_GUI_ROOT}.old" 2>/dev/null || true
    mv /tmp/cipi-gui-build "${CIPI_GUI_ROOT}"
    chown -R www-data:www-data "${CIPI_GUI_ROOT}"
    ensure_cipi_gui_permissions
    reload_php_fpm "8.5"
    success "GUI upgraded (old: ${CIPI_GUI_ROOT}.old)"
}

gui_status() {
    [[ ! -f "${CIPI_GUI_CONFIG}" ]] && { error "GUI not configured."; exit 1; }
    local domain
    domain=$(vault_read gui.json | jq -r '.domain')
    echo ""
    echo -e "${BOLD}Cipi GUI Status${NC}"
    echo -e "  Domain:  ${CYAN}https://${domain}${NC}"
    echo -e "  Root:    ${CIPI_GUI_ROOT}"
    [[ -f "${CIPI_GUI_ROOT}/artisan" ]] \
        && echo -e "  Laravel: $(cd "${CIPI_GUI_ROOT}" && sudo -u www-data php artisan --version 2>/dev/null)" \
        || echo -e "  Laravel: ${RED}not installed${NC}"
    [[ -f "${CIPI_GUI_ROOT}/artisan" ]] \
        && echo -e "  Package: $(cd "${CIPI_GUI_ROOT}" && composer show cipi/gui 2>/dev/null | sed -n 's/^[[:space:]]*versions[[:space:]]*:[[:space:]]*//p' | head -1)"
    echo ""
}

gui_fix_permissions() {
    ensure_cipi_gui_permissions
    success "GUI permissions fixed"
}

gui_reset_user() {
    [[ ! -f "${CIPI_GUI_ROOT}/artisan" ]] && {
        error "Laravel GUI app not found. Run: cipi gui <domain>"
        exit 1
    }

    unset ARG_email ARG_password ARG_name
    parse_args "$@"

    local email="${ARG_email:-}" password="" err
    if [[ -n "$email" ]] && ! _gui_validate_admin_email "$email"; then
        error "Invalid email address"
        exit 1
    fi
    _gui_resolve_admin_password password "${ARG_password:-}" || exit 1

    local cmd=(sudo -u www-data php artisan cipi:seed-gui-user --reset)
    [[ -n "$email" ]] && cmd+=(--email="${email}")
    cmd+=(--password="${password}")
    [[ -n "${ARG_name:-}" ]] && cmd+=(--name="${ARG_name}")

    step "Resetting GUI admin user..."
    ensure_cipi_gui_permissions
    if ! (cd "${CIPI_GUI_ROOT}" && "${cmd[@]}"); then
        error "Failed to reset GUI admin user"
        exit 1
    fi

    log_action "GUI ADMIN USER RESET"
    success "GUI admin user reset"
    unset password
}

gui_command() {
    local sub="${1:-}"
    shift || true

    case "$sub" in
        "")
            error "Usage: cipi gui <domain>"
            echo "       cipi gui ssl | update | upgrade | status | fix-permissions"
            echo "       cipi gui reset-user [--email=] [--password=] [--name=]"
            exit 1
            ;;
        ssl) gui_ssl ;;
        update) gui_update ;;
        upgrade) gui_upgrade ;;
        status) gui_status ;;
        fix-permissions) gui_fix_permissions ;;
        reset-user|reset-password) gui_reset_user "$@" ;;
        *)
            validate_domain "$sub" && gui_setup "$sub" || exit 1
            ;;
    esac
}
