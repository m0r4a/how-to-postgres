# ADR-0005: Change the direction of the project to a purely pgbench database

- **Date:** 2026-09-15
- **Applies to:** `the whole project`
- **Related config:** `compose.yaml`, `./postgres-sql/*`, `config/grafana`

I've been thinking about this for a while. The original purpose of this project was to
understand Postgres at an _SRE level_, meaning to know enough about how it works and how it
operates to build monitoring around it and be able to respond to an incident. I don't want to
become a DBA, but I think knowing databases to a certain level is one of the core concepts in
tech.

So: understanding Postgres to get better at incident response and observability, right? Well,
the original idea was to have a regular instance running something that kept transactions
flowing, a way to leave the instance unattended and have it generate data, data I cared about
somewhat but wouldn't cry over if it got lost. But I think I could have gone about it in a
smarter way.

What do you need monitoring for? To know whether an incident is happening, what is happening,
mitigate it, and diagnose why it happened. That's what I want to learn, and it's my actual main
priority (besides learning being fun and Postgres being such an interesting tool), so I changed
my focus.

Now you get a clean database (Grafana runs on SQLite now), and the database you monitor is the
one pgbench creates, along with the tables it uses. You can run pgbench to generate a baseline,
so you don't need a service configured; you can generate incidents with a script, and I can
build dashboards from those incidents: seeing what moves and what doesn't, understanding how
each incident affects things, and polishing the dashboard little by little based on incidents.
The idea is that the end user of this project already has the dashboard built for them. And in
`docs/incidents` we'll have a description of each incident (so you can understand it and try to
mitigate it yourself), and in `docs/solutions` how to mitigate it, prioritizing not restarting,
because in prod you can't always restart.

In the end, all of this boils down to: for end users, being able to spin up a dummy Postgres
instance, generate an incident, learn what moves on the dashboard, read the details of that
incident, try to mitigate it, and then read how it was supposed to be mitigated.

And the extra I get out of it is giving a detailed review to the incident descriptions,
generating them, building the dashboard, and so on.
