# Home Server

Dockerized home server running three isolated services on Ubuntu.

## Services

| Service   | Image                          | Port(s)         | Network        | External Access |
|-----------|--------------------------------|-----------------|----------------|-----------------|
| Minecraft | itzg/minecraft-server:latest   | 25565           | minecraft_net  | Yes (public)    |
| Jenkins   | Custom (jenkins/jenkins:lts + Docker CLI) | 8080, 50000     | jenkins_net    | No (LAN only)   |
| Samba     | dockurr/samba:4.23             | 445             | samba_net      | No (LAN only)   |

Each service runs on its own bridge network with separate data directories and no shared volumes.

## Quick Start

1. **Clone the repo** and copy environment files:

    ```bash
    cp minecraft/.env.example minecraft/.env
    cp jenkins/.env.example jenkins/.env
    cp .env.example .env    # global config (LAN_SUBNET)
    ```

2. **Edit `.env` files** — see [Environment Files](#environment-files) below.

3. **Create the Samba user and its password file** (see [Fileshare User](#fileshare-user)).

4. **Start all services:**

    ```bash
    ./manage.sh up
    ```

5. **Apply firewall rules:**

    ```bash
    sudo apt install -y iptables-persistent
    sudo ./firewall.sh apply
    ```

## Usage

```bash
./manage.sh          # bring all services up (default)
./manage.sh up       # same as above
./manage.sh down     # bring all services down
./manage.sh pull     # pull latest images
./manage.sh logs     # view logs
```

Services have `restart: unless-stopped`, so they start automatically on boot.
You only need `manage.sh` for the initial setup or manual control.

## Environment Files

All `.env` files are git-ignored. Each service has a `.env.example` template.

| File | Purpose |
|------|---------|
| `.env` | Global config — `LAN_SUBNET` for firewall rules |
| `minecraft/.env` | Server settings (EULA, memory, version) |
| `jenkins/.env` | Jenkins environment variables |
| `samba/secrets/samba_pass` | Samba password of the `fileshare` user (one line, mode 600) |

For Samba, the login user and the UID/GID that files are created with are set
in `samba/docker-compose.yml` (`USER`, `UID`, `GID`). They must match the host
`fileshare` user and `sambashare` group:

```bash
id -u fileshare   # USERID
getent group sambashare | cut -d: -f3   # GROUPID
```

## Fileshare User

A restricted system user `fileshare` (nologin shell) is used exclusively for
Samba authentication. Create it and set its Samba password:

```bash
sudo useradd -r -s /usr/sbin/nologin -G sambashare fileshare
mkdir -p samba/secrets && chmod 700 samba/secrets
(umask 077; printf '%s' 'THE-PASSWORD' > samba/secrets/samba_pass)
```

The container reads the password from this file at startup (mounted as
`/run/secrets/pass`), so it never appears on a command line, in `ps`, or in
the container environment. Samba's own password database lives inside the
container and is rebuilt from the file on every start.

## Firewall

Firewall rules are managed by `firewall.sh`, which configures iptables to:

- **INPUT chain** — default policy DROP; allows only SSH (port 22) and established connections
- **DOCKER-USER chain** — restricts Docker-published ports (Jenkins, Samba) to the LAN subnet

> **Note:** ufw is not used. It conflicts with Docker's iptables rules and has been
> replaced by direct iptables management via `firewall.sh` + `iptables-persistent`.

### Why not ufw?

Docker bypasses ufw entirely. When Docker publishes a port (e.g. `-p 8080:8080`),
it creates rules in the **FORWARD** chain and its own **DOCKER** chain, routing
traffic directly to the container. ufw only manages the **INPUT** chain, which
handles traffic for host-level processes:

```
Packet → FORWARD chain → DOCKER chain → Container
               ↑
         ufw never sees this traffic
```

Even `sudo ufw deny 8080` has no effect — the packet never reaches INPUT because
Docker's FORWARD rules grab it first. The `DOCKER-USER` chain is the only chain
in the FORWARD path that Docker guarantees it won't overwrite, making it the
correct place to filter traffic to containers.

### Setup (one-time on a fresh machine)

```bash
# Install iptables-persistent for boot persistence
sudo apt install -y iptables-persistent

# Apply all firewall rules
sudo ./firewall.sh apply
```

### Commands

```bash
sudo ./firewall.sh apply    # apply all rules and persist
sudo ./firewall.sh status   # show current INPUT and DOCKER-USER chains
sudo ./firewall.sh reset    # remove all managed rules (opens everything)
```

### How it works

The script reads `LAN_SUBNET` from the root `.env` file and configures two iptables chains:

**INPUT chain** (host-level traffic):
- ACCEPT established/related connections
- ACCEPT loopback
- ACCEPT SSH (port 22) from anywhere
- DROP everything else

**DOCKER-USER chain** (Docker container traffic):
- ACCEPT from `LAN_SUBNET` on ports 8080, 50000, 445
- DROP from everywhere else on those ports
- Minecraft (25565) is left unrestricted for external access

Rules are tagged with `homeserver-managed` comments so the script can
flush and reapply them cleanly. Rules survive reboots via `iptables-persistent`.

### Customization

Edit the port arrays at the top of `firewall.sh`:

| Array | Purpose |
|-------|---------|
| `INPUT_OPEN_PORTS` | Host ports open to everyone (SSH) |
| `INPUT_LAN_PORTS_TCP` | Host ports open to LAN only |
| `DOCKER_LAN_PORTS` | Docker container ports restricted to LAN |

## Jenkins Docker Support

Jenkins uses a custom image (`jenkins/Dockerfile`) that includes the Docker CLI.
The host's Docker socket is mounted into the container, allowing Jenkins pipelines
to build images and run containers.

The `DOCKER_GID` variable in `jenkins/.env` must match the host's docker group ID:

```bash
stat -c '%g' /var/run/docker.sock   # find the GID
```

> **Security note:** Docker socket access gives Jenkins effective root access to the
> host. This is acceptable for a single-user home server but should not be used in
> multi-user or untrusted environments.

## Security

- Each service runs on an **isolated Docker bridge network** — no inter-container communication
- No shared volumes between services (except Jenkins → Docker socket)
- `no-new-privileges: true` on all containers
- `cap_drop: ALL` on Minecraft; Samba adds only required capabilities
- Jenkins has Docker socket access for pipeline builds (see above)
- Secrets (`.env` files, `samba/secrets/`) are git-ignored
- Jenkins data directory must be owned by UID 1000: `sudo chown -R 1000:1000 jenkins/data`
