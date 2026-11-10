# ansible - the deploy server, configured from a pipeline

Configuration management for the single Rocky Linux 10 server that all the example projects deploy to.
Every playbook runs in this project's GitLab pipeline; the variables (keys, passwords) are set with `glab`.

| Playbook | What it does |
|----------|--------------|
| `playbooks/maintenance.yml` | Repository pinning, common packages (`ca-certificates`, `htop`, `chrony` ...), SELinux enforcing, and with `-e update_all=true` all updates **including the kernel**, with a reboot when needed |
| `playbooks/runtimes.yml` | Docker, Podman, Java (`java_version`), .NET (`dotnet_versions`), PHP and Apache (`php_version`) in the versions set in `inventory/group_vars/all.yml` |
| `playbooks/users.yml` | The accounts the applications run as (`svc-java`, `svc-php`, `svc-dotnet`), directories, and the `deploy` user's narrow sudo rule |
| `playbooks/postgresql.yml` | PostgreSQL 16 (packaged), one role and database per application and environment |
| `playbooks/caddy.yml` | Caddy with automatic HTTPS (Let's Encrypt) for every application and environment, and the static maintenance page |
| `playbooks/apps.yml` | systemd units, configuration files with the database passwords, one Apache instance per environment for PHP |
| `playbooks/site.yml` | All of the above, in order |

## Naming

Every application exists twice on the server, `<app>-staging` and `<app>-production`. The same name is used for the
systemd unit, the database and role (`_` instead of `-`), `/srv/<app>/<env>/`, `/etc/examples/<app>-<env>.env`
and the host name `<app>-<env>.examples.maresdemo.com`. Backends listen on `127.0.0.1` only.

| Application | Kind | Staging / production port |
|-------------|------|---------------------------|
| `dotnet-api` | systemd unit running `docker run` | 5101 / 5102 |
| `dotnet-vendor` | rootless Podman Quadlet (owned by `svc-dotnet`) | 5111 / 5112 |
| `java-systemd` | Spring Boot JAR as a systemd unit | 5121 / 5122 |
| `java-container` | systemd unit running `docker run` | 5131 / 5132 |
| `php-apache` | Apache (mod_php) instance per environment | 5141 / 5142 |

## Pipeline

`syntax` (every pipeline) → `dry-run:staging` (`--check --diff`) → `deploy:staging` → `deploy:production` (manual,
protected environment). `maintenance:updates` applies all updates and reboots when needed; run it by hand or from a
schedule with the variable `UPDATE_ALL=true`.

Staging and production are the same machine here, so `--limit staging` / `--limit production` select which
environment's resources (databases, units, directories) are configured. The platform tasks are identical and idempotent.

## Variables

```bash
export ANSIBLE_SSH_KEY_FILE=...   DEPLOY_PUBLIC_KEY_FILE=...   SECRETS_FILE=...
scripts/set-ci-variables.sh
```

`ANSIBLE_SSH_PRIVATE_KEY` is a protected *File* variable; the `DB_PASSWORD_<APP>` variables exist once per environment
scope, so a job in the environment `staging` gets the staging password. `DEPLOY_HOST`, `DEPLOY_SSH_PORT` and `SSH_KNOWN_HOSTS`
come from the instance.

## Run it from a laptop

```bash
ansible-galaxy collection install -r requirements.yml -p .collections
export DEPLOY_HOST=... DEPLOY_SSH_PORT=6022 ANSIBLE_PRIVATE_KEY_FILE=... DEPLOY_PUBLIC_KEY="ssh-ed25519 ..."
export DB_PASSWORD_DOTNET_API=... DB_PASSWORD_JAVA_SYSTEMD=... DB_PASSWORD_JAVA_CONTAINER=...
ansible-playbook playbooks/runtimes.yml --limit staging -e java_version=25 --tags java
```

## Good to know

- `deploy` is in the `docker` group, which is equivalent to root on this host. That is the trade-off of "the pipeline
  runs `docker run`"; a Quadlet (rootless Podman) deployment avoids it.
- PostgreSQL listens on all addresses but only the Docker bridge range and loopback are allowed in `pg_hba.conf`, and the
  cloud firewall does not open 5432.
- SELinux stays **enforcing**: Apache's ports and the PHP release directories are labelled by the playbooks.
