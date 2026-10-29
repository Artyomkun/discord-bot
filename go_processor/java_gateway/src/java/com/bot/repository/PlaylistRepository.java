package com.bot.repository;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;
import com.bot.model.Playlist;
import java.util.List;
import java.util.Optional;

public interface PlaylistRepository extends JpaRepository<Playlist, Long> {
    
    // Базовые поиски
    Optional<Playlist> findByNameAndUserId(String name, Long userId);
    Optional<Playlist> findByNameAndGuildId(String name, Long guildId);
    
    List<Playlist> findByUserId(Long userId);
    List<Playlist> findByGuildId(Long guildId);
    List<Playlist> findByIsPublicTrue();
    
    // Поиск публичных плейлистов по названию (без учёта регистра)
    List<Playlist> findByIsPublicTrueAndNameContainingIgnoreCase(String name);
    
    // Статистика и удаление
    long countByUserId(Long userId);
    void deleteByUserId(Long userId);
    
    boolean existsByNameAndUserId(String name, Long userId);
    boolean existsByNameAndGuildId(String name, Long guildId);
    
    // Свежие плейлисты
    List<Playlist> findTop10ByOrderByIdDesc();
    Page<Playlist> findAllByOrderByCreatedAtDesc(Pageable pageable);
    
    // Поиск плейлистов, содержащих песню
    @Query("SELECT p FROM Playlist p JOIN p.songs s WHERE s.id = :songId")
    List<Playlist> findBySongId(@Param("songId") Long songId);
    
    @Query("SELECT COUNT(s) FROM Playlist p JOIN p.songs s WHERE p.id = :playlistId")
    long countSongsInPlaylist(@Param("playlistId") Long playlistId);
    
    // Поиск популярных плейлистов (по количеству треков)
    @Query("SELECT p FROM Playlist p ORDER BY SIZE(p.songs) DESC")
    List<Playlist> findMostPopularPlaylists(Pageable pageable);
    
    // Поиск публичных плейлистов по пользователю
    List<Playlist> findByUserIdAndIsPublicTrue(Long userId);
    
    // Удаление пустых плейлистов
    @Modifying
    @Transactional
    @Query("DELETE FROM Playlist p WHERE SIZE(p.songs) = 0 AND p.createdAt < :cutoffDate")
    int deleteEmptyPlaylists(@Param("cutoffDate") java.time.LocalDateTime cutoffDate);
    
    // Поиск по имени без учёта регистра
    List<Playlist> findByNameContainingIgnoreCase(String name);
}