# ADR-0002: Replace docker_stats with cAdvisor for container metrics

- **Date:** 2026-09-03
- **Applies to:** `otel-collector` `prometheus` receiver, `cadvisor` service
- **Related config:** `metrics/cadvisor` pipeline in `otel-config.yaml`, `cadvisor` service in `compose.yaml`, `prometheusreceiver` in `build-otel-collector/builder-config.yaml`
- **Related:** [ADR-0001](0001-normalize-docker-stats-percentage-metrics.md) (superseded by this)

---

## Summary

I moved container monitoring off the OpenTelemetry `docker_stats` receiver onto
cAdvisor. `docker_stats` only exposed the aggregate numbers `docker stats` prints
on the terminal, which is not enough detail to reason about a container. cAdvisor
exposes the full cgroup metric surface (per core, per filesystem, per interface,
throttling, a real memory breakdown), which is the detail I need.

cAdvisor runs as its own service and publishes Prometheus metrics on
`:8080/metrics`. The collector scrapes it through the `prometheus` receiver into a
dedicated `metrics/cadvisor` pipeline. The old `docker_stats` receiver, its two
docker-label processors, the `metrics/docker` pipeline, and the
`docker-socket-proxy` container are removed.

This also removes the ADR-0001 problem. cAdvisor emits native Prometheus counters
and gauges with correct units (`container_cpu_usage_seconds_total`,
`container_memory_working_set_bytes`, and so on), so there is no OTel `unit: "1"`
mismatch and no wrong `_ratio` suffix. The `transform/dockerstats_scale`
workaround has nothing left to fix.

## Why docker_stats was not enough

The `docker_stats` receiver mirrors `docker stats`, which is a top-level summary:
CPU %, memory usage and %, aggregate network I/O, aggregate block I/O, PIDs. There
is no per-core CPU, no per-filesystem usage, no per-interface network breakdown,
no cgroup CPU throttling, and no detailed memory accounting (working set vs cache
vs RSS vs swap). Those are the dimensions I want when a container misbehaves, and
`docker_stats` does not carry them. Its two useful numbers also came with the
unit-scaling defect from ADR-0001 and a sampling defect that needed
`stream_stats: true` for a real CPU rate.

## What cAdvisor provides

cAdvisor reads cgroups and the Docker API directly and exposes the full container
metric set in Prometheus exposition format. The series are counters and gauges
with correct, unambiguous units, so they pass through the OTLP to Prometheus
translator cleanly where `docker_stats` did not.

## Decision

1. Run cAdvisor as a service on the `monitoring` network, scraping only Docker
   containers.
2. Scrape it with the collector's `prometheus` receiver on `cadvisor:8080`.
3. Feed it through a dedicated `metrics/cadvisor` pipeline so it picks up the
   shared `attributes/environment` label and uses the same `prometheus` exporter.
4. Remove the `docker_stats` receiver, its `attributes/docker_job` and
   `transform/docker_labels` processors, the `metrics/docker` pipeline, and the
   `docker-socket-proxy` container.

Collector receiver and pipeline (`otel-config.yaml`):

```yaml
receivers:
  prometheus:
    config:
      scrape_configs:
        - job_name: 'cadvisor'
          scrape_interval: 10s
          static_configs:
            - targets: ['cadvisor:8080']

service:
  pipelines:
    metrics/cadvisor:
      receivers: [prometheus]
      processors: [memory_limiter, attributes/environment, batch]
      exporters: [prometheus]
```

cAdvisor service (`compose.yaml`):

```yaml
cadvisor:
  image: ghcr.io/google/cadvisor:v0.60.5
  container_name: cadvisor
  restart: unless-stopped
  privileged: true
  devices:
    - /dev/kmsg:/dev/kmsg
  volumes:
    - /:/rootfs:ro
    - /var/run:/var/run:ro
    - /sys:/sys:ro
    - /var/lib/docker/:/var/lib/docker:ro
    - /dev/disk/:/dev/disk:ro
  command:
    - "--docker_only=true"
    - "--housekeeping_interval=10s"
    - "--store_container_labels=false"
    - "--disable_metrics=percpu,sched,tcp,udp,process,hugetlb,referenced_memory,cpu_topology,resctrl"
  networks:
    - monitoring
```

Flag choices:

- `--docker_only=true`: report only Docker containers, not the machine cgroups and
  system slices cAdvisor would otherwise emit. That cuts a large amount of noise.
- `--disable_metrics=percpu,sched,tcp,udp,process,hugetlb,referenced_memory,cpu_topology,resctrl`:
  cAdvisor's default metric set is large, and several families are high cardinality
  or unused here. `percpu` grows with core count; `tcp`/`udp` add a per-container
  connection-state matrix; `sched`, `process`, `hugetlb`, `referenced_memory`,
  `cpu_topology`, `resctrl` are detail this stack does not use. Dropping them at
  the source is simpler than filtering after ingestion.
- `--store_container_labels=false`: do not turn every Docker container label into a
  Prometheus label. That is a cardinality and churn risk, and the labels I want
  are added in the collector.
- `--housekeeping_interval=10s`: match cAdvisor's sampling to the 10s scrape
  interval.
- `privileged: true` and the host mounts (`/`, `/var/run`, `/sys`,
  `/var/lib/docker`, `/dev/disk`, `/dev/kmsg`): cAdvisor needs broad read access to
  the host to read cgroups and container state. This is a security trade-off (see
  Consequences); the mounts are read-only.

Collector memory was raised in the same change:

```yaml
processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 1024      # was 150
    spike_limit_mib: 200 # was 30
```

cAdvisor's scrape payload is much larger than what `docker_stats` produced (many
more series per container), so the old 150 MiB limit would trip the limiter under
normal load. 1024 MiB gives the prometheus receiver and batch processor room for a
scrape.

## Alternatives considered

**Keep `docker_stats` and accept the low detail.** Rejected. That is the problem
being fixed: it never carried the per-core, per-filesystem, or throttling detail,
and its two useful metrics needed the ADR-0001 workaround.

**Run both `docker_stats` and cAdvisor.** Rejected. They cover the same
containers, so this is duplicate series for no benefit: two sources for CPU and
memory, twice the storage, and the ADR-0001 defect still present on the
`docker_stats` copy.

**Let Prometheus scrape cAdvisor directly instead of routing through the
collector.** Rejected for consistency. Routing through the collector's
`prometheus` receiver keeps container metrics on the same path as everything else,
so they get the shared `attributes/environment` label and the same exporter.

## Consequences

Positive:

- Per-container detail I did not have before: per-core CPU, throttling,
  per-filesystem usage, per-interface network, and a real memory breakdown.
- The ADR-0001 `_ratio` unit-mismatch bug is gone. cAdvisor's units are correct at
  the source, so there is nothing to normalize and no double-correction risk on
  collector upgrades.
- Simpler collector config: no docker-label transform, no `stream_stats` streaming
  connection, no `docker-socket-proxy` sidecar.

Negative:

- cAdvisor runs `privileged: true` with broad host mounts, a larger attack surface
  than the read-only `docker-socket-proxy` it replaces. The mounts are read-only
  to limit that, but this is the main cost of the switch.
- Higher cardinality and volume. Even with `--docker_only` and the
  `disable_metrics` list, cAdvisor emits many more series than `docker_stats`. The
  `disable_metrics` list is the lever if the series count becomes a problem.
- Higher collector memory, hence the `memory_limiter` bump to 1024 MiB. If the
  limiter starts dropping data again, check this first.

Leftover: the `dockerstatsreceiver` gomod is still listed in
`build-otel-collector/builder-config.yaml` and is compiled in but unused. It can
be dropped in a follow-up; it is harmless left in place.

## How to check it is working

Against a running stack:

```promql
# 1. cAdvisor series are arriving.
container_cpu_usage_seconds_total
container_memory_working_set_bytes

# 2. The scrape target is healthy.
up{job="cadvisor"}
```

If (1) returns series for the running containers and (2) is `1`, the pipeline is
live. If the collector logs show the `memory_limiter` refusing data, raise
`limit_mib` first.

## References

- [cAdvisor](https://github.com/google/cadvisor)
- [cAdvisor: Prometheus metrics exposition](https://github.com/google/cadvisor/blob/master/docs/storage/prometheus.md)
- [OpenTelemetry Collector: prometheus receiver](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/prometheusreceiver/README.md)
- [ADR-0001: the docker_stats unit-scaling workaround this supersedes](0001-normalize-docker-stats-percentage-metrics.md)
