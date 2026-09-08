# ADR-0003: Drop OTEL Collector

- **Date:** 2026-09-08
- **Applies to:** `otel-collector`

I've been thinking about this, I'm not happy with the metrics that the docker reciever is exporting, I migrated it to cAdvisor and now the collector is just a middeman wasting resources, I think, for this project in particular, the collector doesn't add value anymore, just unnecesary overhead, so I'm dropping it.
