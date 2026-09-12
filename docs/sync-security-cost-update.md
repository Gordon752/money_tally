# Sync security cost update — September 12, 2026

## Result and scope

The new deletion barrier adds roughly **$1.98/month per 1,000 typical active
synced users**, or **$19.80/month at 10,000**, under the explicit activity model
below, before any remaining free allowance. This is an **addition**, not a total
backend bill. It is a code-based planning estimate, not a production load test.
No load was generated against real user data.

The earlier full cost audit is not stored in this checkout; these scenarios are
independently stated so its baseline is not silently combined with different
usage assumptions. Storage, ordinary sync reads/writes, authentication, egress,
restore history and deletion cleanup must still be included in the total bill.

## Verified price and request model

The project uses Firestore Standard in `nam5` (North America 5). Google's Cloud
Billing Catalog API returned these USD prices effective September 12, 2026:

| Item | SKU | Paid rate |
| --- | --- | ---: |
| Document reads | 369B-DC02-4DAB | $0.06 / 100,000 |
| Document writes | 0FD8-FD9E-2D84 | $0.18 / 100,000 |

Catalog service: `EE2C-7FAC-5E08`. Evidence was retrieved via the authenticated
[Cloud Billing Catalog API](https://cloud.google.com/billing/docs/how-to/catalog-api),
not the pricing page's default single-region selection.

The rule checks one server-only `accountDeletions/{uid}` document. Firestore bills
dependent rule reads per request and evaluates a shared dependency once within
that request, not once for every returned record. The daily 50,000-read allowance
is shared with the rest of the project's eligible database usage; do not subtract
it a second time from this addition. [Firestore billing](https://firebase.google.com/docs/firestore/pricing)

Code inspection of `loadDataSetForSync` found 14 core client requests: an authority
read, checkpoint write/read, ten collection queries and one preferences read.
This model budgets **15 dependent reads per sync**, including one request of
headroom. An ordinary changed-document transaction budgets **two dependent
reads**, one for its read and one for its commit. A business action may change
multiple documents: count documents, not taps. SDK retries and conflicts can add
requests; these are assumptions, not measured invoice counters.

Full bootstrap and seven-day refresh use the same collection-request shape;
their existing document-read and egress costs still grow with ledger size.
Client sync-activity counters do not include these server-side rule reads.
Server Admin SDK operations do not use client security rules.

## Incremental monthly scenarios

All scenarios use 30 days. Changed documents are totals across devices and
include account, preference, scheduled, fund/goal and transaction changes.

| Profile | Devices | Syncs/device/day | Changed documents/day | Extra reads/user/month |
| --- | ---: | ---: | ---: | ---: |
| Light | 1 | 2 | 5 | 1,200 |
| Typical | 2 | 3 | 10 | 3,300 |
| Heavy | 3 | 8 | 30 | 12,600 |

Formula: `30 × (devices × daily syncs × 15 + changed documents × 2)`.

| Active synced users | Light extra USD/mo | Typical extra USD/mo | Heavy extra USD/mo |
| ---: | ---: | ---: | ---: |
| 100 | 0.07 | 0.20 | 0.76 |
| 1,000 | 0.72 | 1.98 | 7.56 |
| 5,000 | 3.60 | 9.90 | 37.80 |
| 10,000 | 7.20 | 19.80 | 75.60 |
| 25,000 | 18.00 | 49.50 | 189.00 |
| 50,000 | 36.00 | 99.00 | 378.00 |
| 100,000 | 72.00 | 198.00 | 756.00 |

Reproduce with `node tool/sync_rule_cost_estimate.mjs`. The script contains formula
assertions. Actual incremental billing can be lower while daily free reads
remain. For each day, the read-charge increase is
`rate × (max(0, existing + extra − 50000) − max(0, existing − 50000))`.
Do not treat an unused allowance on one day as transferable to another.

The typical barrier overhead alone is 110 reads/user/day; dividing 50,000 by
110 is **not** the app's free-user ceiling, because normal sync and refreshes
also consume reads. Retry/restore storms are outside these steady-state figures.

## Added deletion monitoring

One read-only scheduled function checks pending deletion markers every 30 minutes.
With none pending: approximately 1,440 invocations and minimum query reads per
30-day month, about **$0.000864/month** in gross Firestore reads. With pending
requests it reads up to 501 projected status records per run; reaching that limit
itself alerts. This bound prevents an unbounded scan, not a cap on all backend cost.

Cloud Scheduler charges $0.10/job/month beyond three free jobs shared by the
billing account. Function compute/invocations, deployment artifacts and logs are
separate usage; at this frequency they should be small but aren't guaranteed free
if shared allowances are exhausted. [Scheduler pricing](https://cloud.google.com/scheduler/pricing)

Current Monitoring documentation says alert-policy charging starts no sooner than
September 1, 2027. Recheck before then; this is not a promise of free monitoring
forever. [Monitoring pricing](https://cloud.google.com/products/observability/pricing)

Deletion calls and retries still incur their own document cleanup and function
usage. Completed barrier markers are retained, so storage grows with the number
of deleted accounts, though the monitor excludes completed markers from its query.

## Practical conclusion

The protection is worth retaining; it does not materially change the earlier
business-model discussion at small launch volumes. Use the extra-cost table when
revisiting the full audit, and compare real billing with observed activity after
launch. The existing $25 budget and billing settings were not changed.
