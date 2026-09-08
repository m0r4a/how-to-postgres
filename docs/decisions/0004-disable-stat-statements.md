# ADR-0004: Disable / Not use stat statements for prometheus

- **Date:** 2026-09-08
- **Applies to:** `otel-collector` `prometheus`
- **Related config:** flag `--collector.stat_statements` on the `services.postgres_expotrer` inside `compose.yaml`

The metric `pg_stat_statements_seconds_total` has a time series per `queryid`, which, as you might imagine, could end into a ton of time series and cardinality, I could argue that doesn't matter much in my homelab, because is small, but I don't want to cover my mistakes with the justification of "not being a problem YET" due to the scale, so, I won't use it, this opens the posibility to, maybe, using clickhouse again to send this info.
