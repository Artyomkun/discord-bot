package com.bot.repository;

import com.bot.entity.UserSettingsEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;
import java.time.LocalDateTime;
import java.util.Optional;

@Repository
public interface UserSettingsRepository extends JpaRepository<UserSettingsEntity, String> {
    
    Optional<UserSettingsEntity> findByUserId(String userId);
    
    boolean existsByUserId(String userId);
    
    void deleteByUserId(String userId);
    
    @Modifying
    @Transactional
    @Query("DELETE FROM UserSettingsEntity u WHERE u.lastUpdated < :cutoff")
    void deleteOldSettings(@Param("cutoff") LocalDateTime cutoff);
    
    Optional<UserSettingsEntity> findByUserIdAndIsActiveTrue(String userId);
    
    long countByMusicRegion(String musicRegion);
}