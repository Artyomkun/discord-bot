package com.bot.repository;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import com.bot.model.Song;
import java.util.List;
import java.util.Optional;

public interface SongRepository extends JpaRepository<Song, Long> {
    
    // Базовые поиски
    Optional<Song> findByUrl(String url);
    
    List<Song> findByTitleContainingIgnoreCase(String title);
    
    List<Song> findByDurationLessThan(Integer maxDuration);
    List<Song> findByDurationGreaterThan(Integer minDuration);
    
    List<Song> findByAddedBy_Id(Long userId);
    
    // Свежие треки (с пагинацией)
    List<Song> findTop10ByOrderByIdDesc();
    Page<Song> findAllByOrderByCreatedAtDesc(Pageable pageable);
    
    // Кастомные запросы
    @Query("SELECT s FROM Song s WHERE LOWER(s.title) LIKE LOWER(CONCAT('%', :title, '%')) AND s.duration <= :maxDuration")
    List<Song> findByTitleAndMaxDuration(@Param("title") String title, @Param("maxDuration") Integer maxDuration);
    
    @Query("SELECT COUNT(s) FROM Song s JOIN s.playlists p WHERE p.id = :playlistId")
    long countSongsInPlaylist(@Param("playlistId") Long playlistId);
    
    // Поиск без дубликатов
    List<Song> findDistinctByTitleContainingIgnoreCase(String title);
    
    // Поиск по исполнителю (если есть поле artist)
    @Query("SELECT s FROM Song s WHERE LOWER(s.artist) LIKE LOWER(CONCAT('%', :artist, '%'))")
    List<Song> findByArtistContainingIgnoreCase(@Param("artist") String artist);
    
    // Статистика
    @Query("SELECT AVG(s.duration) FROM Song s")
    Double getAverageDuration();
    
    @Query("SELECT SUM(s.duration) FROM Song s")
    Long getTotalDuration();
    
    // Поиск популярных песен (по количеству добавлений в плейлисты)
    @Query("SELECT s, COUNT(p) FROM Song s JOIN s.playlists p GROUP BY s ORDER BY COUNT(p) DESC")
    List<Song> findMostPopularSongs(Pageable pageable);
    
    // Удаление старых песен (например, неиспользуемых более 30 дней)
    @Modifying
    @Transactional
    @Query("DELETE FROM Song s WHERE s.lastPlayed < :cutoffDate AND s NOT IN (SELECT p.songs FROM Playlist p)")
    int deleteUnusedSongs(@Param("cutoffDate") LocalDateTime cutoffDate);
}