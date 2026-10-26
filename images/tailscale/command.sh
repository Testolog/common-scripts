tailscale() {
    local COMPOSE_DIR="$HOME/common-scripts/images/tailscale"
    local CONTAINER_NAME="tailscale_proxy"

    # 1. Handle "down" - brings down the whole Docker Compose stack
    if [ "$1" = "down" ]; then
        echo "Bringing down Tailscale Docker Compose stack..."
        docker compose -f "$COMPOSE_DIR/docker-compose.yml" down
        return $?
    fi

    # 2. Check if the container is running; if not, spin it up using Docker Compose
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Tailscale container is not running. Starting Docker Compose..."
        docker compose -f "$COMPOSE_DIR/docker-compose.yml" up -d
        
        if [ $? -ne 0 ]; then
            echo "Error: Failed to start Docker Compose stack."
            return 1
        fi
        sleep 1
    fi

    # 3. If no extra arguments provided, default to showing status
    if [ $# -eq 0 ]; then
        docker exec -it "$CONTAINER_NAME" tailscale status
    else
        # Pass all arguments directly to the tailscale CLI inside the container
        docker exec -it "$CONTAINER_NAME" tailscale "$@" -d
    fi
}

# Optional: Shortcut alias if you prefer typing 'ts' instead of 'tailscale'
alias ts="tailscale"
