#!/bin/sh
set -eu

STEAMCMD_DIR="/steamapps"
APP_DIR="/app"
APP_ID="1169370"
RUN_USER="${CONTAINER_USER:-necesse}"
RUN_GROUP="${CONTAINER_GROUP:-necesse}"
AUTO_UPDATE_FLAG_FILE="/tmp/necesse-auto-update"

SERVER_PID=""
AUTO_UPDATE_MONITOR_PID=""
SERVER_EXIT_CODE=0
AUTO_UPDATE_INTERVAL_MINUTES_NORMALIZED=0
AUTO_UPDATE_INTERVAL_SECONDS=0

lowercase() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_root() {
    [ "$(id -u)" -eq 0 ]
}

run_as_user() {
    if is_root; then
        gosu "${RUN_USER}:${RUN_GROUP}" "$@"
    else
        "$@"
    fi
}

adjust_permissions() {
    if ! is_root; then
        return
    fi

    target_gid="${PGID:-$CONTAINER_GID}"
    target_uid="${PUID:-$CONTAINER_UID}"

    current_gid="$(getent group "${RUN_GROUP}" | awk -F: '{print $3}')"
    if [ -n "${target_gid}" ] && [ "${target_gid}" != "${current_gid}" ]; then
        groupmod -o -g "${target_gid}" "${RUN_GROUP}"
    fi

    current_uid="$(id -u "${RUN_USER}")"
    if [ -n "${target_uid}" ] && [ "${target_uid}" != "${current_uid}" ]; then
        usermod -o -u "${target_uid}" -g "${RUN_GROUP}" "${RUN_USER}"
    fi

    chown -R "${RUN_USER}:${RUN_GROUP}" \
        "${APP_DIR}" \
        "/home/${RUN_USER}" \
        "${STEAMCMD_DIR}"
}

get_manifest_buildid() {
    # SteamCMD writes manifests into the install dir's steamapps folder when force_install_dir is used.
    # Fall back to the SteamCMD root for older layouts or if users override directories.
    for manifest_path in \
        "${APP_DIR}/steamapps/appmanifest_${APP_ID}.acf" \
        "${STEAMCMD_DIR}/steamapps/appmanifest_${APP_ID}.acf"
    do
        if [ -f "${manifest_path}" ]; then
            awk -F'"' '/"buildid"/ {print $4; exit}' "${manifest_path}"
            return
        fi
    done
}

fetch_remote_buildid() {
    run_as_user "$STEAMCMD_DIR/steamcmd.sh" \
        +login anonymous \
        +app_info_update 1 \
        +app_info_print "${APP_ID}" \
        +quit \
        | awk -F'"' '/"buildid"/ {print $4; exit}'
}

calculate_auto_update_interval() {
    interval="${AUTO_UPDATE_INTERVAL_MINUTES:-0}"
    if [ -z "${interval}" ]; then
        interval=0
    fi

    if printf '%s' "${interval}" | grep -Eq '^[0-9]+$'; then
        AUTO_UPDATE_INTERVAL_MINUTES_NORMALIZED="${interval}"
        AUTO_UPDATE_INTERVAL_SECONDS=$((interval * 60))
    else
        echo "AUTO_UPDATE_INTERVAL_MINUTES must be numeric; disabling auto update." >&2
        AUTO_UPDATE_INTERVAL_MINUTES_NORMALIZED=0
        AUTO_UPDATE_INTERVAL_SECONDS=0
    fi
}

check_for_remote_update() {
    current="$(get_manifest_buildid || true)"
    remote="$(fetch_remote_buildid || true)"

    if [ -z "${remote}" ]; then
        echo "Auto-update: unable to determine remote build ID." >&2
        return 1
    fi

    if [ -z "${current}" ]; then
        echo "Auto-update: no local build found; treating as update required."
        return 0
    fi

    if [ "${remote}" != "${current}" ]; then
        echo "Auto-update: new build detected (local ${current}, remote ${remote})."
        return 0
    fi

    return 1
}

stop_auto_update_monitor() {
    if [ -n "${AUTO_UPDATE_MONITOR_PID}" ]; then
        if kill -0 "${AUTO_UPDATE_MONITOR_PID}" 2>/dev/null; then
            kill "${AUTO_UPDATE_MONITOR_PID}" 2>/dev/null || true
        fi
        wait "${AUTO_UPDATE_MONITOR_PID}" 2>/dev/null || true
        AUTO_UPDATE_MONITOR_PID=""
    fi
}

start_auto_update_monitor() {
    calculate_auto_update_interval
    seconds="${AUTO_UPDATE_INTERVAL_SECONDS}"
    if [ "${seconds}" -le 0 ]; then
        return
    fi

    echo "Auto-update: enabled; checking for new builds every ${AUTO_UPDATE_INTERVAL_MINUTES_NORMALIZED} minute(s)."

    (
        while true; do
            sleep "${seconds}"
            if check_for_remote_update; then
                touch "${AUTO_UPDATE_FLAG_FILE}"
                echo "Auto-update: stopping server to apply latest build."
                pkill -f 'Server.jar' >/dev/null 2>&1 || true
                exit 0
            fi
        done
    ) &
    AUTO_UPDATE_MONITOR_PID=$!
}

stop_server() {
    if [ -n "${SERVER_PID}" ]; then
        if kill -0 "${SERVER_PID}" 2>/dev/null; then
            kill "${SERVER_PID}" 2>/dev/null || true
        fi
        wait "${SERVER_PID}" 2>/dev/null || true
        SERVER_PID=""
    fi
}

launch_server() {
    set -- java

    if [ -n "${JAVA_OPTS:-}" ]; then
        # shellcheck disable=SC2086
        for opt in ${JAVA_OPTS}; do
            set -- "$@" "$opt"
        done
    fi

    set -- "$@" -jar Server.jar -nogui

    local_dir_flag="$(lowercase "${LOCAL_DIR:-0}")"
    if [ "$local_dir_flag" = "1" ] || [ "$local_dir_flag" = "true" ]; then
        set -- "$@" -localdir
    fi

    if [ -n "${DATA_DIR:-}" ]; then
        mkdir -p "${DATA_DIR}"
        set -- "$@" -datadir "${DATA_DIR}"
    fi

    if [ -n "${LOGS_DIR:-}" ]; then
        mkdir -p "${LOGS_DIR}"
        set -- "$@" -logs "${LOGS_DIR}"
    fi

    if [ -n "${WORLD_NAME:-}" ]; then
        set -- "$@" -world "${WORLD_NAME}"
    fi

    if [ -n "${SERVER_PORT:-}" ]; then
        set -- "$@" -port "${SERVER_PORT}"
    fi

    if [ -n "${SERVER_SLOTS:-}" ]; then
        set -- "$@" -slots "${SERVER_SLOTS}"
    fi

    if [ -n "${SERVER_OWNER:-}" ]; then
        set -- "$@" -owner "${SERVER_OWNER}"
    fi

    if [ -n "${SERVER_MOTD:-}" ]; then
        set -- "$@" -motd "${SERVER_MOTD}"
    fi

    if [ -n "${SERVER_PASSWORD:-}" ]; then
        set -- "$@" -password "${SERVER_PASSWORD}"
    fi

    if [ -n "${PAUSE_WHEN_EMPTY:-}" ]; then
        set -- "$@" -pausewhenempty "${PAUSE_WHEN_EMPTY}"
    fi

    if [ -n "${GIVE_CLIENTS_POWER:-}" ]; then
        set -- "$@" -giveclientspower "${GIVE_CLIENTS_POWER}"
    fi

    if [ -n "${ENABLE_LOGGING:-}" ]; then
        set -- "$@" -logging "${ENABLE_LOGGING}"
    fi

    if [ -n "${ZIP_SAVES:-}" ]; then
        set -- "$@" -zipsaves "${ZIP_SAVES}"
    fi

    if [ -n "${SERVER_LANGUAGE:-}" ]; then
        set -- "$@" -language "${SERVER_LANGUAGE}"
    fi

    if [ -n "${SETTINGS_FILE:-}" ]; then
        set -- "$@" -settings "${SETTINGS_FILE}"
    fi

    if [ -n "${BIND_IP:-}" ]; then
        set -- "$@" -ip "${BIND_IP}"
    fi

    if [ -n "${MAX_CLIENT_LATENCY:-}" ]; then
        set -- "$@" -maxlatency "${MAX_CLIENT_LATENCY}"
    fi

    echo "Starting Necesse server with command:"
    printf '  %s' "$@"
    printf '\n\n'

    run_as_user "$@" &
    SERVER_PID=$!
}

wait_for_server() {
    if [ -n "${SERVER_PID}" ]; then
        if wait "${SERVER_PID}"; then
            SERVER_EXIT_CODE=0
        else
            SERVER_EXIT_CODE=$?
        fi
        SERVER_PID=""
    fi
}

handle_exit() {
    trap - INT TERM
    stop_auto_update_monitor
    stop_server
    exit 0
}

maybe_update_server() {
    update_flag="$(lowercase "${UPDATE_ON_START:-false}")"

    if [ -f "${AUTO_UPDATE_FLAG_FILE}" ]; then
        update_flag="true"
    fi

    if [ ! -f "$APP_DIR/Server.jar" ] || [ "$update_flag" = "true" ]; then
        echo "Running SteamCMD to install or update Necesse..."
        if run_as_user "$STEAMCMD_DIR/steamcmd.sh" +runscript "$STEAMCMD_DIR/update_necesse.txt"; then
            echo "SteamCMD run complete."
        else
            result=$?
            echo "SteamCMD failed with exit code ${result}."
            if [ -f "$APP_DIR/Server.jar" ]; then
                echo "Keeping existing server build; new files were not applied."
                echo "Check /home/${RUN_USER}/Steam/logs/stderr.txt for SteamCMD details."
                rm -f "${AUTO_UPDATE_FLAG_FILE}"
                return
            fi

            echo "No existing server binaries found and SteamCMD failed; aborting start."
            echo "Check /home/${RUN_USER}/Steam/logs/stderr.txt for SteamCMD details."
            exit "${result}"
        fi
    fi

    rm -f "${AUTO_UPDATE_FLAG_FILE}"
}

main_loop() {
    while true; do
        SERVER_EXIT_CODE=0
        maybe_update_server
        launch_server
        start_auto_update_monitor
        wait_for_server
        stop_auto_update_monitor

        if [ -f "${AUTO_UPDATE_FLAG_FILE}" ]; then
            echo "Auto-update: restarting server with fresh binaries."
            continue
        fi

        exit "${SERVER_EXIT_CODE}"
    done
}

trap 'handle_exit' INT TERM

adjust_permissions
main_loop
