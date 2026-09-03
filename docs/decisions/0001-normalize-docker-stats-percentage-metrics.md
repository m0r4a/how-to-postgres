# ADR-0001: Normalize docker_stats percentage metrics to true ratios

- **Superseded by:** [ADR-0002](0002-replace-docker-stats-with-cadvisor.md). I replaced `docker_stats` with cAdvisor, so this workaround no longer runs. The reasoning below is kept intact: it is the whole value of the record.
- **Date:** 2026-08-28
- **Applies to:** `otel-collector`, `docker_stats` receiver (opentelemetry-collector-contrib)
- **Related config:** `transform/dockerstats_scale` processor, `stream_stats: true` on the receiver

---

## Summary

The `docker_stats` receiver emits `container.memory.percent` and
`container.cpu.utilization` on a 0-100 scale, but declares them with OpenTelemetry
`unit: "1"` (a dimensionless 0-1 ratio). The Prometheus translator trusts the
declared unit and appends a `_ratio` suffix, so the stored series is named for a
range its values never occupy. A container using 1.84% of memory is stored as
`1.84` under `container_memory_percent_ratio` and rendered as 184%.

The fix divides these two metrics by 100 in a `transform` processor so the value
matches the unit the receiver claims. A second, unrelated defect on the CPU
metric is fixed by `stream_stats: true`.

## Symptom

Grafana Metrics Drilldown showed the postgres container's memory at 170-185%.
Memory above 100% is not possible, so the number was wrong, but nothing in the
pipeline reported an error.

## Where the metrics come from

The receiver mirrors what `docker stats` shows, and `docker stats` reports
`MEM %` on a 0-100 scale. The metrics were originally named
`container.memory.percent` and `container.cpu.percent`. A metric named "percent"
returning `1.84` to mean 1.84 percent is consistent, so this line is correct for
the name it was written under:

```go
// receiver/dockerstatsreceiver/metric_helper.go
return float64(usedNoCache) / float64(limit) * 100.0
```

The `* 100.0` is not the bug. Removing it would break the metric in the other
direction.

The contradiction is in the `unit` field:

```yaml
# receiver/dockerstatsreceiver/metadata.yaml
container.memory.percent:
  unit: "1"
  gauge:
    value_type: double
```

Under UCUM, which OpenTelemetry references for units, `%` is valid and would have
been the correct choice. Why `"1"` was picked instead is not documented anywhere
I could find. The likely reasoning is "a percentage is dimensionless, so unit 1",
but that is reconstruction, not established fact.

Later, OTel semantic conventions standardized on `*.utilization` at 0-1 (as in
`system.cpu.utilization`), and `container.cpu.percent` was renamed to
`container.cpu.utilization` to align. The value was not rescaled, so the name
went from neutral to promising a 0-1 range the value never delivered. The code
still shows it:

```go
r.mb.RecordContainerCPUUtilizationDataPoint(now, calculateCPUPercent(v))
```

`calculateCPUPercent` fills a field named `Utilization`.

## Why it went unnoticed

The wrong `unit` was harmless for most of its life. Most backends keep that field
as a descriptive string and ignore it: ClickHouse, Datadog, and most OTLP-native
stores. Incorrect metadata that nothing reads produces no symptom.

It became load-bearing when the OTLP to Prometheus translator adopted the rule
"unit `1` on a gauge, append `_ratio`". At that point the metadata error became
part of the series identifier. The component that started failing (the
translator, Prometheus, Grafana) was not the component that was wrong (the
receiver).

## Where the value is wrong

The container uses 1.84% of its memory. There are two self-consistent ways to
encode that:

| Encoding | Value | Unit | Prometheus suffix |
|----------|-------|------|-------------------|
| Percentage | `1.84` | `%` | `_percent` |
| Ratio | `0.0184` | `1` | `_ratio` |

The receiver emits the value from row one with the unit from row two. Neither
half is wrong on its own; the pairing is. At the receiver either row is a valid
fix. Once the translator bakes `_ratio` into the series name, the direction is
committed and `1.84` is the wrong value for the field. That is why the fix divides
the value instead of relabeling the unit: the value is the incorrect half.

## The two multiplications by 100

There are two, in different components:

| # | Where | What it does | Is it the bug? |
|---|-------|--------------|----------------|
| 1 | receiver, `* 100.0` | modifies the data: `0.0184` becomes `1.84` | yes |
| 2 | Grafana, at render time | formats `1.84` into the string `"184%"` | no |

Grafana's multiplication is correct behavior: multiplying a ratio by 100 to
display it as a percentage is expected. It is display-only. Nothing stores `184`;
the query result is still `1.84`. Confirm this in the Query inspector, or by
writing `metric / 100` in PromQL and watching the axis correct while the stored
data stays the same.

If you remove Grafana entirely, the bug still exists: Prometheus holds a value
100x larger than its name promises, and every consumer, alert, or script inherits
it. The bug is upstream of Grafana.

## The full chain

| # | Layer | What it does | Verdict |
|---|-------|--------------|---------|
| 1 | `docker_stats` receiver | emits `1.84`, declares `unit: "1"` | wrong: bad output from good input |
| 2 | OTLP to Prometheus translator | sees `unit: "1"` on a gauge, appends `_ratio` | fragile: correct rule, bad input |
| 3 | Prometheus | stores and returns `1.84` faithfully | fragile: has no unit system |
| 4 | Grafana | reads `_ratio`, renders `1.84` as `184%` | fragile: correct convention, wrong name |

Only layer 1 produces incorrect output from correct input. Layers 2 to 4 produce
incorrect output from incorrect input and cannot detect it. They must not be
"fixed": teaching Grafana to ignore the `_ratio` suffix would break every
correctly labeled ratio metric.

The translation is also lossy and irreversible. Before it, the unit is a
structured field you can inspect and correct, which is what the `transform`
processor does. After it, the unit is baked into a string that doubles as the
series identifier, and Prometheus has no unit concept to recover it. (Prometheus
carries an optional OpenMetrics `UNIT` metadata field, but PromQL ignores it and
it does not travel with query results, so every consumer reads the name.) This is
why the fix lives in the collector and not in a Grafana panel.

## Verification against ground truth

Raw Prometheus values compared to `docker stats` on the same host:

| Container | `docker stats` MEM % | Prometheus raw value | Grafana rendered |
|-----------|---------------------|----------------------|------------------|
| grafana | 11.03% | 10.87 | 1087% |
| db | 1.84% | 1.838 | 184% |
| prometheus | 1.84% | 1.782 | 178% |

Arithmetic: 588.8 MiB / 5.216 GiB = 11.02%, and 98.13 MiB / 5.216 GiB = 1.84%.
The raw stored value is the percentage.

## The CPU metric has a second, unrelated defect

`container.cpu.utilization` also needs `stream_stats: true` on the receiver, fixed
separately. The two are easy to confuse, and fixing the scale without fixing the
sampling produces a silently wrong metric.

Docker does not store a "CPU %". It stores cumulative counters, and the
percentage is a rate between two reads:

```
cpuDelta    = cpu_stats.total_usage  - precpu_stats.total_usage
systemDelta = cpu_stats.system_usage - precpu_stats.system_usage
percent     = (cpuDelta / systemDelta) * onlineCPUs * 100
```

With the default `stream_stats: false`, the receiver issues one request per
scrape. A fresh connection has no prior read, so `precpu_stats` arrives zeroed
and the formula degenerates to:

```
percent = (container CPU since start / host CPU since boot) * nCPU * 100
```

That is the average since the container started. Because both sides grow without
bound, it flattens: a 30-second burst cannot move a ratio whose two sides have
accumulated for hours. The observed result was a flat 1.2% for postgres over six
hours while `docker stats` showed it moving between 0.2% and 4.5%.

`stream_stats: true` opens one persistent stats stream per container. The daemon
pushes a sample about once per second, so each sample carries a real
`precpu_stats` and the delta is a real ~1-second rate.

## Decision

1. Set `stream_stats: true` on the `docker_stats` receiver, so
   `container.cpu.utilization` is a real rate instead of a lifetime average.
2. Divide both affected metrics by 100 in a dedicated
   `transform/dockerstats_scale` processor, so the stored value matches the
   `_ratio` suffix the translator assigns.

Config:

```yaml
receivers:
  docker_stats:
    # ...existing settings unchanged...
    stream_stats: true

processors:
  # Values are 0-100 but declared as OTel unit "1", so consumers render 1.84% as 184%.
  # Requires stream_stats: true on the receiver. See docs/decisions/.
  transform/dockerstats_scale:
    metric_statements:
      - context: datapoint
        statements:
          - set(value_double, value_double / 100)
            where metric.name == "container.memory.percent"
               or metric.name == "container.cpu.utilization"
```

The processor has to be in the metrics pipeline to take effect:

```yaml
service:
  pipelines:
    metrics:
      receivers: [docker_stats]
      processors: [transform/dockerstats_scale]
      exporters: [prometheus]
```

The `where` clause is an explicit allowlist by metric name, on purpose.
`where metric.unit == "1"` would also divide metrics that are already correctly
0-1 (such as `system.cpu.utilization` from hostmetrics) and turn a visible bug
into a silent one.

Apply the two changes in that order. Fixing the scale alone yields a flat,
useless value that looks plausible: 184% at least signals something is broken,
while a flat `0.0121` does not. After a restart with `stream_stats: true`, the
first scrape or two may still report the old flat value until the stream
accumulates a prior sample, so wait two or three collection intervals before
judging it.

## Alternatives considered

**Delete the `* 100.0` in the receiver.** Rejected. That line is correct for a
metric named `percent`. Fixing it upstream would work, but I do not control
upstream, and reproducing it locally is harder than dividing at the processor.

**Override the unit on each Grafana panel.** Rejected. It fixes one panel and
leaves the stored data wrong, so every new panel, alert, and drilldown view
inherits the bug. It also does not work in Metrics Drilldown, which infers units
and offers no override.

**Disable unit suffixes globally** (`translation_strategy: NoTranslation` or
`UnderscoreEscapingWithoutSuffixes`). Rejected. This strips `_total`, `_bytes`,
and `_seconds` from the entire stack for a one-metric bug. `NoTranslation` is
also experimental and forces quoted PromQL (`{"container.memory.percent"}`),
breaking every existing query, dashboard, and rule.

**Push OTLP to Prometheus's native endpoint instead of scraping.** Rejected. It
changes nothing. Prometheus's OTLP receiver uses the same
`prometheus/otlptranslator` library with the same default strategy, so the
`_ratio` suffix is applied identically. The suffix logic is in the translation,
not the transport.

**Use only derived metrics and ignore the broken ones.** Partially adopted.
Deriving from the raw counters is more robust:

```promql
rate(container_cpu_usage_total_nanoseconds[5m]) / 1e9
```

Counters carry unambiguous units and `rate()` computes its own deltas, so this is
immune to both defects. I keep it as the verification oracle (below) rather than
the primary metric, because the goal was to make the first-party metric usable.

**Wait for an upstream fix.** Rejected. Every possible upstream fix is a breaking
change: changing the unit to `%` renames the series to
`container_memory_percent_percent`; dividing by 100 shifts everyone's values by
two orders of magnitude; renaming to `container.memory.utilization` does both.
Breaking metric changes in collector-contrib require a feature gate with a
multi-release deprecation cycle. The component is `alpha` with a single code
owner, so this will not move quickly. The precedent is the `container.cpu.percent`
to `container.cpu.utilization` rename, which shipped without rescaling the value.

## Consequences

Positive:

- `container_memory_percent_ratio` and `container_cpu_utilization_ratio` become
  true 0-1 ratios, so the `_ratio` suffix is accurate.
- Grafana renders them correctly with no panel configuration.
- The fix is scoped to two named metrics and does not touch any other series.

Negative, read before upgrading the collector:

The workaround now diverges from upstream, silently. If a future collector
release fixes the scale upstream, the `transform` will double-correct and every
value becomes 100x too small. Nothing errors; dashboards just show implausibly
low numbers. To catch it, keep this as a standing alert:

```promql
abs(
  container_cpu_utilization_ratio
  - rate(container_cpu_usage_total_nanoseconds[5m]) / 1e9
) > 0.005
```

This compares the patched metric against the counter-derived value, which is
immune to both defects, and fires on the day of the upgrade instead of months
later.

Cost of `stream_stats: true`: one persistent connection per container, held open
through the `docker-socket-proxy`. On this host the proxy's CPU rose from about
0.1% to about 2% with 8 containers. Negligible in absolute terms, but it scales
with container count. If the CPU metric goes flat again after a proxy upgrade or
timeout change, suspect the streaming connection first.

## How to check whether this is still needed

Run against a running collector:

```promql
# 1. Is any "_ratio" metric above 1? If yes, the upstream bug is still present.
{__name__=~".+_ratio"} > 1
```

```promql
# 2. Does the patched metric agree with the counter-derived value? Should be near zero.
container_cpu_utilization_ratio
  - rate(container_cpu_usage_total_nanoseconds[5m]) / 1e9
```

If check 1 returns nothing and check 2 is near zero, the workaround is working or
upstream has fixed it. To tell which, disable the `transform` processor and re-run
check 1: if values are still below 1 with it off, upstream fixed it, so supersede
this ADR and delete the processor.

If check 2 is consistently off by a factor of 100, you are probably
double-correcting (see Negative consequences).

## References

- [`metric_helper.go`: `calculateMemoryPercent`, the `* 100.0`](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/dockerstatsreceiver/metric_helper.go)
- [`metadata.yaml`: the `unit: "1"` declaration](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/dockerstatsreceiver/metadata.yaml)
- [`receiver.go`: `RecordContainerCPUUtilizationDataPoint(now, calculateCPUPercent(v))`](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/dockerstatsreceiver/receiver.go)
- [`internal/docker/config.go`: `stream_stats`, defaults to `false`](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/internal/docker/config.go)
- [`internal/docker/docker.go`: one-shot `FetchContainerStats` vs `runStatsStream`](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/internal/docker/docker.go)
- [dockerstatsreceiver README: status `alpha`, single code owner, `metrics:` enable/disable block](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/dockerstatsreceiver/README.md)
- [OpenTelemetry: Prometheus and OpenMetrics Compatibility spec](https://opentelemetry.io/docs/specs/otel/compatibility/prometheus_and_openmetrics/)
- [Prometheus: `otlp.translation_strategy` configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)
- [Docker API: container stats and the CPU percent formula](https://docs.docker.com/reference/cli/docker/container/stats/)
