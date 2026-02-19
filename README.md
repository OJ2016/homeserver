# Home Server

Dockerized home server running three isolated services on Ubuntu 22.04.

## Services

| Service   | Image                          | Port(s)         | Network        |
|-----------|--------------------------------|-----------------|----------------|
| Minecraft | itzg/minecraft-server:latest   | 25565           | minecraft_net  |
| Jenkins   | jenkins/jenkins:lts            | 8080, 50000     | jenkins_net    |
| Samba     | dperson/samba:latest           | 139, 445        | samba_net      |

Each service runs on its own bridge network with separate data directories and no shared volumes.

## Usage

Bring all services up (default):

```bash
./manage.sh
# or explicitly
./manage.sh up
```

Bring all services down:

```bash
./manage.sh down
```

Run any other docker compose action:

```bash
./manage.sh pull    # pull latest images
./manage.sh logs    # view logs
```

## Environment Files

Each service has a `.env.example` file checked into version control.
Copy it to `.env` and edit as needed — `.env` files are git-ignored.

```bash
cp minecraft/.env.example minecraft/.env
cp jenkins/.env.example jenkins/.env
cp samba/.env.example samba/.env
```

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

## Firewall Rules

Allow access only from the local network:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 25565   # Minecraft
sudo ufw allow from 192.168.1.0/24 to any port 8080    # Jenkins
sudo ufw allow from 192.168.1.0/24 to any port 445     # Samba
```
