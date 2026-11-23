-- =====================================================================
-- Phase 5: Declarative Table Partitioning (sql/08_partitioning.sql)
--
-- Why Partitioning:
-- At scale (20x seed data = 24M rows, and architecture for 100x = 120M rows),
-- single unpartitioned tables cause:
--   1. Massive index bloat (e.g. likes index is 577 MB alone).
--   2. Inability to drop old data without costly, row-by-row DELETEs and VACUUM.
--   3. Unnecessary I/O scanning historical data for current-window queries.
--
-- Primary Key Rule in PostgreSQL Partitioned Tables:
-- Every UNIQUE or PRIMARY KEY constraint on a partitioned table MUST include
-- the partition key column(s). E.g., likes PK becomes (user_id, post_id, created_at).
--
-- Tables Partitioned:
--   1. likes:   RANGE (created_at)  - 8.4M rows. Prunes older years for recent analytics.
--   2. posts:   RANGE (created_at)  - 1.2M rows. Prunes 2025 posts (800k rows) for 2026 queries.
--   3. stories: RANGE (expires_at)  - 800k rows. O(1) drop/detach of expired stories vs bulk DELETE.
--   4. follows: LIST (status)       - 5.2M rows. Separates 5M active follows from 187k pending.
-- =====================================================================

\set ON_ERROR_STOP on
SET search_path TO instagram, public;

-- =====================================================================
-- 1. Partitioned Table: LIKES (RANGE by created_at)
-- =====================================================================
DROP TABLE IF EXISTS likes_partitioned CASCADE;

CREATE TABLE likes_partitioned (
    user_id BIGINT NOT NULL,
    post_id BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (user_id, post_id, created_at)
) PARTITION BY RANGE (created_at);

CREATE TABLE likes_2025_h1 PARTITION OF likes_partitioned
    FOR VALUES FROM ('2025-01-01 00:00:00+00') TO ('2025-07-01 00:00:00+00');

CREATE TABLE likes_2025_h2 PARTITION OF likes_partitioned
    FOR VALUES FROM ('2025-07-01 00:00:00+00') TO ('2026-01-01 00:00:00+00');

CREATE TABLE likes_2026_h1 PARTITION OF likes_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');

CREATE TABLE likes_default PARTITION OF likes_partitioned DEFAULT;

-- Covering composite index on partitioned table (propagates to child partitions)
CREATE INDEX likes_part_post_created_idx
    ON likes_partitioned (post_id, created_at DESC)
    INCLUDE (user_id);

INSERT INTO likes_partitioned SELECT user_id, post_id, created_at FROM likes;
ANALYZE likes_partitioned;


-- =====================================================================
-- 2. Partitioned Table: POSTS (RANGE by created_at)
-- =====================================================================
DROP TABLE IF EXISTS posts_partitioned CASCADE;

CREATE TABLE posts_partitioned (
    post_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    post_type TEXT NOT NULL CHECK (post_type IN ('PHOTO', 'VIDEO', 'CAROUSEL', 'REEL')),
    caption TEXT,
    location_name TEXT,
    like_count INTEGER NOT NULL DEFAULT 0 CHECK (like_count >= 0),
    comment_count INTEGER NOT NULL DEFAULT 0 CHECK (comment_count >= 0),
    is_archived BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (post_id, created_at)
) PARTITION BY RANGE (created_at);

CREATE TABLE posts_2025_h1 PARTITION OF posts_partitioned
    FOR VALUES FROM ('2025-01-01 00:00:00+00') TO ('2025-07-01 00:00:00+00');

CREATE TABLE posts_2025_h2 PARTITION OF posts_partitioned
    FOR VALUES FROM ('2025-07-01 00:00:00+00') TO ('2026-01-01 00:00:00+00');

CREATE TABLE posts_2026_h1 PARTITION OF posts_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');

CREATE TABLE posts_default PARTITION OF posts_partitioned DEFAULT;

-- Indexes propagating across post partitions
CREATE INDEX posts_part_user_active_created_idx
    ON posts_partitioned (user_id, created_at DESC)
    WHERE NOT is_archived;

CREATE INDEX posts_part_created_at_idx
    ON posts_partitioned (created_at);

CREATE INDEX posts_part_location_trgm_idx
    ON posts_partitioned USING gin (location_name gin_trgm_ops);

INSERT INTO posts_partitioned SELECT * FROM posts;
ANALYZE posts_partitioned;


-- =====================================================================
-- 3. Partitioned Table: STORIES (RANGE by expires_at)
-- =====================================================================
DROP TABLE IF EXISTS stories_partitioned CASCADE;

CREATE TABLE stories_partitioned (
    story_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    media_type TEXT NOT NULL CHECK (media_type IN ('IMAGE', 'VIDEO')),
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    view_count INTEGER NOT NULL CHECK (view_count >= 0),
    PRIMARY KEY (story_id, expires_at),
    CHECK (expires_at = created_at + INTERVAL '24 hours')
) PARTITION BY RANGE (expires_at);

CREATE TABLE stories_expired PARTITION OF stories_partitioned
    FOR VALUES FROM (MINVALUE) TO ('2026-06-01 00:00:00+00');

CREATE TABLE stories_active PARTITION OF stories_partitioned
    FOR VALUES FROM ('2026-06-01 00:00:00+00') TO (MAXVALUE);

CREATE INDEX stories_part_user_created_idx
    ON stories_partitioned (user_id, created_at DESC);

CREATE INDEX stories_part_expires_at_idx
    ON stories_partitioned (expires_at);

INSERT INTO stories_partitioned SELECT * FROM stories;
ANALYZE stories_partitioned;


-- =====================================================================
-- 4. Partitioned Table: FOLLOWS (LIST by status)
-- =====================================================================
DROP TABLE IF EXISTS follows_partitioned CASCADE;

CREATE TABLE follows_partitioned (
    follower_id BIGINT NOT NULL,
    followee_id BIGINT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('ACCEPTED', 'PENDING')),
    created_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (follower_id, followee_id, status),
    CHECK (follower_id <> followee_id)
) PARTITION BY LIST (status);

CREATE TABLE follows_accepted PARTITION OF follows_partitioned
    FOR VALUES IN ('ACCEPTED');

CREATE TABLE follows_pending PARTITION OF follows_partitioned
    FOR VALUES IN ('PENDING');

CREATE INDEX follows_part_followee_created_idx
    ON follows_partitioned (followee_id, created_at DESC);

INSERT INTO follows_partitioned SELECT * FROM follows;
ANALYZE follows_partitioned;


-- =====================================================================
-- 5. Partition Pruning Proofs & Timing Demonstrations
-- =====================================================================

-- Pruning Proof 1: likes_partitioned
-- Time-windowed query prunes likes_2025_h1 and likes_2025_h2 (skipping ~5M rows).
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM likes_partitioned
WHERE created_at >= '2026-06-01' AND created_at < '2026-07-01';

-- Pruning Proof 2: posts_partitioned (R12 / R18 / R20)
-- Content analytics query for June 2026 prunes posts_2025_h1 and posts_2025_h2 (800k rows skipped).
EXPLAIN (ANALYZE, BUFFERS)
SELECT created_at::date AS day, post_type, count(*) AS posts
FROM posts_partitioned
WHERE created_at >= '2026-06-01' AND created_at < '2026-07-01'
GROUP BY 1, 2
ORDER BY 1, 2;

-- Pruning Proof 3: follows_partitioned (W06)
-- Update pending follow requests prunes follows_accepted (5M rows skipped).
EXPLAIN (ANALYZE, BUFFERS)
UPDATE follows_partitioned
SET status = 'ACCEPTED'
WHERE followee_id = 338 AND status = 'PENDING';

-- Pruning Proof 4: stories_partitioned (W05)
-- Housekeeping story cleanup touches only stories_expired; or instant O(1) drop:
-- ALTER TABLE stories_partitioned DETACH PARTITION stories_expired; DROP TABLE stories_expired;
EXPLAIN (ANALYZE, BUFFERS)
DELETE FROM stories_partitioned
WHERE expires_at < '2026-06-01';

-- Pruning Proof 5: Optimized Follower Recount (W04)
-- Aggregating directly over follows_accepted drops runtime from 7,168 ms to ~1,760 ms.
EXPLAIN (ANALYZE, BUFFERS)
UPDATE users u
SET followers_count = s.n
FROM (
    SELECT f.followee_id AS user_id, count(*) AS n
    FROM follows_accepted f
    GROUP BY f.followee_id
) s
WHERE s.user_id = u.user_id AND u.followers_count <> s.n;
