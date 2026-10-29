package com.bot.model;

import java.util.HashMap;
import java.util.Map;

public class DiscordRequest {
    private String command;
    private String userId;
    private String guildId;
    private String channelId;
    private String messageId;
    private Map<String, String> parameters;
    private String interactionId;
    private String token;
    private String url;
    private int volume;
    private String effectType;
    private double intensity;
    private String query;
    private int position;
    private int fromPosition;
    private int toPosition;
    private String mode;
    private boolean shuffle;
    private boolean clear;
    private String approvalId;
    private String approvalStatus;
    private String approvalReason;
    private long approvalTimeout;
    private Long playlistId;
    private String playlistName;
    private boolean isPublic;
    private Long songId;
    private String songTitle;

    public DiscordRequest() {
        this.parameters = new HashMap<>();
        this.volume = 50;
        this.intensity = 0.5;
    }

    public DiscordRequest(String command, String userId, String guildId) {
        this();
        this.command = command;
        this.userId = userId;
        this.guildId = guildId;
    }

    public String getParameter(String key) {
        return parameters != null ? parameters.get(key) : null;
    }

    public String getParameterOrDefault(String key, String defaultValue) {
        String value = getParameter(key);
        return value != null ? value : defaultValue;
    }

    public boolean hasParameter(String key) {
        return parameters != null && parameters.containsKey(key);
    }

    public boolean isApproved() {
        return "approved".equalsIgnoreCase(approvalStatus);
    }

    public boolean isPendingApproval() {
        return "pending".equalsIgnoreCase(approvalStatus);
    }

    public String getCommand() { return command; }
    public void setCommand(String command) { this.command = command; }

    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }

    public String getGuildId() { return guildId; }
    public void setGuildId(String guildId) { this.guildId = guildId; }

    public String getChannelId() { return channelId; }
    public void setChannelId(String channelId) { this.channelId = channelId; }

    public String getMessageId() { return messageId; }
    public void setMessageId(String messageId) { this.messageId = messageId; }

    public Map<String, String> getParameters() { return parameters; }
    public void setParameters(Map<String, String> parameters) { this.parameters = parameters; }

    public String getInteractionId() { return interactionId; }
    public void setInteractionId(String interactionId) { this.interactionId = interactionId; }

    public String getToken() { return token; }
    public void setToken(String token) { this.token = token; }

    public String getUrl() { return url; }
    public void setUrl(String url) { this.url = url; }

    public int getVolume() { return volume; }
    public void setVolume(int volume) { this.volume = volume; }

    public String getEffectType() { return effectType; }
    public void setEffectType(String effectType) { this.effectType = effectType; }

    public double getIntensity() { return intensity; }
    public void setIntensity(double intensity) { this.intensity = intensity; }

    public String getQuery() { return query; }
    public void setQuery(String query) { this.query = query; }

    public int getPosition() { return position; }
    public void setPosition(int position) { this.position = position; }

    public int getFromPosition() { return fromPosition; }
    public void setFromPosition(int fromPosition) { this.fromPosition = fromPosition; }

    public int getToPosition() { return toPosition; }
    public void setToPosition(int toPosition) { this.toPosition = toPosition; }

    public String getMode() { return mode; }
    public void setMode(String mode) { this.mode = mode; }

    public boolean isShuffle() { return shuffle; }
    public void setShuffle(boolean shuffle) { this.shuffle = shuffle; }

    public boolean isClear() { return clear; }
    public void setClear(boolean clear) { this.clear = clear; }

    public String getApprovalId() { return approvalId; }
    public void setApprovalId(String approvalId) { this.approvalId = approvalId; }

    public String getApprovalStatus() { return approvalStatus; }
    public void setApprovalStatus(String approvalStatus) { this.approvalStatus = approvalStatus; }

    public String getApprovalReason() { return approvalReason; }
    public void setApprovalReason(String approvalReason) { this.approvalReason = approvalReason; }

    public long getApprovalTimeout() { return approvalTimeout; }
    public void setApprovalTimeout(long approvalTimeout) { this.approvalTimeout = approvalTimeout; }

    public Long getPlaylistId() { return playlistId; }
    public void setPlaylistId(Long playlistId) { this.playlistId = playlistId; }

    public String getPlaylistName() { return playlistName; }
    public void setPlaylistName(String playlistName) { this.playlistName = playlistName; }

    public boolean isPublic() { return isPublic; }
    public void setPublic(boolean isPublic) { this.isPublic = isPublic; }

    public Long getSongId() { return songId; }
    public void setSongId(Long songId) { this.songId = songId; }

    public String getSongTitle() { return songTitle; }
    public void setSongTitle(String songTitle) { this.songTitle = songTitle; }
}