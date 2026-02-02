#!/bin/bash
# =============================================================================
# watchdog.sh - Server Watchdog for arcrypt-server
# =============================================================================
# Designed to run via cron every 1-5 minutes.
# - Respects SERVER_ENABLED in .env
# - Checks if process is running (PID file + process check)
# - Health check via /v1/health endpoint
# - Restarts only if necessary
# - Logs all actions
#
# Cron example (every 2 minutes):
#   */2 * * * * /home/w18416/web/arcrypt-server/server/scripts/watchdog.sh >> /home/w18416/web/arcrypt-server/server/logs/watchdog.log 2>&1
# =============================================================================

set -e

# --- Config ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SERVER_DIR/.env"
PID_FILE="$SERVER_DIR/server.pid"
LOG_DIR="$SERVER_DIR/logs"
HEALTH_URL="http://localhost"
HEALTH_TIMEOUT=5

# --- Helpers ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Load .env file and extract value
get_env_value() {
    local key="$1"
    if [[ -f "$ENV_FILE" ]]; then
        grep -E "^${key}=" "$ENV_FILE" | cut -d'=' -f2 | tr -d ' "'
    fi
}

is_process_running() {
    local pid="$1"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        return 0
    fi
    return 1
}

get_current_pid() {
    if [[ -f "$PID_FILE" ]]; then
        cat "$PID_FILE"
    fi
}

health_check() {
    local port
    port=$(get_env_value "PORT")
    port="${port:-3000}"
    
    local response
    # Note: Server only accepts POST requests
    response=$(curl -s -o /dev/null -w "%{http_code}" -X POST --max-time "$HEALTH_TIMEOUT" "${HEALTH_URL}:${port}/v1/health" 2>/dev/null || echo "000")
    
    if [[ "$response" == "200" ]]; then
        return 0
    fi
    return 1
}

stop_server() {
    local pid
    pid=$(get_current_pid)
    
    if is_process_running "$pid"; then
        log "Stopping server (PID: $pid)..."
        kill "$pid" 2>/dev/null || true
        sleep 2
        
        # Force kill if still running
        if is_process_running "$pid"; then
            log "Force killing server (PID: $pid)..."
            kill -9 "$pid" 2>/dev/null || true
        fi
    fi
    
    rm -f "$PID_FILE"
}

start_server() {
    log "Starting server..."
    
    mkdir -p "$LOG_DIR"
    cd "$SERVER_DIR"
    
    # Start in background, redirect output to log
    nohup node src/server.js >> "$LOG_DIR/server.log" 2>&1 &
    local new_pid=$!
    
    echo "$new_pid" > "$PID_FILE"
    log "Server started (PID: $new_pid)"
    
    # Wait a moment and verify
    sleep 2
    if is_process_running "$new_pid"; then
        log "Server is running"
        return 0
    else
        log "ERROR: Server failed to start"
        rm -f "$PID_FILE"
        return 1
    fi
}

# --- Main Logic ---
main() {
    log "--- Watchdog check ---"
    
    # Check if .env exists
    if [[ ! -f "$ENV_FILE" ]]; then
        log "ERROR: .env file not found at $ENV_FILE"
        exit 1
    fi
    
    # Read SERVER_ENABLED
    local enabled
    enabled=$(get_env_value "SERVER_ENABLED")
    enabled="${enabled:-false}"
    
    local pid
    pid=$(get_current_pid)
    local running=false
    
    if is_process_running "$pid"; then
        running=true
    fi
    
    # --- Decision logic ---
    
    # If disabled: stop if running
    if [[ "$enabled" != "true" ]]; then
        log "SERVER_ENABLED=$enabled (disabled)"
        if [[ "$running" == "true" ]]; then
            log "Server is running but should be disabled"
            stop_server
            log "Server stopped"
        else
            log "Server is already stopped"
        fi
        exit 0
    fi
    
    # If enabled but not running: start
    if [[ "$running" != "true" ]]; then
        log "Server is not running, starting..."
        start_server
        exit 0
    fi
    
    # If enabled and running: health check
    log "Server is running (PID: $pid), checking health..."
    
    if health_check; then
        log "Health check passed - all good"
        exit 0
    fi
    
    # Health check failed: restart
    log "Health check FAILED - restarting server..."
    stop_server
    sleep 1
    start_server
}

main "$@"
