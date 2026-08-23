CREATE USER {OTEL_POSTGRES_USERNAME} WITH PASSWORD {OTEL_POSTGRES_PASSWORD};

GRANT pg_monitor TO {OTEL_POSTGRES_USERNAME};

-- (Optional) If you need to enable pg_stat_statements to check slow queries
-- CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
