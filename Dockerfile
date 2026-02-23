# Dockerfile - Primary PostgreSQL 17
FROM postgres:17

# Set environment variables
ENV POSTGRES_DB=mfi_banking
ENV POSTGRES_USER=postgres
ENV PGDATA=/var/lib/postgresql/data

# Copy initialization scripts (runs only on first container start)
# Files execute in alphabetical order: 00-init-replication.sh runs first
COPY init-scripts/00-init-replication.sh /docker-entrypoint-initdb.d/
COPY init-scripts/mfi_schema.sql /docker-entrypoint-initdb.d/
RUN chmod +x /docker-entrypoint-initdb.d/00-init-replication.sh

# Copy configuration files
COPY config/postgresql.conf /etc/postgresql/postgresql.conf
COPY config/pg_hba.conf /etc/postgresql/pg_hba.conf

# Create archive directory for WAL archiving
RUN mkdir -p /var/lib/postgresql/archive && chown postgres:postgres /var/lib/postgresql/archive

EXPOSE 5432
