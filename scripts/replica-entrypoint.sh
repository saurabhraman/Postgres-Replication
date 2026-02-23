#!/bin/bash
# scripts/replica-entrypoint.sh
# Custom entrypoint for the replica container.
# If the data directory is empty, clone from primary via pg_basebackup
# instead of running initdb (which is what the default entrypoint does).

set -e

PGDATA="/var/lib/postgresql/data"

# If data directory is empty, initialize from primary
if [ -z "$(ls -A "$PGDATA" 2>/dev/null)" ]; then
    echo "=== Replica data directory is empty. Cloning from primary... ==="

    # Wait for primary to accept connections
    until pg_isready -h db-primary -U postgres -q; do
        echo "Waiting for primary to be ready..."
        sleep 2
    done

    echo "Primary is ready. Running pg_basebackup..."

    # Clone the primary (the -R flag creates standby.signal and sets primary_conninfo)
    pg_basebackup \
        -h db-primary \
        -D "$PGDATA" \
        -U replicator \
        -v -P \
        --wal-method=stream \
        -R

    # Ensure correct ownership
    chown -R postgres:postgres "$PGDATA"
    chmod 0700 "$PGDATA"

    echo "=== Replica cloned successfully. ==="
else
    echo "=== Replica data directory already populated. ==="
fi

# Start postgres as the postgres user
exec gosu postgres postgres -c config_file=/etc/postgresql/postgresql.conf -c hot_standby=on
