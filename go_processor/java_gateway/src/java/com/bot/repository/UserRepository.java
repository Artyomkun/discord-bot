package com.bot.repository;

import com.bot.model.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface UserRepository extends JpaRepository<User, Long> {
    
    // Основные поиски
    Optional<User> findByUsername(String username);
    Optional<User> findByEmail(String email);
    Optional<User> findByDiscordId(String discordId);
    
    // Поиск с игнорированием регистра
    List<User> findByUsernameContainingIgnoreCase(String username);
    
    // Проверки существования
    boolean existsByUsername(String username);
    boolean existsByEmail(String username);
    boolean existsByDiscordId(String discordId);
    
    // Сортировка и лимиты
    long count();
    List<User> findTop10ByOrderByIdDesc();
    List<User> findTop10ByOrderByCreatedAtDesc();
    
    // JPQL запросы
    @Query("SELECT DISTINCT u FROM User u JOIN u.playlists p")
    List<User> findUsersWithPlaylists();
    
    @Query("SELECT u FROM User u WHERE u.email = :email OR u.username = :username")
    Optional<User> findByEmailOrUsername(@Param("email") String email, @Param("username") String username);
    
    // Поиск по частичному совпадению в email
    @Query("SELECT u FROM User u WHERE u.email LIKE %:domain%")
    List<User> findByEmailDomain(@Param("domain") String domain);
    
    // Подсчёт пользователей, созданных после указанной даты
    @Query("SELECT COUNT(u) FROM User u WHERE u.createdAt > :date")
    long countUsersCreatedAfter(@Param("date") java.time.LocalDateTime date);
}