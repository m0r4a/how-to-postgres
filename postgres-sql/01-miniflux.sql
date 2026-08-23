-- NOTE: this "env vars" are representative, I had to
--       manually change them to fit the real env vars.

CREATE USER {MINIFLUX_DB_USERNAME}
  WITH PASSWORD '{MINIFLUX_DB_PASSWORD}';

CREATE DATABASE {MINIFLUX_DB_NAME}
  WITH OWNER {MINIFLUX_DB_USERNAME}
  CONNECTION LIMIT 10;
