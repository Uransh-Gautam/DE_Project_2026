CREATE SCHEMA IF NOT EXISTS instagram;
SET search_path TO instagram;

CREATE TABLE users (
    user_id BIGINT PRIMARY KEY,
    username VARCHAR(30) NOT NULL UNIQUE
        CHECK (username ~ '^[a-z0-9._]{1,30}$'),
    full_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    bio TEXT,
    account_type TEXT NOT NULL
        CHECK (account_type IN ('PERSONAL', 'CREATOR', 'BUSINESS')),
    is_private BOOLEAN NOT NULL,
    is_verified BOOLEAN NOT NULL,
    followers_count INTEGER NOT NULL CHECK (followers_count >= 0),
    following_count INTEGER NOT NULL CHECK (following_count >= 0),
    created_at TIMESTAMPTZ NOT NULL,
    CHECK (account_type <> 'BUSINESS' OR NOT is_private)
);

CREATE TABLE follows (
    follower_id BIGINT NOT NULL,
    followee_id BIGINT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('ACCEPTED', 'PENDING')),
    created_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (follower_id, followee_id),
    CHECK (follower_id <> followee_id),
    FOREIGN KEY (follower_id) REFERENCES users (user_id) ON DELETE CASCADE,
    FOREIGN KEY (followee_id) REFERENCES users (user_id) ON DELETE CASCADE
);

CREATE TABLE hashtags (
    hashtag_id BIGINT PRIMARY KEY,
    tag TEXT NOT NULL UNIQUE CHECK (tag ~ '^[a-z0-9_]+$')
);

CREATE TABLE posts (
    post_id BIGINT PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    post_type TEXT NOT NULL
        CHECK (post_type IN ('PHOTO', 'VIDEO', 'CAROUSEL', 'REEL')),
    caption TEXT,
    location_name TEXT,
    like_count INTEGER NOT NULL CHECK (like_count >= 0),
    comment_count INTEGER NOT NULL CHECK (comment_count >= 0),
    is_archived BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE post_hashtags (
    post_id BIGINT NOT NULL,
    hashtag_id BIGINT NOT NULL,
    PRIMARY KEY (post_id, hashtag_id),
    FOREIGN KEY (post_id) REFERENCES posts (post_id) ON DELETE CASCADE,
    FOREIGN KEY (hashtag_id) REFERENCES hashtags (hashtag_id) ON DELETE CASCADE
);

CREATE TABLE post_media (
    post_id BIGINT NOT NULL REFERENCES posts (post_id) ON DELETE CASCADE,
    position INTEGER NOT NULL CHECK (position >= 1),
    media_type TEXT NOT NULL CHECK (media_type IN ('IMAGE', 'VIDEO')),
    media_url TEXT NOT NULL,
    width INTEGER NOT NULL CHECK (width > 0),
    height INTEGER NOT NULL CHECK (height > 0),
    duration_sec NUMERIC,
    PRIMARY KEY (post_id, position),
    CHECK (
        (media_type = 'VIDEO' AND duration_sec IS NOT NULL AND duration_sec > 0)
        OR (media_type = 'IMAGE' AND duration_sec IS NULL)
    )
);

CREATE TABLE likes (
    user_id BIGINT NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    post_id BIGINT NOT NULL REFERENCES posts (post_id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (user_id, post_id)
);

CREATE TABLE comments (
    comment_id BIGINT PRIMARY KEY,
    post_id BIGINT NOT NULL REFERENCES posts (post_id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    parent_comment_id BIGINT,
    body TEXT NOT NULL,
    is_hidden BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    UNIQUE (comment_id, post_id),
    FOREIGN KEY (parent_comment_id, post_id)
        REFERENCES comments (comment_id, post_id)
        ON DELETE CASCADE
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE stories (
    story_id BIGINT PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    media_type TEXT NOT NULL CHECK (media_type IN ('IMAGE', 'VIDEO')),
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    view_count INTEGER NOT NULL CHECK (view_count >= 0),
    CHECK (expires_at = created_at + INTERVAL '24 hours')
);
