#!/bin/bash
set -euo pipefail

echo "[INFO] Starting WireGuard container..."

IFACE="${IFACE:-wg0}"
CONFIG="/etc/wireguard/${IFACE}.conf"

mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

require_env() {
    local name="$1"

    if [[ -z "${!name:-}" ]]; then
        echo "[ERROR] Environment variable '$name' is required." >&2
        sleep infinity &
        wait $!
    fi
}

########################################
# Key generation
########################################

if [[ "${GENKEYS:-}" == "true" ]]; then
    echo "[INFO] Key generation mode enabled."

    if [[ -n "${GENKEYS_PRIVATE_KEY:-}" ]]; then
        echo "[INFO] Deriving public key from the provided private key..."
        PRIVATE_KEY="$GENKEYS_PRIVATE_KEY"
    else
        echo "[INFO] Generating a new private key..."
        PRIVATE_KEY="$(wg genkey)"
    fi

    echo "[INFO] Generating public and preshared keys..."

    PUBLIC_KEY="$(printf '%s' "$PRIVATE_KEY" | wg pubkey)"
    PRESHARED_KEY="$(wg genpsk)"

    echo "[INFO] Key generation completed."

    cat <<EOF
PRIVATE_KEY=$PRIVATE_KEY
PUBLIC_KEY=$PUBLIC_KEY
PRESHARED_KEY=$PRESHARED_KEY
EOF

    sleep infinity &
    wait $!
fi

########################################
# Interface
########################################

echo "[INFO] Generating interface configuration for interface '$IFACE'..."

require_env PRIVATE_KEY
require_env ADDRESS

cat > "$CONFIG" <<EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = $ADDRESS
EOF

if [[ -n "${LISTEN_PORT:-}" ]]; then
    echo "ListenPort = $LISTEN_PORT" >> "$CONFIG"
fi

if [[ -n "${DNS:-}" ]]; then
    echo "DNS = $DNS" >> "$CONFIG"
fi

if [[ -n "${MTU:-}" ]]; then
    echo "MTU = $MTU" >> "$CONFIG"
fi

if [[ -n "${TABLE:-}" ]]; then
    echo "Table = $TABLE" >> "$CONFIG"
fi

if [[ -n "${PRE_UP:-}" ]]; then
    echo "PreUp = $PRE_UP" >> "$CONFIG"
fi

if [[ -n "${POST_UP:-}" ]]; then
    echo "PostUp = $POST_UP" >> "$CONFIG"
fi

if [[ -n "${PRE_DOWN:-}" ]]; then
    echo "PreDown = $PRE_DOWN" >> "$CONFIG"
fi

if [[ -n "${POST_DOWN:-}" ]]; then
    echo "PostDown = $POST_DOWN" >> "$CONFIG"
fi

########################################
# Peers
########################################

echo "[INFO] Generating peer configuration(s)..."

require_env PEERS

PEERS="${PEERS// /}"
IFS=',' read -ra peer_names <<< "$PEERS"

echo "[INFO] Processing ${#peer_names[@]} peer(s)..."

for peer_name in "${peer_names[@]}"; do
    if [[ -z "$peer_name" ]]; then
        continue
    fi

    echo "[INFO] Adding peer '$peer_name'..."

    if [[ ! "$peer_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        echo "[ERROR] Invalid peer name '$peer_name'." >&2
        echo "[ERROR] Peer names may only contain letters, numbers, and underscores and must not start with a number." >&2
        sleep infinity &
        wait $!
    fi

    public_var="PEER_${peer_name}_PUBLIC_KEY"
    psk_var="PEER_${peer_name}_PRESHARED_KEY"
    allowed_var="PEER_${peer_name}_ALLOWED_IPS"
    endpoint_var="PEER_${peer_name}_ENDPOINT"
    keepalive_var="PEER_${peer_name}_PERSISTENT_KEEPALIVE"

    require_env "$public_var"
    require_env "$allowed_var"

    {
        echo
        echo "[Peer]"
        echo "# $peer_name"
        echo "PublicKey = ${!public_var}"

        if [[ -n "${!psk_var:-}" ]]; then
            echo "PresharedKey = ${!psk_var}"
        fi

        echo "AllowedIPs = ${!allowed_var}"

        if [[ -n "${!endpoint_var:-}" ]]; then
            echo "Endpoint = ${!endpoint_var}"
        fi

        if [[ -n "${!keepalive_var:-}" ]]; then
            echo "PersistentKeepalive = ${!keepalive_var}"
        fi
    } >> "$CONFIG"
done

echo "[INFO] WireGuard configuration written to '$CONFIG'."

########################################
# Start WireGuard
########################################

chmod 600 "$CONFIG"

cleanup() {
    local exit_code=$?

    trap - EXIT SIGINT SIGTERM

    if ip link show "$IFACE" >/dev/null 2>&1; then
        echo "[INFO] Stopping WireGuard interface '$IFACE'..."

        if wg-quick down "$IFACE"; then
            echo "[INFO] WireGuard interface '$IFACE' stopped."
        else
            echo "[WARN] wg-quick could not remove '$IFACE'; removing it directly." >&2
            ip link delete dev "$IFACE" || true
        fi
    else
        echo "[INFO] WireGuard interface '$IFACE' is not active."
    fi

    exit "$exit_code"
}

trap cleanup EXIT SIGINT SIGTERM

if ip link show "$IFACE" >/dev/null 2>&1; then
    echo "[WARN] Removing stale interface '$IFACE'..."

    if ! wg-quick down "$IFACE"; then
        echo "[WARN] wg-quick could not remove '$IFACE'; removing it directly." >&2
        ip link delete dev "$IFACE" || true
    fi
fi

echo "[INFO] Starting WireGuard interface '$IFACE'..."
wg-quick up "$IFACE"

echo "[INFO] WireGuard interface '$IFACE' started successfully."
echo "[INFO] Waiting for shutdown signal..."

sleep infinity &
wait $!