-- Таблица пользователей
CREATE TABLE IF NOT EXISTS users (
    id BIGSERIAL PRIMARY KEY,  -- BIGSERIAL для Discord ID (которые могут быть > 2^31-1)
    discord_id BIGINT UNIQUE NOT NULL,  -- Discord ID пользователя
    username VARCHAR(255) NOT NULL,
    display_name VARCHAR(255),
    email VARCHAR(255) UNIQUE,
    
    -- Для бота
    is_premium BOOLEAN DEFAULT FALSE,
    premium_until TIMESTAMP,
    timezone VARCHAR(50) DEFAULT 'UTC',
    language VARCHAR(10) DEFAULT 'en',
    
    -- Статистика
    total_commands INT DEFAULT 0,
    total_music_played INT DEFAULT 0,
    last_active TIMESTAMP DEFAULT NOW(),
    
    -- Метаданные
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    
    -- Индексы для быстрого поиска
    CONSTRAINT valid_email CHECK (email IS NULL OR email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

-- Индексы
CREATE INDEX IF NOT EXISTS idx_users_discord_id ON users(discord_id);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_premium ON users(is_premium) WHERE is_premium = TRUE;
CREATE INDEX IF NOT EXISTS idx_users_last_active ON users(last_active DESC);

-- Триггер для обновления updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_users_updated_at 
    BEFORE UPDATE ON users 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- Комментарии к таблице и колонкам
COMMENT ON TABLE users IS 'Music bot users table';
COMMENT ON COLUMN users.discord_id IS 'Discord user ID (snowflake)';
COMMENT ON COLUMN users.is_premium IS 'Whether user has premium subscription';
COMMENT ON COLUMN users.total_commands IS 'Total number of commands executed';