-- Полный SQL schema для Discord music bot

-- Таблица пользователей (ОБЯЗАТЕЛЬНО ПЕРВОЙ!)
CREATE TABLE IF NOT EXISTS users (
    id BIGSERIAL PRIMARY KEY,
    discord_id BIGINT UNIQUE NOT NULL,
    username VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Таблица гильдий (Discord серверов)
CREATE TABLE IF NOT EXISTS guilds (
    id BIGSERIAL PRIMARY KEY,
    guild_id VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    owner_discord_id BIGINT,
    owner_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Таблица плейлистов
CREATE TABLE IF NOT EXISTS playlists (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    is_public BOOLEAN DEFAULT FALSE,
    user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
    guild_id BIGINT REFERENCES guilds(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Таблица песен
CREATE TABLE IF NOT EXISTS songs (
    id BIGSERIAL PRIMARY KEY,
    title VARCHAR(500) NOT NULL,
    url TEXT NOT NULL,
    duration INTEGER,
    thumbnail_url TEXT,
    added_by BIGINT REFERENCES users(id) ON DELETE SET NULL,
    added_at TIMESTAMP DEFAULT NOW(),
    play_count INT DEFAULT 0
);

-- Промежуточная таблица для связи плейлистов и песен (many-to-many)
CREATE TABLE IF NOT EXISTS playlist_songs (
    playlist_id BIGINT REFERENCES playlists(id) ON DELETE CASCADE,
    song_id BIGINT REFERENCES songs(id) ON DELETE CASCADE,
    position INT DEFAULT 0,
    added_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (playlist_id, song_id)
);

-- 🔴 НОВАЯ: Таблица очереди воспроизведения
CREATE TABLE IF NOT EXISTS queue (
    id BIGSERIAL PRIMARY KEY,
    guild_id BIGINT REFERENCES guilds(id) ON DELETE CASCADE,
    song_id BIGINT REFERENCES songs(id) ON DELETE CASCADE,
    user_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
    position INT NOT NULL,
    is_playing BOOLEAN DEFAULT FALSE,
    added_at TIMESTAMP DEFAULT NOW()
);

-- 🔴 НОВАЯ: Таблица истории прослушиваний
CREATE TABLE IF NOT EXISTS listening_history (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
    song_id BIGINT REFERENCES songs(id) ON DELETE CASCADE,
    guild_id BIGINT REFERENCES guilds(id) ON DELETE CASCADE,
    listened_at TIMESTAMP DEFAULT NOW()
);

-- Индексы для производительности
CREATE INDEX IF NOT EXISTS idx_users_discord_id ON users(discord_id);
CREATE INDEX IF NOT EXISTS idx_guilds_guild_id ON guilds(guild_id);
CREATE INDEX IF NOT EXISTS idx_playlists_user_id ON playlists(user_id);
CREATE INDEX IF NOT EXISTS idx_playlists_guild_id ON playlists(guild_id);
CREATE INDEX IF NOT EXISTS idx_playlist_songs_playlist_id ON playlist_songs(playlist_id);
CREATE INDEX IF NOT EXISTS idx_queue_guild_id ON queue(guild_id);
CREATE INDEX IF NOT EXISTS idx_queue_position ON queue(position);
CREATE INDEX IF NOT EXISTS idx_history_user_id ON listening_history(user_id);
CREATE INDEX IF NOT EXISTS idx_history_listened_at ON listening_history(listened_at DESC);

-- Индекс для полнотекстового поиска на русском и английском
CREATE INDEX IF NOT EXISTS idx_songs_title_fts ON songs 
    USING GIN (to_tsvector('russian', title));

-- ИЛИ комбинированный поиск на обоих языках
CREATE INDEX IF NOT EXISTS idx_songs_title_multilang ON songs 
    USING GIN (to_tsvector('simple', title)); 

-- Лучший вариант: поддержка нескольких языков
CREATE INDEX IF NOT EXISTS idx_songs_title_fts_ru_en ON songs 
    USING GIN (to_tsvector('russian', COALESCE(title_ru, title)));

-- Триггеры для updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_playlists_updated_at BEFORE UPDATE ON playlists FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Комментарии
COMMENT ON COLUMN users.discord_id IS 'Discord user ID (snowflake)';
COMMENT ON COLUMN queue.position IS 'Position in the playback queue, 0 = currently playing';