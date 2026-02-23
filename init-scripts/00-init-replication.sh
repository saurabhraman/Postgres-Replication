#!/bin/bash
# init-scripts/00-init-replication.sh
# Creates the replicator role using the same password as POSTGRES_PASSWORD.
# This runs before mfi_schema.sql (alphabetical order: 00 < mfi).

set -e

echo "Creating replicator role..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'replicator') THEN
            CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '${POSTGRES_PASSWORD}';
            RAISE NOTICE 'Replicator role created successfully';
        ELSE
            RAISE NOTICE 'Replicator role already exists';
        END IF;
    END
    \$\$;
EOSQL

echo "Replicator role ready."
