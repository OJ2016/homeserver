# Home Server

Dockerized home server running three isolated services on Ubuntu.

## Services

| Service   | Image                          | Port(s)         | Network        | External Access |
|-----------|--------------------------------|-----------------|----------------|-----------------|
| Minecraft | itzg/minecraft-server:latest   | 25565           | minecraft_net  | Yes (public)    |
| Jenkins   | jenkins/jenkins:lts            | 8080, 50000     | jenkins_net    | No (LAN only)   |
| Samba     | dperson/samba:latest           | 445             | samba_net      | No (LAN only)   |

Each service runs on its own bridge network with separate data directories and no shared volumes.

## Quick Start

1. **Clone the repo** and copy environment files:

    ```bash
    cp minecraft/.env.example minecraft/.env
    cp jenkins/.env.example jenkins/.env
    cp samba/.env.example samba/.env
    cp .env.example .env    # global config (LAN_SUBNET)
    ```

2. **Edit `.env` files** — see [Environment Files](#environment-files) below.

3. **Create the Samba user** (see [Fileshare User](#fileshare-user)).

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
| `samba/.env` | Samba user credentials, UID/GID |

For Samba, replace `<fileshare_UID>` and `<sambashare_GID>` in `samba/.env`
with the actual UID/GID after creating the fileshare user:

```bash
id -u fileshare   # USERID
getent group sambashare | cut -d: -f3   # GROUPID
```

## Fileshare User

A restricted system user `fileshare` (nologin shell) is used exclusively for
Samba authentication. Create it and set its Samba password:

```bash
sudo useradd -r -s /usr/sbin/nologin -G sambashare fileshare
sudo smbpasswd -a fileshare
```

## Firewall

Firewall rules are managed by `firewall.sh`, which configures iptables to:

- **INPUT chain** — default policy DROP; allows only SSH (port 22) and established connections
- **DOCKER-USER chain** — restricts Docker-published ports (Jenkins, Samba) to the LAN subnet

> **Note:** ufw is not used. It conflicts with Docker's iptables rules and has been
> replaced by direct iptables management via `firewall.sh` + `iptables-persistent`.

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

## Security

- Each service runs on an **isolated Docker bridge network** — no inter-container communication
- No shared volumes between services
- `cap_drop: ALL` on every container
- `no-new-privileges: true` on Jenkins and Minecraft
- Samba adds only required capabilities (`NET_BIND_SERVICE`, `SETUID`, `SETGID`, `SYS_CHROOT`, `DAC_OVERRIDE`, `CHOWN`, `FOWNER`)
- Secrets (`.env` files) are git-ignored
- Jenkins data directory must be owned by UID 1000: `sudo chown -R 1000:1000 jenkins/data`
