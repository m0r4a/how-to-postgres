I will eventually flesh out this README, but here is a brief rundown of what this project is all about.

In my day-to-day work, I handle core observability and incident response. We have several PostgreSQL instances monitored with Zabbix (which isn't exactly my favorite tool). While I recently built and organized a Postgres dashboard for work, I realized there is a gap in my knowledge. I can see the metrics, and I understand high-level issues, like a database slowing down due to 100% disk usage or row level locking from concurrent transactions, but I don't deeply understand the internals yet. I want to fully grasp how the WAL actually works, what checkpoints really mean, and how specific engine configurations directly impact performance.

So, the general idea of this project is to learn by doing (and breaking):

1. **Deploy:** Spin up a baseline PostgreSQL database with zero tuning or fancy settings. Just get it running.
2. **Populate:** Feed it with automated, low-maintenance data sources (like RSS feeds or Atuin shell history syncing).
3. **Observe:** Monitor it with tools from this decade. I weighed a Prometheus exporter against OpenTelemetry and decided to go with the OTel Collector.
4. **Stress:** Apply pressure to the DB. Make it struggle and identify *where* it hurts using the modern monitoring stack.
5. **Tune:** Read up on available PostgreSQL settings, understand what they do, and apply them to fix or mitigate the bottlenecks.

The ultimate goal is to understand the core loop: *"Action X causes Y, which looks like Z on the Grafana dashboard, and can be mitigated with configuration K."* Not every issue will be solved by a config tweak, but I want to push the database until configuration becomes the limiting factor.

### Current Status

I'm currently on **Step 3**. I'm using [my OCB starter template](https://github.com/m0r4a/OTel-Collector-Builder-OCB-Starter-Template) to easily build a custom OpenTelemetry collector, and I'm starting to put together the dashboards. 

The immediate plan is to run the collector with only the basics enabled, build the Grafana dashboard, and let it run for a week. After that, I will enable *all* the extra telemetry. Since this is a small DB, the overhead will likely be minimal, but I want to see the difference firsthand and form an educated opinion on what is actually worth toggling on in a real-world environment.

### Running the stack

Copy `.env.example` to `.env` and fill it in first.

**Base (Postgres + Prometheus + Grafana):**

```bash
docker compose up -d
```

This is the self-contained project. The OTel Collector ships PostgreSQL and container
metrics to Prometheus, and Grafana reads from there. It does **not** depend on any
external service — this is the mode to use by default.

**With ClickHouse:**

```bash
docker compose -f compose.yaml -f compose.clickhouse.yaml up -d
```

I also run a separate, **external** ClickHouse instance for [my clickhouse project](https://github.com/m0r4a/how-to-clickhouse), I fan metrics out to it
to experiment. I wanted to decouple it using (`compose.clickhouse.yaml`) plus a config overlay (`config/otel-collector/otel-config.clickhouse.yaml`) that get merged on top of the base
config so you can still use this project as intended.

The point of this split is that a missing/unreachable ClickHouse can no longer take the
whole collector down, the base project stays alive on its own, and ClickHouse is just and opt-in. Set the `OTEL_CLICKHOUSE_*` variables in `.env` before using this mode.
