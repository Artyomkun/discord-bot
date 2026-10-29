package com.bot.entity;

import javax.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "user_settings")
public class UserSettingsEntity {
    
    @Id
    @Column(name = "user_id", nullable = false)
    private Long userId;
    
    @Enumerated(EnumType.STRING)
    @Column(name = "music_region")
    private MusicRegion musicRegion;
    
    @Column(name = "default_volume")
    private Integer defaultVolume = 100;
    
    @Column(name = "default_format")
    private String defaultFormat = "opus";
    
    @Column(name = "created_at")
    private LocalDateTime createdAt;
    
    @Column(name = "updated_at")
    private LocalDateTime updatedAt;
    
    // Геттеры и сеттеры (исправлены)
    public Long getUserId() { 
        return userId; 
    }
    
    public void setUserId(Long userId) { 
        this.userId = userId; 
    }
    
    public MusicRegion getMusicRegion() { 
        return musicRegion; 
    }
    
    public void setMusicRegion(MusicRegion musicRegion) { 
        this.musicRegion = musicRegion; 
    }
    
    public Integer getDefaultVolume() { 
        return defaultVolume; 
    }
    
    public void setDefaultVolume(Integer defaultVolume) { 
        this.defaultVolume = defaultVolume; 
    }
    
    public String getDefaultFormat() { 
        return defaultFormat; 
    }
    
    public void setDefaultFormat(String defaultFormat) { 
        this.defaultFormat = defaultFormat; 
    }
    
    public LocalDateTime getCreatedAt() { 
        return createdAt; 
    }
    
    public void setCreatedAt(LocalDateTime createdAt) { 
        this.createdAt = createdAt; 
    }
    
    public LocalDateTime getUpdatedAt() { 
        return updatedAt; 
    }
    
    public void setUpdatedAt(LocalDateTime updatedAt) { 
        this.updatedAt = updatedAt; 
    }
    
    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();
    }
    
    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }
}