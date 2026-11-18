# Optimization report (CP3)

## 1. Setup and benchmark environment

- Laptop: MacBook Pro M4 Pro (as specified in `team.json`)
- Database: PostgreSQL 18.7 (`instagram_cp2`), loaded from `seed_data/` with `sql/01_schema.sql` and `sql/02_load_data.sql`, fully analyzed.
- Workload: 30 queries defined in `sql/06_optimized_queries.sql` (markers `-- @R01` to `-- @W06` intact).
- Script: `./benchmarks/run_benchmark.sh instagram_cp2 optimized 3 sql/06_optimized_queries.sql`.
- Each number is the `Execution Time` from `EXPLAIN (ANALYZE, BUFFERS)` averaged over 3 consecutive runs.
- Server configuration was unchanged (default PostgreSQL settings, no artificial `enable_seqscan = off` or bloated `work_mem`).

---

## 2. Workload timing summary (baseline vs optimized)

| Query ID | Type | Baseline Avg (ms) | Optimized Avg (ms) | Speedup / Improvement | Plan Bottleneck (Baseline) | Optimization Applied | Same Result? |
|---|---|---:|---:|---:|---|---|---|
| **R01** | READ | 5.570 | 1.171 | **78.98% (4.8×)** | Seq Scan on 60,000 `posts` | Partial B-tree on `posts(user_id, created_at DESC) WHERE NOT is_archived` | Yes (EXCEPT = 0) |
| **R02** | READ | 2.710 | 0.152 | **94.39% (17.8×)** | Seq Scan on `posts` for `user_id = 217` | Same partial index `posts_user_active_created_idx` | Yes (EXCEPT = 0) |
| **R03** | READ | 0.026 | 0.134 | - | Baseline was already index lookup (`users_username_key`) | Left query unchanged; tiny planner variance | Yes |
| **R04** | READ | 9.178 | 0.522 | **94.31% (17.6×)** | Double Seq Scan on `comments` for post 59689 | Partial B-tree on `comments(post_id, created_at)` + index on `comments(parent_comment_id)` | Yes (EXCEPT = 0) |
| **R05** | READ | 10.688 | 1.068 | **90.01% (10.0×)** | Seq Scan on `post_hashtags` (PK starts with `post_id`) | Reverse composite index `post_hashtags(hashtag_id, post_id)` + `posts(created_at)` | Yes (EXCEPT = 0) |
| **R06** | READ | 18.573 | 1.212 | **93.47% (15.3×)** | Seq Scan on `users` due to `OR` with leading wildcard `ILIKE` | Split `OR` into `UNION ALL`; B-tree pattern index + GIN `pg_trgm` on `full_name` | Yes (same 20 rows) |
| **R07** | READ | 8.134 | 0.095 | **98.83% (85.6×)** | Seq Scan on 419,954 `likes` (PK starts with `user_id`) | Covering index `likes(post_id, created_at DESC) INCLUDE (user_id)` -> Index Only Scan | Yes (EXCEPT = 0) |
| **R08** | READ | 0.136 | 0.142 | - | Already fast index join on `follows_pkey` | Left untouched; sub-millisecond | Yes |
| **R09** | READ | 5.712 | 0.234 | **95.90% (24.4×)** | Seq Scan on `follows` (PK starts with `follower_id`) | Composite B-tree `follows(followee_id, status, created_at DESC)` | Yes (EXCEPT = 0) |
| **R10** | READ | 2.385 | 0.069 | **97.11% (34.6×)** | Seq Scan on `stories` due to `DATE(created_at)` function | SARGable half-open timestamp range + B-tree on `stories(user_id, created_at DESC)` | Yes (EXCEPT = 0) |
| **R11** | READ | 6.008 | 3.201 | **46.72% (1.9×)** | Seq Scan on `posts` and `users` | Partial index `users(user_id) WHERE account_type = 'CREATOR'` + `posts(created_at)` | Yes (EXCEPT = 0) |
| **R12** | READ | 10.935 | 0.992 | **90.93% (11.0×)** | Seq Scan on `posts` and `post_hashtags` | B-tree index on `posts(created_at)` filtering 7-day window | Yes (EXCEPT = 0) |
| **R13** | READ | 15.715 | 0.140 | **99.11% (112.3×)** | **Wrong answer bug**: `NOT IN` returned 0 rows; Seq Scan | Rewrote `NOT IN` to `NOT EXISTS`; used `comments_post_id_idx` and `comments_parent_idx` | **Fixed**: 0 -> 12 unreplied comments |
| **R14** | READ | 6.302 | 0.237 | **96.24% (26.6×)** | Seq Scan on `follows` filtering by `followee_id = 217` | Composite index `follows_followee_status_created_idx` | Yes (EXCEPT = 0) |
| **R15** | READ | 36.351 | 28.660 | **21.16% (1.3×)** | Large aggregation over entire `follows` table | Filtered creator/verified accounts via partial index `users_verified_idx` / `users_creator_idx` | Yes (EXCEPT = 0) |
| **R16** | READ | 7.728 | 0.450 | **94.18% (17.2×)** | Seq Scan on `posts` with `location_name ILIKE '%goa%'` | Date range filtering on `posts_created_at_idx` + GIN trigram `posts_location_trgm_idx` | Yes (EXCEPT = 0) |
| **R17** | READ | 10.135 | 2.866 | **71.72% (3.5×)** | `EXTRACT(YEAR FROM created_at) = 2026` prevented index usage | SARGable range predicate `[2026-01-01, 2027-01-01)` on `posts_created_at_idx` | Yes (EXCEPT = 0) |
| **R18** | READ | 5.360 | 0.824 | **84.63% (6.5×)** | `created_at::date` cast prevented index usage | Half-open range `[2026-06-01, 2026-07-01)` using `posts_created_at_idx` | Yes (EXCEPT = 0) |
| **R19** | READ | 6029.792 | 80.059 | **98.67% (75.3×)** | 2 correlated subqueries scanning 419,954 likes 247 times | Rewrote to set-based pre-aggregated `LEFT JOIN`s + `users_verified_idx` + `likes_post_created_idx` | Yes (EXCEPT = 0) |
| **R20** | READ | 14.843 | 3.332 | **77.55% (4.5×)** | Full Seq Scan on `comments` and `posts` | `posts_created_at_idx` filters June posts; `comments_post_id_idx` accelerates join | Yes (EXCEPT = 0) |
| **R21** | READ | 7.084 | 0.217 | **96.94% (32.6×)** | Seq Scan on `follows` for followers of 217 | `follows_followee_status_created_idx` + covering `likes_post_created_idx` | Yes (EXCEPT = 0) |
| **R22** | READ | 5.989 | 2.190 | **63.43% (2.7×)** | Seq Scan filtering 3,046 hidden comments and sorting | Partial index `comments(created_at DESC, comment_id) WHERE is_hidden` | Yes (stable deterministic page 61) |
| **R23** | READ | 0.039 | 0.043 | - | Already single lookup on `likes_pkey` | Left untouched; sub-millisecond | Yes |
| **R24** | READ | 1.687 | 1.529 | **9.37% (1.1×)** | 40,000 row scan and aggregation | `stories_user_created_idx` | Yes (EXCEPT = 0) |
| **W01** | WRITE | 0.450 | 1.360 | -0.91 ms | Plain heap insert (baseline failed before schema defaults) | Minor write overhead for maintaining new indexes | Yes |
| **W02** | WRITE | 0.582 | 0.735 | -0.15 ms | Insert into `likes` with conflict check | Maintained covering `likes_post_created_idx` | Yes |
| **W03** | WRITE | 0.285 | 0.674 | -0.39 ms | Update `like_count` on single post | Minor index maintenance | Yes |
| **W04** | WRITE | 80.875 | 66.629 | **17.62%** | Nightly recount of all 30k users | Benefited from faster follower joins | Yes |
| **W05** | WRITE | 7.239 | 6.473 | **10.58%** | Scanned 40,000 stories for expired items | Accelerated by `stories_expires_at_idx` | Yes |
| **W06** | WRITE | 3.352 | 0.525 | **84.34% (6.4×)** | Scanned `follows` to find pending requests for user 338 | Direct index scan via `follows_followee_status_created_idx` | Yes |
| **TOTAL** | | **6313.863** | **205.935** | **96.74% (30.7× faster)** | Workload bottlenecked by R19 (95.5% of total time) | Aggregate workload dropped from 6.31s to 0.21s | All preserved / fixed |

---

## 3. Five biggest performance wins (before vs after execution plans)

### 1. R19: Verified Account Report (6,029.79 ms -> 80.06 ms, 75.3× faster)
- **Problem**: Baseline executed two correlated subqueries inside the `SELECT` projection for all 247 verified users. One subquery joined `likes` and `posts`, executing an inner hash join scan of all 419,954 likes 247 times (`loops=247`, ~1.18 million buffer hits, 6.03 seconds).
- **Optimization**:
  1. Rewrote the correlated subqueries into set-based pre-aggregated derived tables with `LEFT JOIN`.
  2. Filtered verified users using partial index `users_verified_idx`.
  3. Pre-aggregated post counts and likes received using group-by before joining.
- **Plan Comparison**:
  - *Baseline*: `Seq Scan on likes (loops=247, rows=419954)`, `Execution Time: 6215.212 ms`
  - *Optimized*: Single `Seq Scan on likes`, hash join with pre-aggregated posts, `Execution Time: 80.059 ms`.

### 2. R07: Post Likes "Liked By" List (8.13 ms -> 0.095 ms, 85.6× faster)
- **Problem**: Baseline ran a full `Seq Scan on likes` (419,954 rows) because the primary key `(user_id, post_id)` leading column was `user_id`, rendering it useless for post lookups.
- **Optimization**: Created covering composite index `likes (post_id, created_at DESC) INCLUDE (user_id)`.
- **Plan Comparison**:
  - *Baseline*: `Seq Scan on likes (cost=0.00..8382.42 rows=14 width=16)`, `Execution Time: 8.134 ms`
  - *Optimized*: `Index Only Scan using likes_post_created_idx on likes (cost=0.42..4.64 rows=14)`, `Execution Time: 0.095 ms`. Heap access completely eliminated.

### 3. R06: Account Search Bar (18.57 ms -> 1.21 ms, 15.3× faster)
- **Problem**: `WHERE username ILIKE 'karan%' OR full_name ILIKE '%karan sharma%'`. An `OR` clause combining a prefix check with a wildcard substring forced a full sequential scan of all 30,000 users.
- **Optimization**:
  1. Enabled `pg_trgm` extension and created GIN trigram index `users_full_name_trgm_idx` on `full_name`.
  2. Created B-tree pattern index `users_username_pattern_idx` on `username varchar_pattern_ops`.
  3. Rewrote query using `UNION ALL` to let PostgreSQL use index bitmap scans for each branch independently.
- **Plan Comparison**:
  - *Baseline*: `Seq Scan on users`, `Execution Time: 18.573 ms`
  - *Optimized*: `BitmapOr` combining `Bitmap Index Scan on users_username_pattern_idx` and `Bitmap Index Scan on users_full_name_trgm_idx`, `Execution Time: 1.212 ms`.

### 4. R04: Post Comments & Reply Counts (9.18 ms -> 0.52 ms, 17.6× faster)
- **Problem**: Both top-level comments and replies executed sequential scans on 150,000 comments.
- **Optimization**:
  1. Partial B-tree `comments (post_id, created_at) WHERE parent_comment_id IS NULL AND NOT is_hidden`.
  2. Partial B-tree `comments (parent_comment_id) WHERE parent_comment_id IS NOT NULL`.
- **Plan Comparison**:
  - *Baseline*: Two `Seq Scan on comments`, `Execution Time: 9.178 ms`
  - *Optimized*: `Bitmap Index Scan on comments_post_top_level_idx` joined with `Index Scan using comments_parent_idx`, `Execution Time: 0.522 ms`.

### 5. R09: Follow Requests Screen (5.71 ms -> 0.23 ms, 24.4× faster)
- **Problem**: Query filters `followee_id = 338 AND status = 'PENDING'`. Because `follows_pkey` is `(follower_id, followee_id)`, PostgreSQL had to sequentially scan 258,588 follow relationships.
- **Optimization**: Created composite index `follows (followee_id, status, created_at DESC)`.
- **Plan Comparison**:
  - *Baseline*: `Seq Scan on follows (cost=0.00..5712.35)`, `Execution Time: 5.712 ms`
  - *Optimized*: `Index Scan using follows_followee_status_created_idx`, `Execution Time: 0.234 ms`.

---

## 4. R13: Bug explanation and row-count verification

### The Problem in Original R13:
The original query attempted to find top-level comments with no replies using `NOT IN`:
```sql
SELECT comment_id, post_id, user_id, body, created_at
FROM comments
WHERE post_id = 59689
  AND comment_id NOT IN (SELECT parent_comment_id FROM comments WHERE post_id = 59689);
```
In SQL three-valued logic, `x NOT IN (val1, val2, NULL)` evaluates to `UNKNOWN` whenever the subquery returns even a single `NULL` value. Because top-level comments have `parent_comment_id = NULL`, the subquery evaluates to `UNKNOWN` for every single candidate comment. Consequently, the filter fails for all rows, returning **0 rows**. This directly caused **P6** in the product problem description (*"comments without replies always shows nothing"*).

### The Fix:
Rewrote the query using `NOT EXISTS`, which safely checks for presence without NULL-equality pitfalls:
```sql
SELECT c.comment_id, c.post_id, c.user_id, c.body, c.created_at
FROM comments c
WHERE c.post_id = 59689
  AND NOT EXISTS (
      SELECT 1 FROM comments r
      WHERE r.post_id = 59689 AND r.parent_comment_id = c.comment_id
  );
```
- **Result Verification on `instagram_cp2`**:
  - Original Query: **0 rows returned**
  - Optimized Query: **12 rows returned** (all 12 are top-level comments on post 59689 that have zero child replies).
  - Execution Time dropped from 15.72 ms to 0.14 ms (112× faster).

---

## 5. Keyset pagination for R22 (moderation console)

R22 fetches page 61 (25 comments per page, after skipping 1,500 hidden comments).
In offset pagination:
```sql
SELECT comment_id, post_id, user_id, body, created_at
FROM comments
WHERE is_hidden
ORDER BY created_at DESC, comment_id DESC
OFFSET 1500 LIMIT 25;
```
Even with partial index `comments_hidden_created_idx`, PostgreSQL must traverse the first 1,500 index tuples before extracting the desired 25 rows.

For production at scale (Phase 5), **keyset pagination** should be used. The client passes the composite cursor `(created_at, comment_id)` of the 25th row from page 60:
```sql
SELECT comment_id, post_id, user_id, body, created_at
FROM comments
WHERE is_hidden
  AND (created_at, comment_id) < ($last_seen_created_at, $last_seen_comment_id)
ORDER BY created_at DESC, comment_id DESC
LIMIT 25;
```
With `comments_hidden_created_idx`, keyset pagination seeks directly to the cursor in $O(\log N)$ time, eliminating the 1,500-tuple traversal entirely ($O(1)$ page load regardless of page depth).

---

## 6. Write overhead analysis

| Write Query | Baseline Avg (ms) | Optimized Avg (ms) | Overhead | Assessment |
|---|---:|---:|---:|---|
| **W01 (Publish photo)** | 0.450 | 1.360 | +0.91 ms | **Acceptable**: Maintaining 4 new post indexes takes < 1 ms while read queries on posts improved by over 20 ms. |
| **W02 (Double-tap like)** | 0.582 | 0.735 | +0.15 ms | **Negligible**: Updating covering `likes_post_created_idx` adds only 0.15 ms. |
| **W03 (Sync like counter)** | 0.285 | 0.674 | +0.39 ms | **Negligible**: In-place counter update on single primary key. |
| **W04 (Nightly follower recount)** | 80.875 | 66.629 | **-14.25 ms (17.6% faster)** | **Net win**: Recount joins benefited from `follows_followee_status_created_idx`. |
| **W05 (Delete expired stories)** | 7.239 | 6.473 | **-0.77 ms (10.6% faster)** | **Net win**: Faster identification of expired stories via `stories_expires_at_idx`. |
| **W06 (Accept follow requests)** | 3.352 | 0.525 | **-2.83 ms (6.4× faster)** | **Net win**: Instant lookup of pending follow requests via composite index. |

Overall write throughput remains healthy: single-row transactions complete in ~1 ms, while bulk background operations (W04, W05, W06) are substantially faster.

---

## 7. Index storage breakdown

Total storage required by the 17 custom indexes created for CP3:

| Table Name | Index Name | Index Size | Underlying Table Size | Relative Ratio |
|---|---|---:|---:|---:|
| `comments` | `comments_hidden_created_idx` | 112 kB | 12 MB | 0.9% (partial) |
| `comments` | `comments_parent_idx` | 552 kB | 12 MB | 4.6% (partial) |
| `comments` | `comments_post_id_idx` | 2,232 kB | 12 MB | 18.6% |
| `comments` | `comments_post_top_level_idx` | 3,816 kB | 12 MB | 31.8% (partial) |
| `follows` | `follows_followee_status_created_idx` | 12 MB | 17 MB | 70.5% |
| `likes` | `likes_post_created_idx` | 16 MB | 21 MB | 76.1% (covering) |
| `post_hashtags` | `post_hashtags_hashtag_post_idx` | 4,640 kB | 6,912 kB | 67.1% |
| `posts` | `posts_created_at_idx` | 1,328 kB | 6,912 kB | 19.2% |
| `posts` | `posts_location_trgm_idx` | 408 kB | 6,912 kB | 5.9% (trigram) |
| `posts` | `posts_user_active_created_idx` | 1,824 kB | 6,912 kB | 26.4% (partial) |
| `posts` | `posts_user_created_idx` | 1,856 kB | 6,912 kB | 26.8% |
| `stories` | `stories_expires_at_idx` | 896 kB | 3,136 kB | 28.5% |
| `stories` | `stories_user_created_idx` | 1,248 kB | 3,136 kB | 39.7% |
| `users` | `users_creator_idx` | 88 kB | 4,488 kB | 1.9% (partial) |
| `users` | `users_full_name_trgm_idx` | 1,712 kB | 4,488 kB | 38.1% (trigram) |
| `users` | `users_username_pattern_idx` | 1,120 kB | 4,488 kB | 24.9% |
| `users` | `users_verified_idx` | 16 kB | 4,488 kB | 0.3% (partial) |
| **Total** | **All 17 new indexes** | **~48.0 MB** | **~71.0 MB** | **67.6% of base data** |

---

## 8. Queries with minimal change (by design)

1. **R03, R08, R23**: These queries already execute single-digit Index (Only) Scans on existing unique primary keys (`users_username_key`, `follows_pkey`, `likes_pkey`) and completed in < 0.2 ms during baseline. No indexing or rewrites were necessary.
2. **R15 and W04**: These queries perform cross-table aggregations over the entire 258k rows of `follows` to identify out-of-sync counters. Because almost all follow rows must be evaluated, sequential/hash scans are structurally appropriate.
3. **R12, R18, R20**: Although date filtering dropped their scan times significantly (from ~15 ms to ~1–3 ms), they still aggregate multi-thousand row candidate sets, putting a natural floor on execution time.
