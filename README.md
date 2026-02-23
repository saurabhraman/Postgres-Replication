# Postgres Database Replication (Hot/Hot)

PostgreSQL 17 database with streaming replication and automated nightly backups.

## Architecture

```
┌─────────────────┐       ┌─────────────────┐
│   db-primary    │──WAL──│   db-replica     │
│  (read/write)   │ stream│  (read-only)     │
│    0.0.0.0:8008  │       │    0.0.0.0:8009   │
└────────┬────────┘       └──────────────────┘
         │
    ┌────┴────┐
    │db-backup│  Nightly at 2 AM
    │ pg_dump │──► ./backups/ (host)
    └─────────┘
```

All database ports are bound to `0.0.0.0` so they are accessible from external hosts.

| Service | Port | Purpose |
|---------|------|---------|
| `db-primary` | 8008 | Primary read/write database |
| `db-replica` | 8009 | Read-only streaming replica |
| `db-backup` | -- | Nightly backup to host filesystem (no exposed port) |

## Prerequisites

- Docker & Docker Compose

## CI/CD Pipeline

The project uses GitLab CI/CD to build, push, and deploy Docker images automatically.

### Pipeline Stages

```
push/merge to main
       │
       ▼
┌──────────────┐     ┌──────────────┐
│ build-primary│     │ build-replica │   (parallel, Docker-in-Docker)
└──────┬───────┘     └──────┬───────┘
       │                    │
       └────────┬───────────┘
                ▼
        ┌──────────────┐
        │    deploy     │   (ec2-dev-deploy runner on server)
        └──────────────┘
```

| Stage | Job | Description |
|-------|-----|-------------|
| `build` | `build-primary` | Builds `Dockerfile` and pushes to GitLab Container Registry |
| `build` | `build-replica` | Builds `Dockerfile.replica` and pushes to GitLab Container Registry |
| `deploy` | `deploy` | Pulls latest images and runs `docker compose up -d` on the server |

The pipeline **only runs on pushes/merges to the `main` branch**.

### GitLab CI/CD Variables

Set these under **Settings > CI/CD > Variables** in your GitLab project:

| Variable | Description | Masked | Protected |
|----------|-------------|--------|-----------|
| `DB_PASSWORD` | PostgreSQL password | Yes | Yes |

The following variables are provided automatically by GitLab — no setup needed:

- `CI_REGISTRY`, `CI_REGISTRY_USER`, `CI_REGISTRY_PASSWORD` — registry authentication
- `CI_REGISTRY_IMAGE` — registry image path (used as `REGISTRY_URL` during deploy)

### GitLab Runner Requirements

The deploy job requires a **shell executor** runner on the target server with:

- **Tag:** `ec2-dev-deploy`
- **Protected:** Enabled (since `main` is a protected branch)
- **Docker & Docker Compose** installed on the server

### Container Registry Images

After a successful build, images are available at:

```
<registry>/primary:latest
<registry>/primary:<commit-sha>
<registry>/replica:latest
<registry>/replica:<commit-sha>
```

## Quick Start

### Local Development (using docker-compose.yml)

1. **Configure environment**
   ```bash
   cp .env.example .env
   # Edit .env and set a strong DB_PASSWORD
   ```

2. **Start all services**
   ```bash
   docker compose up -d
   ```

3. **Verify everything is running**
   ```bash
   docker compose ps
   ```

### Production Deployment (via CI/CD)

Deployment is automated. On every push/merge to `main`:

1. GitLab CI builds and pushes images to the Container Registry
2. The deploy job pulls images and runs services on the server at `/opt/mfi-hub/`

To manually deploy or restart on the server:

```bash
cd /opt/mfi-hub
export REGISTRY_URL=registry.gitlab.com/<group>/<project>
export DB_PASSWORD=<password>
docker login registry.gitlab.com
docker compose pull
docker compose up -d
```

## Connecting to the Database

```bash
# Connect to the primary
psql -h localhost -p 8008 -U postgres -d mfi_banking

# Connect to the replica (read-only)
psql -h localhost -p 8009 -U postgres -d mfi_banking

# Connect from a remote host
psql -h <server-ip> -p 8008 -U postgres -d mfi_banking
```

## Project Structure

```
mfi-database/
├── .gitlab-ci.yml              # CI/CD pipeline (build, push, deploy)
├── config/
│   ├── postgresql.conf          # PostgreSQL configuration (WAL, replication)
│   └── pg_hba.conf              # Client authentication rules
├── init-scripts/
│   ├── 00-init-replication.sh   # Creates replicator role on primary
│   └── mfi_schema.sql           # Full schema, indexes, triggers, seed data
├── scripts/
│   ├── replica-entrypoint.sh    # Replica init via pg_basebackup
│   └── backup.sh                # pg_dump backup with retention cleanup
├── backups/                     # Backup files (mounted from host)
├── Dockerfile                   # Primary database image
├── Dockerfile.replica           # Replica database image
├── docker-compose.yml           # Local development orchestration (builds from source)
├── compose.yaml                 # Production orchestration (pulls from registry)
├── .env.example                 # Template for environment variables
└── .gitignore                   # Excludes .env and backups/
```

## Database Schema

The schema is initialized automatically on first run via `init-scripts/mfi_schema.sql`.

### Modules

| Module | Tables |
|--------|--------|
| **Reference** | `activity_type`, `mfi_country`, `mfi_type`, `platform_type` |
| **Portals** | `portals`, `portal_groups`, `portal_users`, `user_groups` |
| **MFIs** | `mfi_clients`, `mfi_groups`, `mfi_users`, `mfi_platforms` |
| **Platforms** | `digital_platforms` |
| **Audit** | `user_auth_logs`, `admin_event_logs`, `user_activity_logs`, `mfi_user_activity_logs` |

### Views

| View | Description |
|------|-------------|
| `v_active_portals` | Active portals with user counts |
| `v_mfi_platforms_summary` | MFI clients with assigned platforms |
| `v_user_group_assignments` | Users with their group memberships |

### Verify Schema

```sql
-- List all tables
\dt

-- Check seed data
SELECT * FROM activity_type;
SELECT * FROM mfi_country;
SELECT * FROM mfi_type;
SELECT * FROM platform_type;
```

## Replication

The replica uses PostgreSQL streaming replication:

- On first start, `replica-entrypoint.sh` clones the primary via `pg_basebackup`
- Ongoing changes are streamed via WAL (Write-Ahead Log)
- The replica is read-only (`hot_standby = on`)

**Verify replication is working:**
```sql
-- On the primary
SELECT * FROM pg_stat_replication;

-- On the replica
SELECT pg_is_in_recovery();  -- Should return true
```

## Backups

- **Schedule:** Nightly at 2:00 AM (+ one backup on container start)
- **Format:** `pg_dump --format=custom` (compressed)
- **Location:** `./backups/` on the host machine
- **Retention:** 7 days (configurable via `BACKUP_RETAIN_DAYS`)

**Run a manual backup:**
```bash
docker compose exec db-backup /backup.sh
```

**Restore from a backup:**
```bash
pg_restore -h localhost -p 8008 -U postgres -d mfi_banking --clean ./backups/<backup_file>.sql.gz
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DB_PASSWORD` | PostgreSQL & replicator password | **(required)** |
| `REGISTRY_URL` | GitLab Container Registry path (production only) | set via CI/CD |
| `BACKUP_RETAIN_DAYS` | Days to keep backup files | `7` |

## Important Notes

| Item | Description |
|------|-------------|
| **Keycloak Groups** | Must be created in Keycloak first, then synced to `portal_groups` / `mfi_groups` |
| **UUID Generation** | Uses `uuid-ossp` and `pgcrypto` extensions |
| **JSONB Fields** | Used for flexible metadata storage (logs, event details) |
| **Triggers** | Auto-update `updated_at` timestamps on record changes |
| **Foreign Keys** | Enforce referential integrity with CASCADE/RESTRICT rules |

## Common Commands

```bash
# Start services (local)
docker compose up -d

# Start services (production)
docker compose -f compose.yaml up -d

# Stop services
docker compose down

# View logs
docker compose logs -f db-primary
docker compose logs -f db-replica
docker compose logs -f db-backup

# Reset everything (destroys all data)
docker compose down -v
```
