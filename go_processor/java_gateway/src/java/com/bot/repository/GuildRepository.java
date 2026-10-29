package com.bot.repository;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;
import com.bot.model.Guild;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface GuildRepository extends JpaRepository<Guild, Long> {
    
    // Базовые поиски
    Optional<Guild> findByGuildId(String guildId);
    List<Guild> findByNameContainingIgnoreCase(String name);
    
    // Проверки
    boolean existsByGuildId(String guildId);
    
    // Операции с владельцами
    long countByOwnerId(Long ownerId);
    List<Guild> findByOwnerId(Long ownerId);
    
    // Удаление
    void deleteByGuildId(String guildId);
    
    // Статистика и активность
    @Query("SELECT COUNT(g) FROM Guild g")
    long countAllGuilds();
    
    @Query("SELECT g FROM Guild g WHERE g.lastActive > :since")
    List<Guild> findActiveGuilds(@Param("since") LocalDateTime since);
    
    @Query("SELECT g FROM Guild g WHERE g.lastActive < :cutoff")
    List<Guild> findInactiveGuilds(@Param("cutoff") LocalDateTime cutoff);
    
    // Гильдии без плейлистов
    @Query("SELECT g FROM Guild g WHERE g.id NOT IN (SELECT DISTINCT p.guild.id FROM Playlist p WHERE p.guild IS NOT NULL)")
    List<Guild> findGuildsWithoutPlaylists();
    
    // Гильдии с большим количеством плейлистов
    @Query("SELECT g FROM Guild g WHERE SIZE(g.playlists) > :minPlaylists")
    List<Guild> findGuildsWithManyPlaylists(@Param("minPlaylists") int minPlaylists);
    
    // Поиск недавно созданных гильдий
    List<Guild> findByCreatedAtAfter(LocalDateTime date);
    
    // Пагинация для активных гильдий
    Page<Guild> findByLastActiveAfter(LocalDateTime since, Pageable pageable);
    
    // Обновление активности (массово)
    @Modifying
    @Transactional
    @Query("UPDATE Guild g SET g.lastActive = CURRENT_TIMESTAMP WHERE g.guildId = :guildId")
    int updateLastActive(@Param("guildId") String guildId);
    
    // Удаление неактивных гильдий
    @Modifying
    @Transactional
    @Query("DELETE FROM Guild g WHERE g.lastActive < :cutoff AND g.id NOT IN (SELECT p.guild.id FROM Playlist p)")
    int deleteInactiveGuildsWithoutPlaylists(@Param("cutoff") LocalDateTime cutoff);
}