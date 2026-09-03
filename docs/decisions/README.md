# Decision records

In this file I explain way some stuff in this repo are the way they are.

I want to explain on earch record the **reasoning** behind, I want to have documented for my future self why I did something that way or configured like that, I won't want the troubleshooting hours to go to waste.

---

## Status

Records carry no status while they are live. **Absence means active.** Only
records that have stopped applying get a status line, so in the normal case
there is nothing to maintain.

| Status | Meaning | Use when |
|--------|---------|----------|
| *(no status line)* | **Active** | Default. The decision is live an probably shouldn't be in the config |
| `Superseded by ADR-000N` | **Replaced** | The problem still exists, but a later record solves it differently. The replacement record explains the new approach. |
| `Reverted` | **Undone** | I backed the change out and returned to the previous behavior, without a replacement record. Say why in one line. |
| `Obsolete` | **Context gone** | The thing this was about no longer exists (component removed, service retired). Nothing replaced it because nothing needs to. |

`Superseded` vs `Reverted`: both mean the config no longer matches the record. Superseded points forward to where the reasoning continued and the reverted is a dead end. If I write a follow-up record, it's Superseded.

### Placement

The status line goes **first** in the header block, above the date, so it is
visible without scrolling:

```markdown
# ADR-0003: Some decision

- **Superseded by:** [ADR-0007](0007-the-replacement.md)
- **Date:** 2026-08-28
- **Applies to:** ...
```

---

## Da Rules

These exist so the records stay trustworthy years from now.

1. **Never edit the body of a record that has stopped applying.** Add the
   status line and leave the reasoning intact. The reasoning is the entire
   value. A future reader needs to know what you tried and why, especially
   when it did not work out.

2. **Never delete a record.** Reverted and obsolete records are the ones that
   stop you from repeating a mistake.

3. **Never renumber.** The number is a permanent address, the config comments and
   other records point at it.

4. **Change the status in the same commit as the config change.** That way
   `git blame` on a YAML line leads to a commit that also touched the record
   explaining it.

5. **Update the index below in that same commit.** One line, one table row.

---

## Index

Strike through a row when its record is no longer active.

| # | Decision | Date |
|---|----------|------|
| ~~[0001](0001-normalize-docker-stats-percentage-metrics.md)~~ | ~~Normalize docker_stats percentage metrics to true ratios~~ | 2026-08-28 |
| [0002](0002-replace-docker-stats-with-cadvisor.md) | Replace docker_stats with cAdvisor for container metrics | 2026-09-03 |
