# how-to-postgres

A disposable PostgreSQL instance, a monitoring stack around it, and a set of scripted
incidents you can fire at it. Break it, watch what moves on the dashboard, try to fix it
without restarting, then read how it was supposed to be fixed.

## Why

At work I handle observability and incident response. We have several PostgreSQL instances
monitored with Zabbix, and while I can read the metrics and understand the high-level problems
(a database slowing down because the disk is full, row-level locking from concurrent
transactions), I don't really understand the internals: how the WAL actually works, what a
checkpoint is, how a given setting changes behavior under load.

I don't want to become a DBA. I want to be a good SRE and understand Postgres enough to build
monitoring around it, recognize an incident when it happens, mitigate it, and explain why it
happened. That is the whole scope of this repo.

The project started as "run a real database with real data sources and grow monitoring around
it". That turned out to be the slow way to learn what I actually care about, so it changed
direction: see [ADR-0005](docs/decisions/0005-changing-direction-of-the-project.md). Now the
database is a dummy one, the data is whatever `pgbench` creates, and the actual project is
the incidents.

## What is in the box

| Component | Role |
|---|---|
| `postgres:18` (`db`) | The lab instance. Intentionally small: `max_connections=20`, `shared_buffers=128MB`, 1 GB memory limit, so incidents reproduce in minutes. |
| `postgres_exporter` | Postgres metrics for Prometheus (`pg_stat_*`, `pg_stat_statements`). |
| cAdvisor | Container-level CPU/memory/IO, so you can see the OOM killer and disk pressure from outside the database. |
| Prometheus | Scrapes both, 90 days retention. |
| Grafana | Dashboards. Runs on its own SQLite and does not touch the lab database. |
| Traefik | Optional TLS in front of Grafana and Prometheus via Cloudflare DNS challenge. |

The database is provisioned once, on first boot, by `scripts/setup.sh`
(mounted into `/docker-entrypoint-initdb.d/`). It creates the exporter user, a read-only
monitoring user, and the `pgbench` role and database from the values in `.env`. It only runs
when the data volume is empty, so `docker compose down -v` gives you a clean slate.

`docs/decisions/` holds the reasoning behind some choices (why cAdvisor instead of the
docker stats receiver, why the OTel Collector was dropped, why the direction changed).

## Running it

1. Copy `.env.example` to `.env` and fill it in.

   The lab talks about two things by name: the `app` role (what all the load runs as) and
   the `lab` database (what pgbench fills). Those are just the defaults in `.env.example`:

   ```
   PGBENCH_DB_USERNAME="app"
   PGBENCH_DB_PASSWORD="app"
   PGBENCH_DB_NAME="lab"
   ```

   Change them if you want, the scripts read whatever is in `.env`. Just remember the
   incident and solution docs say `app` and `lab` literally, so you'll be translating.

2. Bring the stack up:

   ```bash
   docker compose up -d
   ```

   First boot logs `sourcing /docker-entrypoint-initdb.d/setup.sh`. If you see
   `Skipping initialization` instead, the volume was not empty and nothing was provisioned.

3. Provision the lab objects from the host (needs `psql` and `pgbench` installed locally):

   ```bash
   make init
   ```

   This installs the extensions, runs `pgbench -i` at the configured scale, and creates the
   `orders` table several incidents use. It is idempotent.

The connection settings for `make` are read from `.env`, so the Makefile and compose should
always match. Anything can still be overridden on the command line:

```bash
make init PGPORT=5499
```

## The incident loop

```bash
make baseline        # steady load: pgbench at a fixed TPS + a new-connection probe
make list            # the available incidents
make incident-01     # fire one
# ... watch Grafana, read docs/incidents/01-*.md, try to mitigate ...
make stop-01         # kill its clients, revert the GUCs it changed
make reset           # everything back to steady state
```

Each incident has three parts:

- `scripts/NN-*/start.sh` produces it (and `stop.sh` when undoing it needs more than
  killing clients).

- `docs/incidents/NN-*.md` explains what is happening inside Postgres, what it looks like on
  the dashboard, and what questions to ask yourself while it is happening.

- `docs/solutions/NN-*.md` is the answer sheet: how to mitigate it, prioritizing whatever does
  not need a restart, because in production you often can't.

The mitigation is the point. For example, incident 01 exhausts `max_connections` and you learn
that raising it is the wrong first move even when a restart is free.

## Current status

The base stack works: Postgres comes up provisioned on the first `compose up` with no manual
SQL, Prometheus scrapes both exporters, Grafana has its datasource provisioned, and the
Makefile, the incident scripts and the lab config (`docs/lab-config.md`) match the compose
file and `.env`.

The incident scripts, the incident write-ups and the solutions were AI-generated as a first
draft. I have not verified them yet and will only commit them once I have reviewed them by
hand. The plan is to go through them one at a time: run the incident against the stack, check that it does
what the write-up claims, check that the solution actually mitigates it (and that it does so
without a restart where the doc says it does), fix whatever is wrong, and only then commit
that incident.

I will build the dashboard on top of each incident after I review it: fire it, see what moves,
add the panels that would have caught it. So the dashboard grows one verified incident at a
time rather than being designed up front.

Until an incident passes that review it stays gitignored (`scripts/`, `docs/incidents/`,
`docs/solutions/`, `Makefile`). What is committed is meant to be correct. What is not
committed is still a draft.

The next steps of the project are:

1. Commit the working base (compose, config, provisioning script) on its own.

2. Review and test every incident and solution, one commit per incident, building the
   dashboard as each one lands.

3. Cover the gaps below.

Known gaps:

- Incidents 22 and 23 (replication lag, standby conflicts) need a streaming replica the
  compose file does not have yet. Their scripts say so and exit.

- `archive_mode` is on with a `pgbackrest` archive command, but pgbackrest is not installed
  in the image, so every archive attempt fails and WAL is retained. Either wire up pgbackrest
  or drop the two flags.

- Only the Metrics Drilldown in Grafana has data. Logs/Traces/Profiles need Loki, Tempo and
  Pyroscope, which are not part of this stack YET, so there is still a lot of observability work
left to do.
