# Work Note — Normal-profile daily CI

The coordinator assigned the existing nightly intent from exact commit
`0110a56430470106ad7ffed6c96707d3eb5cc636` to this CI/harness lane after receipt of
the frozen product patch. This is a separate commit after inactive native
compatibility checkpoint `5f6469e2cc6b314902b9b9b86495cd14e7dc484c`; it does not
activate compatibility or authorize a hosted run. PR #40 remote remains unchanged.

## Source and affected checks

Preserve the original schedule and concurrency expressions exactly: cron
`0 5 * * *` with native `America/New_York` timezone, daily 05:00 Eastern (EST/EDT),
and a distinct `ci-nightly` group. Keep the existing unique manual campaign group,
push/PR cancellation, normal/full manual choice, and normal profile for ordinary
and scheduled runs. There is no automatic full-profile campaign or new matrix.
GitHub's [schedule contract](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)
supports native IANA timezones, the latest default-branch source, and possible
queue delay/dropped schedules. A source declaration does not prove a real trigger.

The compiled producer, both existing macOS shard identities, Linux checks and
aggregate keep their existing gates. Empty scheduled path evidence selects all
platforms conservatively; producer or skipped/failed selected shards cannot pass
the aggregate. Testing-profile and contributor documentation must describe the
normal nightly while preserving manual full behavior and artifact lifetimes.

Exercise the schedule's ordinary plan with hostile manual values, workflow
profile/concurrency contracts, existing path-gate/aggregate fixtures and local
documentation links under fresh admission and the nonblocking portfolio lock.
Keep the product-owned path-gate fixture/source and all frozen handoff bytes
unchanged. Required make entrypoints remain unavailable locally at absent Swift
and plutil; native/scheduled execution remains a hosted proof obligation.

## Result

The final activation/schedule union passed 116 portable fixture tests in 13.061
seconds, the complete existing path-gate/aggregate fixtures and 302 local
documentation links. Fresh admission was 15.41% CPU; the nonblocking portfolio
lock was acquired and owned scratch absence verified. The first union exposed
an existing exact concurrency assertion that lacked the new nightly branch; it
now requires all three branches while preserving manual uniqueness/cancellation.
Schedule and concurrency bytes match `0110a5643` exactly. Removing those two
changes reproduces the entire producer/shard/aggregate workflow at `5f6469e2c`.
