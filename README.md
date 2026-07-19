# wireguard-s2s-docker

A minimal Docker image for running WireGuard. Supports key generation, environment variable–based configuration and multiple peers.

No configuration files need to be mounted into the container.

## Requirements

### WireGuard kernel support

The host must have the WireGuard kernel module available and loaded. Most modern Linux kernels include WireGuard support. However, the module may not be loaded by default. Make sure WireGuard is available on the host before starting the container.

You can verify this by running:

```bash
sudo modprobe wireguard
```

### Firewall kernel modules

Some hosts do not load the required iptables kernel modules automatically. Load the required modules on the host before starting the container. Alternatively, the container can load host kernel modules itself by adding the `SYS_MODULE` capability and mounting the host's module directory:

```yaml
cap_add:
  - NET_ADMIN
  - SYS_MODULE

volumes:
  - /lib/modules:/lib/modules:ro
```

`SYS_MODULE` and the `/lib/modules` mount are optional and should only be used when the container must load kernel modules itself.

### IP routing

Because the container is used to route traffic between networks, IP forwarding must be enabled on the host.

For IPv4:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

For IPv6:

```bash
sudo sysctl -w net.ipv6.conf.all.forwarding=1
```

To make these settings persistent, add them to the host's sysctl configuration.

Furthermore, devices on each host's network must have static routes configured to direct traffic for the remote networks behind the WireGuard peers to the WireGuard host. Otherwise, clients on the local network will not be able to reach hosts behind the VPN, and return traffic will not be routed back to the originating client. The routes can be configured on individual devices or centrally on the network's gateway router.

## Usage

### Generate Keys

Generate a new private key, public key and preshared key:

```yaml
services:
  wireguard:
    image: ghcr.io/reon04/wireguard-s2s-docker:latest
    environment:
      GENKEYS: "true"
```

Generate a public key and preshared key from an existing private key:

```yaml
services:
  wireguard:
    image: ghcr.io/reon04/wireguard-s2s-docker:latest
    environment:
      GENKEYS: "true"
      GENKEYS_PRIVATE_KEY: "<private-key>" # insert key
```

### Run WireGuard

```yaml
services:
  wireguard:
    image: ghcr.io/reon04/wireguard-s2s-docker:latest
    restart: unless-stopped
    environment:
      PRIVATE_KEY: "<private-key>" # insert key
      ADDRESS: "10.0.0.1/24" # VPN internal IP of interface
      LISTEN_PORT: "51820"
      POST_UP: "iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT"
      POST_DOWN: "iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT"
      PEERS: "server"
      PEER_server_PUBLIC_KEY: "<server-public-key>" # insert key
      PEER_server_PRESHARED_KEY: "<server-preshared-key>" # insert key
      PEER_server_ALLOWED_IPS: "10.0.0.2/32,192.168.0.0/24" # VPN internal IP of remote interface and IP range of remote network
      PEER_server_ENDPOINT: "vpn.example.com:51820" # remote VPN endpoint
    network_mode: "host"
    volumes:
      - "/lib/modules:/lib/modules:ro" # optional
    cap_add:
      - NET_ADMIN
      - SYS_MODULE # optional
```

## Environment Variables

### General

| Variable | Required | Description |
|----------|:--------:|-------------|
| `IFACE` | No | WireGuard interface name (default is `wg0`). |
| `GENKEYS` | No | Generate WireGuard keys instead of starting WireGuard. |
| `GENKEYS_PRIVATE_KEY` | No | Existing private key used to derive the public key. Ignored unless `GENKEYS=true`. |

### Interface Configuration

| Variable | Required | Description |
|----------|:--------:|-------------|
| `PRIVATE_KEY` | Yes* | Private key of the interface. |
| `ADDRESS` | Yes* | Interface address in CIDR notation. |
| `LISTEN_PORT` | No | Interface listen port. |
| `DNS` | No | DNS server(s). |
| `MTU` | No | Interface MTU. |
| `TABLE` | No | Controls route table modifications. |
| `PRE_UP` | No | Command executed before bringing the interface up. |
| `POST_UP` | No | Command executed after bringing the interface up. |
| `PRE_DOWN` | No | Command executed before bringing the interface down. |
| `POST_DOWN` | No | Command executed after bringing the interface down. |

\* Required unless `GENKEYS=true`.

### Peer Configuration

Specify all peers in the `PEERS` variable as a comma-separated list.

| Variable | Required | Description |
|----------|:--------:|-------------|
| `PEERS` | Yes* | Comma-separated list of peer names (e.g. `server,office,laptop`). |

For every peer listed in `PEERS`, the following environment variables are supported:

| Variable | Required | Description |
|----------|:--------:|-------------|
| `PEER_<name>_PUBLIC_KEY` | Yes* | Public key of the peer. |
| `PEER_<name>_PRESHARED_KEY` | No | Preshared key. |
| `PEER_<name>_ALLOWED_IPS` | Yes* | Allowed IPs for the peer. |
| `PEER_<name>_ENDPOINT` | Yes* | Peer endpoint (`host:port`). |
| `PEER_<name>_PERSISTENT_KEEPALIVE` | No | Persistent keepalive interval in seconds. |

\* Required unless `GENKEYS=true`.

## License

This project is licensed under the [MIT License](LICENSE).