package com.bot.services;

import com.bot.model.User;
import net.dv8tion.jda.api.JDA;
import net.dv8tion.jda.api.JDABuilder;
import net.dv8tion.jda.api.entities.User;
import net.dv8tion.jda.api.requests.GatewayIntent;
import net.dv8tion.jda.api.utils.cache.CacheFlag;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import java.util.EnumSet;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

@Service
public class DiscordClient {
    private static final Logger log = LoggerFactory.getLogger(DiscordClient.class);
    
    private JDA jda;
    
    @Value("${discord.token:}")
    private String token;
    
    @Value("${discord.gateway-intents.all:false}")
    private boolean enableAllIntents;
    
    @PostConstruct
    public void init() {
        if (token == null || token.isEmpty() || token.equals("YOUR_BOT_TOKEN")) {
            log.warn("Discord token not configured, Discord client will be disabled");
            return;
        }
        
        try {
            JDABuilder builder = JDABuilder.createDefault(token);
            
            if (enableAllIntents) {
                builder.enableIntents(EnumSet.allOf(GatewayIntent.class));
            } else {
                builder.enableIntents(GatewayIntent.GUILD_MEMBERS, GatewayIntent.GUILD_PRESENCES);
            }
            
            builder.disableCache(EnumSet.of(
                CacheFlag.ACTIVITY,
                CacheFlag.CLIENT_STATUS,
                CacheFlag.EMOJI,
                CacheFlag.STICKER,
                CacheFlag.VOICE_STATE
            ));
            
            CompletableFuture<JDA> future = CompletableFuture.supplyAsync(() -> {
                try {
                    return builder.build().awaitReady();
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    throw new RuntimeException(e);
                }
            });
            
            jda = future.get(30, TimeUnit.SECONDS);
            log.info("✅ Discord client initialized as {}", jda.getSelfUser().getName());
            
        } catch (Exception e) {
            log.error("❌ Failed to initialize Discord client: {}", e.getMessage(), e);
        }
    }
    
    @PreDestroy
    public void shutdown() {
        if (jda != null) {
            log.info("Shutting down Discord client...");
            jda.shutdown();
            try {
                jda.awaitShutdown(10, TimeUnit.SECONDS);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                log.warn("Interrupted while shutting down Discord client");
            }
        }
    }
    
    public net.dv8tion.jda.api.entities.User getDiscordUser(String userId) {
        if (jda == null) return null;
        return jda.getUserById(userId);
    }
    
    public User getUser(String userId) {
        net.dv8tion.jda.api.entities.User discordUser = getDiscordUser(userId);
        if (discordUser == null) return null;
        
        User user = new User();
        user.setDiscordId(discordUser.getId());
        user.setUsername(discordUser.getName());
        user.setGlobalName(discordUser.getGlobalName());
        user.setAvatarUrl(discordUser.getAvatarUrl());
        
        return user;
    }
    
    public boolean isConnected() {
        return jda != null && jda.getStatus() == JDA.Status.CONNECTED;
    }
    
    public JDA.Status getStatus() {
        return jda != null ? jda.getStatus() : null;
    }
    
    public String getBotName() {
        return jda != null ? jda.getSelfUser().getName() : "unknown";
    }
}