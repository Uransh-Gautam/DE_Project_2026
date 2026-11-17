\set ON_ERROR_STOP on

SET search_path TO instagram;

BEGIN;
SET CONSTRAINTS ALL DEFERRED;

\copy users (user_id, username, full_name, email, bio, account_type, is_private, is_verified, followers_count, following_count, created_at) FROM 'seed_data/users.csv' WITH (FORMAT csv, HEADER true)
\copy follows (follower_id, followee_id, status, created_at) FROM 'seed_data/follows.csv' WITH (FORMAT csv, HEADER true)
\copy hashtags (hashtag_id, tag) FROM 'seed_data/hashtags.csv' WITH (FORMAT csv, HEADER true)
\copy posts (post_id, user_id, post_type, caption, location_name, like_count, comment_count, is_archived, created_at) FROM 'seed_data/posts.csv' WITH (FORMAT csv, HEADER true)
\copy post_hashtags (post_id, hashtag_id) FROM 'seed_data/post_hashtags.csv' WITH (FORMAT csv, HEADER true)
\copy post_media (post_id, position, media_type, media_url, width, height, duration_sec) FROM 'seed_data/post_media.csv' WITH (FORMAT csv, HEADER true)
\copy likes (user_id, post_id, created_at) FROM 'seed_data/likes.csv' WITH (FORMAT csv, HEADER true)
\copy comments (comment_id, post_id, user_id, parent_comment_id, body, is_hidden, created_at) FROM 'seed_data/comments.csv' WITH (FORMAT csv, HEADER true)
\copy stories (story_id, user_id, media_type, created_at, expires_at, view_count) FROM 'seed_data/stories.csv' WITH (FORMAT csv, HEADER true)

COMMIT;

ANALYZE;

SELECT 'comments' AS table_name, count(*) AS row_count FROM comments
UNION ALL SELECT 'follows', count(*) FROM follows
UNION ALL SELECT 'hashtags', count(*) FROM hashtags
UNION ALL SELECT 'likes', count(*) FROM likes
UNION ALL SELECT 'post_hashtags', count(*) FROM post_hashtags
UNION ALL SELECT 'post_media', count(*) FROM post_media
UNION ALL SELECT 'posts', count(*) FROM posts
UNION ALL SELECT 'stories', count(*) FROM stories
UNION ALL SELECT 'users', count(*) FROM users
ORDER BY table_name;

SELECT 'comment_parent_on_same_post' AS check_name, count(*) AS violations
FROM comments child
JOIN comments parent ON parent.comment_id = child.parent_comment_id
WHERE child.post_id <> parent.post_id
UNION ALL
SELECT 'posts_without_media', count(*)
FROM posts p
WHERE NOT EXISTS (
    SELECT 1 FROM post_media pm WHERE pm.post_id = p.post_id
)
UNION ALL
SELECT 'carousels_with_fewer_than_two_media', count(*)
FROM posts p
WHERE p.post_type = 'CAROUSEL'
  AND (
      SELECT count(*) FROM post_media pm WHERE pm.post_id = p.post_id
  ) < 2
UNION ALL
SELECT 'stories_not_expiring_after_24_hours', count(*)
FROM stories
WHERE expires_at <> created_at + INTERVAL '24 hours'
ORDER BY check_name;
