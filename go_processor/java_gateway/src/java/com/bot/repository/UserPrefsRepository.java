package com.bot.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.Optional;

public interface UserPrefsRepository extends JpaRepository<UserPrefs, String> {
    default Optional<UserPrefs> findByUserId(String userId) {
        return findById(userId);
    }
    boolean existsByUserId(String userId);
    void deleteByUserId(String userId);
}