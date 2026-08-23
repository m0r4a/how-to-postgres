-- NOTE: this "env vars" are representative, I had to
--       manually change them to fit the real env vars.

CREATE USER {ATUIN_DB_USERNAME}
  WITH PASSWORD '{ATUIN_DB_PASSWORD}';

CREATE DATABASE {ATUIN_DB_NAME}
  WITH OWNER {ATUIN_DB_USERNAME}
  CONNECTION LIMIT 10;
