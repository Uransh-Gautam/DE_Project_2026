# Scalability Report

## 1. Overview

The goal was to compare the optimized query timings on the seed and large datasets and review a partitioning design for selected tables. The database was PostgreSQL, using `instagram_large` for the large run. The large dataset has about 20× the seed rows. There were 30 queries: 24 reads (R01–R24) and 6 writes (W01–W06). Each query was run 3 times and the reported value is the average. The same optimized queries from `sql/06_optimized_queries.sql` were used on both datasets.

TODO: exact seed and large row counts by table.

## 2. Results

Times are in milliseconds. Growth factor is large average divided by seed average. Targets are strict upper bounds as supplied.

| Query | Type | Target (ms) | Seed avg (ms) | Large avg (ms) | Growth | Meets target? |
| :---: | :---: | ---: | ---: | ---: | ---: | :---: |
| R01 | READ | 5 | 1.171 | 6.230 | 5.3× | No |
| R02 | READ | 5 | 0.152 | 0.119 | 0.8× | Yes |
| R03 | READ | 5 | 0.134 | 0.166 | 1.2× | Yes |
| R04 | READ | 5 | 0.522 | 0.310 | 0.6× | Yes |
| R05 | READ | 250 | 1.068 | 14.659 | 13.7× | Yes |
| R06 | READ | 250 | 1.212 | 26.074 | 21.5× | Yes |
| R07 | READ | 5 | 0.095 | 0.625 | 6.6× | Yes |
| R08 | READ | 250 | 0.142 | 0.589 | 4.1× | Yes |
| R09 | READ | 5 | 0.234 | 3.245 | 13.9× | Yes |
| R10 | READ | 250 | 0.069 | 0.533 | 7.7× | Yes |
| R11 | READ | 5,000 | 3.201 | 34.349 | 10.7× | Yes |
| R12 | READ | 5,000 | 0.992 | 58.222 | 58.7× | Yes |
| R13 | READ | 250 | 0.140 | 0.232 | 1.7× | Yes |
| R14 | READ | 250 | 0.505 | 1.165 | 2.3× | Yes |
| R15 | READ | 5,000 | 18.069 | 222.665 | 12.3× | Yes |
| R16 | READ | 250 | 0.354 | 9.371 | 26.5× | Yes |
| R17 | READ | 5,000 | 2.684 | 26.863 | 10.0× | Yes |
| R18 | READ | 5,000 | 0.957 | 15.513 | 16.2× | Yes |
| R19 | READ | 5,000 | 98.423 | 1,367.293 | 13.9× | Yes |
| R20 | READ | 5,000 | 3.655 | 53.536 | 14.6× | Yes |
| R21 | READ | 250 | 0.380 | 4.647 | 12.2× | Yes |
| R22 | READ | 250 | 0.203 | 3.682 | 18.1× | Yes |
| R23 | READ | 5 | 0.088 | 0.098 | 1.1× | Yes |
| R24 | READ | 5,000 | 1.488 | 18.180 | 12.2× | Yes |
| W01 | WRITE | 5 | 0.959 | 1.519 | 1.6× | Yes |
| W02 | WRITE | 5 | 0.597 | 0.874 | 1.5× | Yes |
| W03 | WRITE | 5 | 0.495 | 0.974 | 2.0× | Yes |
| W04 | WRITE | 3,000 | 362.435 | 7,168.640 | 19.8× | No |
| W05 | WRITE | 3,000 | 21.037 | 432.124 | 20.5× | Yes |
| W06 | WRITE | 5 | 0.706 | 5.734 | 8.1× | No |

R01 (6.230 ms against a target below 5 ms), W06 (5.734 ms against a target below 5 ms), and W04 (7,168.640 ms against a target below 3,000 ms) miss their targets on large data. Every other query meets its target.

## 3. Scaling analysis

**Flat:** R02, R03, R04, R13, and R23 have differences below 1 ms between seed and large runs. At these timings, differences under 1 ms are measurement noise; the ratios below 1× for R02 and R04 are not speedups.

**Roughly linear relative to the approximately 20× data increase:** R06 (21.5×), W04 (19.8×), and W05 (20.5×).

**Sublinear:** Most reads grew by less than the approximately 20× data increase. R19 grew 13.9× on approximately 20× data.

**Superlinear:** R12 grew 58.7× and R16 grew 26.5×. The supplied material does not include their EXPLAIN output, so the causes cannot be established here.

TODO: EXPLAIN (ANALYZE, BUFFERS) plans for R12 and R16 to identify plan evidence for their growth.

Lookups should not be described as scaling logarithmically: R07 grew 6.6×, R08 grew 4.1×, and R10 grew 7.7×.

## 4. Partitioning design

The supplied `08_partitioning.sql` creates separate `_partitioned` copies and leaves the original tables unchanged. Thus the 30 benchmark queries above ran on the unpartitioned tables.

| Table | Partitioning key and boundaries | Default partition | Indexes defined in the SQL |
| --- | --- | --- | --- |
| `likes_partitioned` | RANGE on `created_at`: 2025-01-01 to 2025-07-01; 2025-07-01 to 2026-01-01; 2026-01-01 to 2026-07-01 | `likes_default` | Primary key `(user_id, post_id, created_at)`; `(post_id, created_at DESC) INCLUDE (user_id)` |
| `posts_partitioned` | RANGE on `created_at`: 2025-01-01 to 2025-07-01; 2025-07-01 to 2026-01-01; 2026-01-01 to 2026-07-01 | `posts_default` | Primary key `(post_id, created_at)`; partial `(user_id, created_at DESC) WHERE NOT is_archived`; `(created_at)`; GIN trigram on `location_name` |
| `stories_partitioned` | RANGE on `expires_at`: MINVALUE to 2026-06-01; 2026-06-01 to MAXVALUE | None defined | Primary key `(story_id, expires_at)`; `(user_id, created_at DESC)`; `(expires_at)` |
| `follows_partitioned` | LIST on `status`: `ACCEPTED` and `PENDING` | None defined | Primary key `(follower_id, followee_id, status)`; `(followee_id, created_at DESC)` |

Because a partitioned primary key must include the partition key, uniqueness is weaker than a key on the original pair or identifier alone. In the supplied design, likes can repeat for the same user/post at different `created_at` values, and follows can have both `PENDING` and `ACCEPTED` rows for the same follower/followee pair. Updating `follows.status` moves a row between partitions, which is relevant to W06. Partitioning follows by status only helps queries restricted to `PENDING`; the supplied design comments say about 96% of rows are `ACCEPTED`. The date boundaries are fixed in the SQL, so data outside the explicit ranges lands in the default partition where one is defined. The `_partitioned` copies roughly double storage while both copies are kept.

## 5. Partitioning results

The SQL contains EXPLAIN statements for pruning demonstrations, but their measured outputs were not included in the supplied materials. The SQL comments are not measured run results and are not used as timing evidence. Therefore, partition counts scanned/pruned, actual rows, and execution times cannot be reported here.

TODO: paste the EXPLAIN (ANALYZE, BUFFERS) outputs for the partitioning proofs, including partitions scanned and pruned, actual rows, and execution times.

TODO: re-time R12/R15/R19/W04/W05/W06 on partitioned tables and provide `summary_partitioned.csv` for before/after comparisons.

Partitioning does not automatically address every slow query. R12 includes a scan of `post_hashtags`, which is not partitioned in the supplied SQL; the SQL's posts partition pruning alone does not demonstrate that the full R12 query will become faster. Other affected-query outcomes also require measured plans and timings.

## 6. Conclusion, limitations, and 100× outlook

At the measured large size, W04 is the most substantial target miss, while R01 and W06 also exceed their targets. R19 is a costly read at 1,367.293 ms, though it meets its 5,000 ms target. These results compare only the seed and approximately 20× dataset sizes; they do not establish behavior at 100×.

At 100×, the first failure cannot be predicted from the supplied measurements alone. The measured target misses and high-growth queries identify candidates for further measurement, but no 100× run or supported plan-based projection was supplied.

Limitations: each query has only 3 runs, measurements came from a single machine, and differences below 1 ms are treated as noise. Exact per-table row counts and measured partitioned results are also unavailable here.

## TODO checklist

- [ ] TODO: exact seed and large row counts by table.
- [ ] TODO: EXPLAIN (ANALYZE, BUFFERS) plans for R12 and R16 to identify plan evidence for their growth.
- [ ] TODO: paste the EXPLAIN (ANALYZE, BUFFERS) outputs for the partitioning proofs, including partitions scanned and pruned, actual rows, and execution times.
- [ ] TODO: re-time R12/R15/R19/W04/W05/W06 on partitioned tables and provide `summary_partitioned.csv` for before/after comparisons.
