-- Phase 4 indexes. Each one names the queries it serves and why this type
-- and column order. Primary keys and unique indexes from 01_schema.sql stay
-- as they are. No server settings are changed.
--
-- Equality columns come first, then the range or sort column, so a composite
-- index can answer the filter and the ORDER BY together.
-- Partial indexes stay small by keeping only the rows a query actually reads.
-- INCLUDE columns make a covering index (Index Only Scan) so the heap is skipped.
-- pg_trgm GIN indexes are only for ILIKE '%...%' (leading wildcard).

CREATE EXTENSION IF NOT EXISTS pg_trgm;

SET search_path TO instagram, public;

-- R01 home feed, R02 profile grid.
-- Both filter one user (or a short list of followees), skip archived posts,
-- and take the newest rows. user_id is the equality; created_at DESC is the
-- sort, so LIMIT can stop after 12 or 30 index entries. Partial: archived
-- posts are not in this index.
CREATE INDEX IF NOT EXISTS posts_user_active_created_idx
    ON posts (user_id, created_at DESC)
    WHERE NOT is_archived;

-- R11 creator engagement, R19 last post time.
-- These count every post of a user, including archived ones, so the partial
-- index above cannot serve them. Same column order: equality on user_id,
-- then created_at so max(created_at) is the first index entry.
CREATE INDEX IF NOT EXISTS posts_user_created_idx
    ON posts (user_id, created_at DESC);

-- R05, R12, R16, R17, R18, R20.
-- After the date predicates are written as ranges (see 06_optimized_queries.sql),
-- a plain btree on created_at can skip posts outside the window. Leading with
-- created_at matches "posts in this range", which is the selective side of
-- those reports.
CREATE INDEX IF NOT EXISTS posts_created_at_idx
    ON posts (created_at);

-- R16 places search. location_name ILIKE '%goa%' has a leading wildcard, so a
-- btree cannot be used. gin_trgm_ops indexes the trigrams of the text.
CREATE INDEX IF NOT EXISTS posts_location_trgm_idx
    ON posts USING gin (location_name gin_trgm_ops);

-- R07 "liked by", and the likes half of R19.
-- likes_pkey is (user_id, post_id), so "everyone who liked this post" cannot
-- use it. post_id is the equality; created_at DESC matches R07's sort.
-- INCLUDE (user_id) covers R07's selected user id (Index Only Scan).
CREATE INDEX IF NOT EXISTS likes_post_created_idx
    ON likes (post_id, created_at DESC)
    INCLUDE (user_id);

-- R04 post page: top-level visible comments on one post, ordered by time.
-- Equality on post_id, then created_at for the ORDER BY. Partial so replies
-- and hidden comments are not in the index.
CREATE INDEX IF NOT EXISTS comments_post_top_level_idx
    ON comments (post_id, created_at)
    WHERE parent_comment_id IS NULL AND NOT is_hidden;

-- R04 reply counts, R13 "nobody replied".
-- Lookups are parent_comment_id = some comment. NULLs (top-level comments)
-- are excluded so the index only holds real replies.
CREATE INDEX IF NOT EXISTS comments_parent_idx
    ON comments (parent_comment_id)
    WHERE parent_comment_id IS NOT NULL;

-- R13 comments on one post, R20 comments joined from posts.
-- comments_comment_id_post_id_key leads with comment_id, so it cannot jump
-- to a post. This index leads with post_id.
CREATE INDEX IF NOT EXISTS comments_post_id_idx
    ON comments (post_id);

-- R22 moderation console: hidden comments, newest first.
-- Only about 3,046 of 150,000 comments are hidden. A partial index on that
-- predicate, ordered by created_at DESC, comment_id, lets page 61 walk the
-- index instead of sorting every hidden row from a sequential scan.
CREATE INDEX IF NOT EXISTS comments_hidden_created_idx
    ON comments (created_at DESC, comment_id)
    WHERE is_hidden;

-- R05 explore posts for one hashtag.
-- post_hashtags PK is (post_id, hashtag_id), so "all posts with #travel"
-- cannot use it. hashtag_id first, then post_id for the join back to posts.
CREATE INDEX IF NOT EXISTS post_hashtags_hashtag_post_idx
    ON post_hashtags (hashtag_id, post_id);

-- R09 pending requests, R14 and R21 followers of one user, R15 and W04
-- follower recounts, W06 accept pending.
-- follows_pkey is (follower_id, followee_id). These queries look up by the
-- person being followed. followee_id equality, then status equality, then
-- created_at DESC so R09 can return newest requests without a sort.
CREATE INDEX IF NOT EXISTS follows_followee_status_created_idx
    ON follows (followee_id, status, created_at DESC);

-- R10 story highlights (one followed user's stories, newest first),
-- R24 story insights grouped by user inside a date range.
-- user_id equality, created_at for the range and the sort.
CREATE INDEX IF NOT EXISTS stories_user_created_idx
    ON stories (user_id, created_at DESC);

-- W05 delete stories that expired before a timestamp.
-- expires_at is not in the primary key, so the delete was a sequential scan.
CREATE INDEX IF NOT EXISTS stories_expires_at_idx
    ON stories (expires_at);

-- R19 verified-account report.
-- Partial index of only the verified user ids (294 rows). The rewrite joins
-- from this small set instead of scanning all 30,000 users.
CREATE INDEX IF NOT EXISTS users_verified_idx
    ON users (user_id)
    WHERE is_verified;

-- R11 and R17: only creator accounts.
CREATE INDEX IF NOT EXISTS users_creator_idx
    ON users (user_id)
    WHERE account_type = 'CREATOR';

-- R06 search bar, username prefix.
-- Usernames are stored lowercase (CHECK on users.username), so ILIKE 'karan%'
-- is the same set as LIKE 'karan%'. The default unique index uses the
-- database collation and will not serve a prefix LIKE unless the opclass is
-- varchar_pattern_ops.
CREATE INDEX IF NOT EXISTS users_username_pattern_idx
    ON users (username varchar_pattern_ops);

-- R06 search bar, full name contains "karan sharma".
-- Leading-wildcard ILIKE needs trigrams, same idea as location_name.
CREATE INDEX IF NOT EXISTS users_full_name_trgm_idx
    ON users USING gin (full_name gin_trgm_ops);

ANALYZE users;
ANALYZE follows;
ANALYZE posts;
ANALYZE post_hashtags;
ANALYZE likes;
ANALYZE comments;
ANALYZE stories;