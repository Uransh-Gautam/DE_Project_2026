# Baseline timings

We ran the 30 given queries on the seed data before adding any extra indexes. The only indexes on the database are the ones PostgreSQL creates by itself for primary keys and unique columns (`users_pkey`, `users_username_key`, `users_email_key`, `follows_pkey`, `posts_pkey`, `likes_pkey`, `comments_pkey`, `comments_comment_id_post_id_key`, and the other PK/unique indexes).

## Setup

- Laptop: MacBook Pro M4 Pro (the one listed in `team.json`)
- PostgreSQL 18.7, Postgres.app. Course allows 15 or newer.
- Database: `instagram_cp2`, loaded from `seed_data/` with `database/01_schema.sql` and `database/02_load_data.sql`, then `ANALYZE`
- Command: `./benchmarks/run_benchmark.sh instagram_cp2 baseline`
- Each number is the `Execution Time` from `EXPLAIN (ANALYZE, BUFFERS)`. Planning time is not included.
- Writes ran inside `BEGIN` … `ROLLBACK`, so the tables were the same for every run.
- Raw plans are in `benchmarks/results/baseline/`. `summary.csv` in that folder is what the script wrote.

`W01` inserts a post and does not set `like_count`, `comment_count`, or `is_archived`. Those columns were `NOT NULL` with no default, so the insert failed. We added `DEFAULT 0`, `DEFAULT 0`, and `DEFAULT false` in `database/01_schema.sql`. The CSV load still writes the real counter values, so this only matters for a new insert.

Most pages were already in memory (`shared hit`). R01's first run was a bit slower than the third (6.567 ms, then 4.656 ms). The later runs are the cached ones.

## Timing table

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Home feed: the latest 30 posts from accounts user 1042 follows | READ | 6.567 | 5.487 | 4.656 | 5.570 |
| R02: Profile grid: user 217's latest 12 posts | READ | 2.700 | 2.720 | 2.711 | 2.710 |
| R03: Open a profile by username | READ | 0.030 | 0.023 | 0.024 | 0.026 |
| R04: Post page: top-level comments on post 59689 with the number of replies each has | READ | 9.236 | 9.121 | 9.176 | 9.178 |
| R05: Explore: top posts tagged #travel in June 2026 | READ | 10.666 | 10.706 | 10.691 | 10.688 |
| R06: Search bar: accounts whose username starts with "karan" or whose name contains "karan sharma" | READ | 18.095 | 19.330 | 18.294 | 18.573 |
| R07: "Liked by": people who liked post 59689, showing whether user 1042 follows them | READ | 8.512 | 8.040 | 7.849 | 8.134 |
| R08: "Suggested for you": friends-of-friends of user 1042 that 1042 doesn't follow yet | READ | 0.146 | 0.134 | 0.127 | 0.136 |
| R09: Follow requests screen: pending requests for private account 338 | READ | 5.772 | 5.654 | 5.709 | 5.712 |
| R10: Story highlights: stories posted in June 2026 by accounts user 1042 follows | READ | 2.398 | 2.406 | 2.350 | 2.385 |
| R11: Creator insights: engagement rate (likes + comments per follower) of creators' 2026 posts, top 20 | READ | 6.015 | 5.996 | 6.012 | 6.008 |
| R12: Trending: hashtags used most in the last 7 days of June 2026 | READ | 11.247 | 10.757 | 10.800 | 10.935 |
| R13: Creator tools: comments on post 59689 that nobody has replied to yet | READ | 15.582 | 15.487 | 16.075 | 15.715 |
| R14: "Not following back": accounts that follow user 217 whom 217 doesn't follow | READ | 6.387 | 6.585 | 5.934 | 6.302 |
| R15: Data quality: verified or creator accounts whose stored follower count is wrong | READ | 33.551 | 33.772 | 41.731 | 36.351 |
| R16: Places: posts tagged with a location containing "goa" in June 2026 | READ | 7.694 | 7.705 | 7.785 | 7.728 |
| R17: Reels team: creators' reels longer than 60 seconds posted in 2026 | READ | 10.298 | 9.848 | 10.259 | 10.135 |
| R18: Content analytics: new posts per day and type in June 2026 | READ | 5.221 | 5.748 | 5.112 | 5.360 |
| R19: Verified-account report: last post time and total likes received by every verified account | READ | 6215.212 | 5989.558 | 5884.606 | 6029.792 |
| R20: Content analytics: 10 most-commented posts of June 2026 (counting real comments) | READ | 13.773 | 15.397 | 15.358 | 14.843 |
| R21: Creator tools: "ghost followers" of user 217 (followers who never liked any of 217's posts) | READ | 7.109 | 7.221 | 6.922 | 7.084 |
| R22: Moderation console: hidden comments, newest first, page 61 (25 per page) | READ | 6.008 | 6.086 | 5.873 | 5.989 |
| R23: Like button state: has user 1042 liked post 59689? | READ | 0.054 | 0.032 | 0.030 | 0.039 |
| R24: Story insights: total story views per account in the last 30 days, top 20 | READ | 1.777 | 1.643 | 1.641 | 1.687 |
| W01: Publish a new photo post | WRITE | 0.619 | 0.362 | 0.370 | 0.450 |
| W02: Double-tap: user 1042 likes post 59689 | WRITE | 0.486 | 0.462 | 0.798 | 0.582 |
| W03: Keep the counter in sync after the like | WRITE | 0.536 | 0.186 | 0.133 | 0.285 |
| W04: Nightly job: recompute every user's follower count | WRITE | 75.123 | 80.965 | 86.538 | 80.875 |
| W05: Housekeeping: delete stories that expired before June 2026 | WRITE | 6.731 | 7.852 | 7.133 | 7.239 |
| W06: Private account 338 accepts all pending follow requests | WRITE | 3.668 | 3.258 | 3.131 | 3.352 |
| **Total (sum of all 30)** | | 6491.213 | 6272.541 | 6177.828 | 6313.863 |

R19 alone is 6029.792 ms, about 95.5% of the total. The other 29 queries add up to about 284 ms.

## Scan type and why it is slow or fast

- **R01** — Seq Scan on `posts`, Index Scan on `follows_pkey`. Finding who user 1042 follows is cheap (14 accepted follows, 7 buffer hits). Postgres then reads all 60,000 posts to keep the ones from those 14 people, then sorts. Fast enough on this data, but the post scan is the whole cost.
- **R02** — Seq Scan on `posts`. There is no index on `user_id`, so the profile grid reads every post to find user 217, then keeps the latest 12.
- **R03** — Index Scan on `users_username_key`. Username is unique, so this is one index lookup (3 buffer hits, 0.026 ms). This is what a profile open should look like.
- **R04** — Seq Scan on `comments` (twice, once for the outer comments and once for the reply join). Post 59689 is one post, but nothing indexes `comments.post_id` except the unique pair `(comment_id, post_id)`, and `comment_id` is the leading column, so Postgres cannot jump to that post.
- **R05** — Seq Scan on `hashtags` and `post_hashtags`, then Index Scan on `posts_pkey`. The tag lookup itself is tiny (50 hashtags). The slow part is walking every `post_hashtags` row for `#travel` and then sorting those posts by `like_count`.
- **R06** — Seq Scan on `users`. `full_name ILIKE '%karan sharma%'` has a leading wildcard, and it is OR-ed with the username check, so the username unique index is not used. It reads all 30,000 users and throws away 28,800.
- **R07** — Seq Scan on `likes`, then Index Scan on `users_pkey` and `follows_pkey`. Likes are keyed by `(user_id, post_id)`, so "everyone who liked this post" cannot use the primary key. It scans 419,954 likes to find one post.
- **R08** — Index Scan and Index Only Scan on `follows_pkey`. User 1042 follows very few people, so the friends-of-friends join stays on the index and finishes in 0.136 ms. This will not stay this fast for a user who follows thousands of accounts.
- **R09** — Seq Scan on `follows`, Index Scan on `users_pkey` for the names. The filter is `followee_id = 338`, but the primary key starts with `follower_id`, so pending requests for one account still scan all 258,588 follow rows.
- **R10** — Seq Scan on `stories`, Index Scan on `follows_pkey`. `DATE(created_at)` wraps the column, so a plain index on `created_at` would not help this predicate anyway. The follow check itself is an index lookup.
- **R11** — Seq Scan on `users` and `posts`. It has to group every 2026 post of every creator. 6 ms is fine for a report, but it reads both tables fully.
- **R12** — Seq Scan on `post_hashtags`, `posts`, and `hashtags`. Same shape as R05: the date filter is on `posts`, so it joins the hashtag mapping and then aggregates. Only 50 tags, so the sort at the end is nothing.
- **R13** — Index Scan on `comments_comment_id_post_id_key` for post 59689, plus a Seq Scan of all 150,000 comments for the `NOT IN` subquery. The index finds 13 comments on that post and then removes all 13, so the query returns **0 rows**. Top-level comments have `parent_comment_id` NULL, and `NOT IN` becomes unknown if the subquery contains a NULL. That matches problem P6 ("comments without replies always shows nothing"). We did not change the query in this phase.
- **R14** — Seq Scan on `follows` for `followee_id = 217`, with an Index Only Scan on `follows_pkey` for the "do they follow back" check. Same key-order problem as R09: looking up by the person being followed does not match the primary key order.
- **R15** — Seq Scan on `users` and `follows`. It counts accepted followers for every verified or creator account and compares that with `followers_count`. The plan hashes the whole follows table. Third run jumped to 41.7 ms; the first two were about 33.6 ms.
- **R16** — Seq Scan on `posts`. `location_name ILIKE '%goa%'` cannot use a normal B-tree, and a lot of locations are NULL. It reads the whole posts table.
- **R17** — Seq Scan on `posts`, Index Scan on `users_pkey` and `post_media_pkey`. `EXTRACT(YEAR FROM created_at) = 2026` is not a range on the raw column, so the year filter does not limit the post scan. Media and user lookups are indexed.
- **R18** — Seq Scan on `posts`. `created_at::date` is computed for every row, then grouped. June is only part of the table, but the cast stops a range index from being used even if we had one.
- **R19** — Seq Scan on `users`, and for each verified user a Seq Scan on `posts` and a Seq Scan on `likes`. This is the slow one. There are 294 verified accounts. For each of them the plan runs two correlated subqueries. The likes subquery hash-joins by scanning all 419,954 likes, and that scan ran 247 times (`loops=247` in the plan). Run 1 also reported about 1.18 million shared buffer hits. Average 6.03 seconds. Nothing else in the workload is close.
- **R20** — Seq Scan on `comments` and `posts`, then aggregate. It counts comments on every post from June onward. No index on `posts.created_at` or `comments.post_id`, so both tables are read fully. 14.8 ms average.
- **R21** — Seq Scan on `follows` for user 217's followers, then Index Only Scan on `likes_pkey` and Index Scan on `posts_pkey` inside the `NOT EXISTS`. The follower list is a scan (same as R14). The "did this person like any of 217's posts" check can use the likes primary key because it starts from `user_id`.
- **R22** — Seq Scan on `comments`, filter `is_hidden` (3,046 hidden, 146,954 thrown away), sort all of them, then `OFFSET 1500`. The offset still makes Postgres sort and walk the first 1,500 hidden comments before returning 25. On this table that is only 6 ms. It will get worse when comments grow.
- **R23** — Index Only Scan on `likes_pkey`. The question is exactly the primary key `(user_id, post_id)`, so it is one lookup, 0.039 ms.
- **R24** — Seq Scan on `stories`. It filters `created_at >= '2026-06-01'`, groups by user, and sorts. 40,000 stories is small, so 1.7 ms is expected even without an index.
- **W01** — no scan. Single insert of one post. 0.450 ms. First run was slower (0.619 ms), the next two were about 0.37 ms.
- **W02** — no scan shown. Insert into `likes` with `ON CONFLICT (user_id, post_id) DO NOTHING`, so it checks the primary key and inserts one row. 0.582 ms.
- **W03** — Index Scan on `posts_pkey`. Update of one post by primary key. 0.285 ms.
- **W04** — Seq Scan on `users` and `follows`. This is the nightly recount. It builds a follower count for all 30,000 users and updates the 1,200 rows where `followers_count` does not match. That 1,200 matches what we already saw in the schema checks. Average 80.9 ms, and it got a little slower each run (75.1, 81.0, 86.5) because the update dirties pages even though the script rolls back.
- **W05** — Seq Scan on `stories`. Deletes every story with `expires_at < '2026-06-01'`. There is no index on `expires_at`, so it reads all 40,000 stories. The delete is rolled back. 7.2 ms.
- **W06** — Index Scan on `follows_pkey`. Updates pending rows for account 338. Still has to find them by `followee_id`, which is the second column of the key. 3.4 ms on this data.

## What we would look at next

We are not changing queries in this checkpoint. From these plans, the obvious later work is:

1. R19. Stop running a likes scan once per verified user. An index on `posts(user_id)` and `likes(post_id)`, or rewriting the two subqueries as joins, should take this off the multi-second range.
2. Indexes for the columns the feed and post page actually filter on: `posts(user_id, created_at)`, `likes(post_id)`, `comments(post_id)`, `follows(followee_id, status)`.
3. R13's `NOT IN` is wrong when `parent_comment_id` is NULL, not just slow. Fixing the result comes in the optimization phase.
4. R06 and R16 need something other than a plain B-tree (`ILIKE` with a leading `%`).
5. R10, R17, and R18 put a function on `created_at` (`DATE`, `EXTRACT`, `::date`), so a normal index on that column would not be used until the predicate is written as a range.
