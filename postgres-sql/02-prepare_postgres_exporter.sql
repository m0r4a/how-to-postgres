CREATE USER {PE_POSTGRES_USERNAME} WITH PASSWORD {PE_POSTGRES_PASSWORD};

GRANT pg_monitor TO {PE_POSTGRES_USERNAME};

-- (Optional) If you need to enable pg_stat_statements to check slow queries
-- I use it for the Prometheus Exporter
-- CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
