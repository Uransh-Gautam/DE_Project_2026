-- =====================================================================
-- Phase 4 optimized workload.
-- Copied from queries/workload_30.sql. Markers (-- @R01, -- @W01, -- @END)
-- are unchanged so benchmarks/run_benchmark.sh can split the file.
-- Only R06, R10, R13, R17, R18, R19, and R22 are rewritten.
-- The other queries are the originals; they get faster from sql/05_indexes.sql.
-- =====================================================================
SET search_path TO instagram;
BEGIN;

-- @R01
-- Home feed: the latest 30 posts from accounts user 1042 follows
SELECT p.post_id, p.user_id, p.post_type, p.caption, p.like_count, p.created_at
FROM follows f
JOIN posts p ON p.user_id = f.followee_id
WHERE f.follower_id = 1042
  AND f.status = 'ACCEPTED'
  AND NOT p.is_archived
ORDER BY p.created_at DESC
LIMIT 30;

-- @R02
-- Profile grid: user 217's latest 12 posts
SELECT post_id, post_type, like_count, comment_count, created_at
FROM posts
WHERE user_id = 217 AND NOT is_archived
ORDER BY created_at DESC
LIMIT 12;

-- @R03
-- Open a profile by username
SELECT user_id, full_name, bio, is_private, is_verified, followers_count, following_count
FROM users
WHERE username = 'karan_singh217';

-- @R04
-- Post page: top-level comments on post 59689 with the number of replies each has
SELECT c.comment_id, c.user_id, c.body, c.created_at, count(r.comment_id) AS replies
FROM comments c
LEFT JOIN comments r ON r.parent_comment_id = c.comment_id
WHERE c.post_id = 59689
  AND c.parent_comment_id IS NULL
  AND NOT c.is_hidden
GROUP BY c.comment_id, c.user_id, c.body, c.created_at
ORDER BY c.created_at;

-- @R05
-- Explore: top posts tagged #travel in June 2026
SELECT p.post_id, p.user_id, p.like_count
FROM hashtags h
JOIN post_hashtags ph ON ph.hashtag_id = h.hashtag_id
JOIN posts p          ON p.post_id = ph.post_id
WHERE h.tag = 'travel'
  AND p.created_at >= '2026-06-01'
ORDER BY p.like_count DESC
LIMIT 30;

-- @R06
-- Search bar: accounts whose username starts with "karan" or whose name contains "karan sharma"
-- Split the OR so each arm can use its own index:
--   username LIKE 'karan%'           -> users_username_pattern_idx (varchar_pattern_ops)
--   full_name ILIKE '%karan sharma%' -> users_full_name_trgm_idx
-- Usernames are lowercase by CHECK, so LIKE and ILIKE match the same prefix rows.
-- The second arm excludes the prefix matches so UNION ALL does not duplicate them.
SELECT user_id, username, full_name, is_verified, followers_count
FROM (
    SELECT user_id, username, full_name, is_verified, followers_count
    FROM users
    WHERE username LIKE 'karan%'
    UNION ALL
    SELECT user_id, username, full_name, is_verified, followers_count
    FROM users
    WHERE full_name ILIKE '%karan sharma%'
      AND username NOT LIKE 'karan%'
) matches
ORDER BY is_verified DESC, followers_count DESC
LIMIT 20;

-- @R07
-- "Liked by": people who liked post 59689, showing whether user 1042 follows them
SELECT l.user_id, u.username, (f.follower_id IS NOT NULL) AS you_follow, l.created_at
FROM likes l
JOIN users u ON u.user_id = l.user_id
LEFT JOIN follows f ON f.follower_id = 1042 AND f.followee_id = l.user_id AND f.status = 'ACCEPTED'
WHERE l.post_id = 59689
ORDER BY you_follow DESC, l.created_at DESC;

-- @R08
-- "Suggested for you": friends-of-friends of user 1042 that 1042 doesn't follow yet
SELECT f2.followee_id AS suggested_user, count(*) AS mutual_connections
FROM follows f1
JOIN follows f2 ON f2.follower_id = f1.followee_id AND f2.status = 'ACCEPTED'
WHERE f1.follower_id = 1042
  AND f1.status = 'ACCEPTED'
  AND f2.followee_id <> 1042
  AND NOT EXISTS (SELECT 1 FROM follows x WHERE x.follower_id = 1042 AND x.followee_id = f2.followee_id)
GROUP BY f2.followee_id
ORDER BY mutual_connections DESC, suggested_user
LIMIT 20;

-- @R09
-- Follow requests screen: pending requests for private account 338
SELECT f.follower_id, u.username, f.created_at
FROM follows f
JOIN users u ON u.user_id = f.follower_id
WHERE f.followee_id = 338 AND f.status = 'PENDING'
ORDER BY f.created_at DESC;

-- @R10
-- Story highlights: stories posted in June 2026 by accounts user 1042 follows
-- DATE(created_at) hides the column from a range index. The half-open range
-- is the same set of instants as DATE(created_at) between 1 Jun and 30 Jun
-- in the session time zone.
SELECT s.story_id, s.user_id, s.media_type, s.created_at, s.view_count
FROM stories s
JOIN follows f ON f.followee_id = s.user_id AND f.follower_id = 1042 AND f.status = 'ACCEPTED'
WHERE s.created_at >= '2026-06-01'
  AND s.created_at < '2026-07-01'
ORDER BY s.created_at DESC;

-- @R11
-- Creator insights: engagement rate (likes + comments per follower) of creators' 2026 posts, top 20
SELECT u.user_id, u.username, u.followers_count,
       round(sum(p.like_count + p.comment_count)::numeric / NULLIF(u.followers_count, 0), 3) AS engagement_per_follower
FROM users u
JOIN posts p ON p.user_id = u.user_id
WHERE u.account_type = 'CREATOR'
  AND p.created_at >= '2026-01-01'
GROUP BY u.user_id, u.username, u.followers_count
HAVING u.followers_count >= 20
ORDER BY engagement_per_follower DESC
LIMIT 20;

-- @R12
-- Trending: hashtags used most in the last 7 days of June 2026
SELECT h.tag, count(*) AS posts
FROM post_hashtags ph
JOIN hashtags h ON h.hashtag_id = ph.hashtag_id
JOIN posts p    ON p.post_id = ph.post_id
WHERE p.created_at >= '2026-06-24'
GROUP BY h.tag
ORDER BY posts DESC
LIMIT 10;

-- @R13
-- Creator tools: comments on post 59689 that nobody has replied to yet
-- The original NOT IN (SELECT parent_comment_id ...) returns zero rows.
-- Top-level comments have parent_comment_id NULL, and NOT IN is unknown
-- when the subquery contains a NULL. NOT EXISTS treats "no matching reply"
-- correctly and does not compare against NULL parent ids.
SELECT c.comment_id, c.user_id, c.body
FROM comments c
WHERE c.post_id = 59689
  AND NOT EXISTS (
      SELECT 1
      FROM comments r
      WHERE r.parent_comment_id = c.comment_id
  );

-- @R14
-- "Not following back": accounts that follow user 217 whom 217 doesn't follow
SELECT f.follower_id
FROM follows f
WHERE f.followee_id = 217 AND f.status = 'ACCEPTED'
  AND NOT EXISTS (SELECT 1 FROM follows b WHERE b.follower_id = 217 AND b.followee_id = f.follower_id)
ORDER BY f.follower_id;

-- @R15
-- Data quality: verified or creator accounts whose stored follower count is wrong
SELECT u.user_id, u.username, u.followers_count AS stored, count(f.follower_id) AS actual
FROM users u
LEFT JOIN follows f ON f.followee_id = u.user_id AND f.status = 'ACCEPTED'
WHERE u.is_verified OR u.account_type = 'CREATOR'
GROUP BY u.user_id, u.username, u.followers_count
HAVING u.followers_count <> count(f.follower_id)
ORDER BY u.user_id;

-- @R16
-- Places: posts tagged with a location containing "goa" in June 2026
SELECT post_id, user_id, location_name, like_count
FROM posts
WHERE location_name ILIKE '%goa%'
  AND created_at >= '2026-06-01' AND created_at < '2026-07-01'
ORDER BY like_count DESC;

-- @R17
-- Reels team: creators' reels longer than 60 seconds posted in 2026
-- EXTRACT(YEAR FROM created_at) is not a range on the raw column.
-- The half-open range is the same year in the session time zone.
SELECT p.post_id, p.user_id, pm.duration_sec, p.like_count
FROM posts p
JOIN post_media pm ON pm.post_id = p.post_id AND pm.position = 1
JOIN users u       ON u.user_id = p.user_id
WHERE p.post_type = 'REEL'
  AND pm.duration_sec > 60
  AND u.account_type = 'CREATOR'
  AND p.created_at >= '2026-01-01'
  AND p.created_at < '2027-01-01'
ORDER BY p.like_count DESC
LIMIT 50;

-- @R18
-- Content analytics: new posts per day and type in June 2026
-- The cast stays in the SELECT and GROUP BY (that is the report grain).
-- It is removed from WHERE so posts_created_at_idx can bound the scan.
SELECT created_at::date AS day, post_type, count(*) AS posts
FROM posts
WHERE created_at >= '2026-06-01'
  AND created_at < '2026-07-01'
GROUP BY 1, 2
ORDER BY 1, 2;

-- @R19
-- Verified-account report: last post time and total likes received by every verified account
-- One grouped join replaces two correlated subqueries. count(l.post_id) ignores
-- the NULL-extended likes row, so a user with posts and no likes still gets 0.
-- Users with no posts stay in the result via LEFT JOIN (last_post_at NULL, 0 likes).
SELECT u.user_id, u.username,
       agg.last_post_at,
       coalesce(agg.likes_received, 0) AS likes_received
FROM users u
LEFT JOIN (
    SELECT p.user_id,
           max(p.created_at) AS last_post_at,
           count(l.post_id) AS likes_received
    FROM posts p
    LEFT JOIN likes l ON l.post_id = p.post_id
    GROUP BY p.user_id
) agg ON agg.user_id = u.user_id
WHERE u.is_verified
ORDER BY likes_received DESC;

-- @R20
-- Content analytics: 10 most-commented posts of June 2026 (counting real comments)
SELECT c.post_id, count(*) AS comments
FROM comments c
JOIN posts p ON p.post_id = c.post_id
WHERE p.created_at >= '2026-06-01'
GROUP BY c.post_id
ORDER BY comments DESC
LIMIT 10;

-- @R21
-- Creator tools: "ghost followers" of user 217 (followers who never liked any of 217's posts)
SELECT f.follower_id
FROM follows f
WHERE f.followee_id = 217 AND f.status = 'ACCEPTED'
  AND NOT EXISTS (SELECT 1 FROM likes l JOIN posts p ON p.post_id = l.post_id
                  WHERE l.user_id = f.follower_id AND p.user_id = 217)
ORDER BY f.follower_id;

-- @R22
-- Moderation console: hidden comments, newest first, page 61 (25 per page)
-- comment_id is a tie-break so two hidden comments with the same created_at
-- do not swap pages between runs. The partial index
-- comments_hidden_created_idx matches this order.
-- Keyset form for a later page, once the client has the last row of page 60
-- (cursor_created_at, cursor_comment_id): drop OFFSET and add
--   AND (created_at, comment_id) < (cursor_created_at, cursor_comment_id)
-- A cursor baked in from this seed would not be page 61 on the large dataset,
-- so the benchmarked query still asks for page 61 directly.
SELECT comment_id, post_id, user_id, body, created_at
FROM comments
WHERE is_hidden
ORDER BY created_at DESC, comment_id DESC
OFFSET 1500
LIMIT 25;

-- @R23
-- Like button state: has user 1042 liked post 59689?
SELECT EXISTS (SELECT 1 FROM likes WHERE user_id = 1042 AND post_id = 59689) AS liked;

-- @R24
-- Story insights: total story views per account in the last 30 days, top 20
SELECT user_id, count(*) AS stories, sum(view_count) AS views
FROM stories
WHERE created_at >= '2026-06-01'
GROUP BY user_id
ORDER BY views DESC
LIMIT 20;

-- @W01
-- Publish a new photo post
INSERT INTO posts (post_id, user_id, post_type, caption, location_name, created_at)
VALUES (90000001, 1042, 'PHOTO', 'Monsoon diaries #monsoon', 'Mumbai', '2026-07-01 08:00:00+05:30');

-- @W02
-- Double-tap: user 1042 likes post 59689
INSERT INTO likes (user_id, post_id, created_at)
VALUES (1042, 59689, '2026-07-01 08:01:00+05:30')
ON CONFLICT (user_id, post_id) DO NOTHING;

-- @W03
-- Keep the counter in sync after the like
UPDATE posts SET like_count = like_count + 1 WHERE post_id = 59689;

-- @W04
-- Nightly job: recompute every user's follower count
UPDATE users u
SET followers_count = coalesce(s.n, 0)
FROM (SELECT uu.user_id, count(f.follower_id) AS n
      FROM users uu LEFT JOIN follows f ON f.followee_id = uu.user_id AND f.status = 'ACCEPTED'
      GROUP BY uu.user_id) s
WHERE s.user_id = u.user_id AND u.followers_count <> coalesce(s.n, 0);

-- @W05
-- Housekeeping: delete stories that expired before June 2026
DELETE FROM stories
WHERE expires_at < '2026-06-01';

-- @W06
-- Private account 338 accepts all pending follow requests
UPDATE follows
SET status = 'ACCEPTED'
WHERE followee_id = 338 AND status = 'PENDING';

-- @END
ROLLBACK;
