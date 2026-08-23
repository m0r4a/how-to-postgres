-- NOTE: this "env vars" are representative, I had to
--       manually change them to fit the real env vars.

CREATE USER {GRAFANA_DB_USERNAME}
  WITH PASSWORD '{GRAFANA_DB_PASSWORD}';

CREATE DATABASE {GRAFANA_DB_NAME}
  WITH OWNER {GRAFANA_DB_USERNAME}
  CONNECTION LIMIT 10;
