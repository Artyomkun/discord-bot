package com.bot.grpc.client;

import com.bot.grpc.client.DiscordClientProto.*;
import io.grpc.ManagedChannel;
import io.grpc.ManagedChannelBuilder;
import io.grpc.StatusRuntimeException;
import java.util.concurrent.TimeUnit;
import java.util.logging.Logger;
import java.util.logging.Level;
import java.util.Map;
import java.util.HashMap;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Protocol client for communicating with the Discord music bot gRPC server
 */
public class protocol {
    private static final Logger logger = Logger.getLogger(protocol.class.getName());
    
    // Singleton instance
    private static volatile protocol instance;
    private static final Object lock = new Object();
    
    // gRPC channel and stub
    private ManagedChannel channel;
    private DiscordClientServiceGrpc.DiscordClientServiceBlockingStub blockingStub;
    private DiscordClientServiceGrpc.DiscordClientServiceStub asyncStub;
    
    // Configuration
    private String serverHost;
    private int serverPort;
    private long timeoutSeconds = 30;
    private boolean isConnected = false;
    
    // Connection pool for multiple servers (if needed)
    private static final Map<String, protocol> instances = new ConcurrentHashMap<>();
    
    // Statistics
    private final AtomicLong totalCommands = new AtomicLong(0);
    private final AtomicLong successfulCommands = new AtomicLong(0);
    private final AtomicLong failedCommands = new AtomicLong(0);
    private final Map<String, AtomicLong> commandStats = new ConcurrentHashMap<>();
    
    /**
     * Constructor
     */
    private protocol(String host, int port) {
        this.serverHost = host;
        this.serverPort = port;
        connect();
    }
    
    /**
     * Get singleton instance
     */
    public static protocol getInstance() {
        return getInstance("localhost", 50051);
    }
    
    /**
     * Get instance for specific server
     */
    public static protocol getInstance(String host, int port) {
        String key = host + ":" + port;
        if (!instances.containsKey(key)) {
            synchronized (lock) {
                if (!instances.containsKey(key)) {
                    instances.put(key, new protocol(host, port));
                }
            }
        }
        return instances.get(key);
    }
    
    /**
     * Connect to gRPC server
     */
    private void connect() {
        try {
            if (channel != null && !channel.isShutdown()) {
                channel.shutdown();
            }
            
            channel = ManagedChannelBuilder.forAddress(serverHost, serverPort)
                .usePlaintext()
                .keepAliveTime(30, TimeUnit.SECONDS)
                .keepAliveTimeout(10, TimeUnit.SECONDS)
                .maxInboundMessageSize(100 * 1024 * 1024) // 100MB
                .build();
            
            blockingStub = DiscordClientServiceGrpc.newBlockingStub(channel);
            asyncStub = DiscordClientServiceGrpc.newStub(channel);
            isConnected = true;
            
            logger.info(String.format("✅ Connected to gRPC server at %s:%d", serverHost, serverPort));
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Failed to connect to gRPC server", e);
            isConnected = false;
        }
    }
    
    /**
     * Reconnect to server
     */
    public void reconnect() {
        logger.info("Reconnecting to gRPC server...");
        connect();
    }
    
    /**
     * Check connection status
     */
    public boolean isConnected() {
        return isConnected && channel != null && !channel.isShutdown();
    }
    
    /**
     * Send a command to the bot
     */
    public CommandResponse sendCommand(String command, String userId, String guildId, 
                                        String channelId, Map<String, String> options) {
        long startTime = System.currentTimeMillis();
        String methodName = "command_" + command;
        
        if (!isConnected()) {
            reconnect();
            if (!isConnected()) {
                recordCommand(methodName, false, System.currentTimeMillis() - startTime);
                return CommandResponse.newBuilder()
                    .setSuccess(false)
                    .setMessage("Not connected to server")
                    .build();
            }
        }
        
        try {
            CommandRequest.Builder requestBuilder = CommandRequest.newBuilder()
                .setCommand(command)
                .setUserId(userId)
                .setGuildId(guildId)
                .setChannelId(channelId);
            
            if (options != null) {
                requestBuilder.putAllOptions(options);
            }
            
            CommandRequest request = requestBuilder.build();
            CommandResponse response = blockingStub.withDeadlineAfter(timeoutSeconds, TimeUnit.SECONDS)
                .sendCommand(request);
            
            recordCommand(methodName, response.getSuccess(), System.currentTimeMillis() - startTime);
            
            if (logger.isLoggable(Level.FINE)) {
                logger.fine(String.format("Command '%s' from user %s: success=%s, message=%s",
                    command, userId, response.getSuccess(), response.getMessage()));
            }
            
            return response;
            
        } catch (StatusRuntimeException e) {
            logger.log(Level.WARNING, "gRPC error for command " + command, e);
            recordCommand(methodName, false, System.currentTimeMillis() - startTime);
            return CommandResponse.newBuilder()
                .setSuccess(false)
                .setMessage("gRPC error: " + e.getStatus().getCode())
                .build();
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Error sending command " + command, e);
            recordCommand(methodName, false, System.currentTimeMillis() - startTime);
            return CommandResponse.newBuilder()
                .setSuccess(false)
                .setMessage("Error: " + e.getMessage())
                .build();
        }
    }
    
    /**
     * Play a track
     */
    public PlayResponse play(String guildId, String userId, String url, String voiceChannelId,
                              Map<String, String> options) {
        long startTime = System.currentTimeMillis();
        
        if (!isConnected()) {
            reconnect();
            if (!isConnected()) {
                return PlayResponse.newBuilder()
                    .setSuccess(false)
                    .setMessage("Not connected to server")
                    .build();
            }
        }
        
        try {
            PlayRequest.Builder requestBuilder = PlayRequest.newBuilder()
                .setGuildId(guildId)
                .setUserId(userId)
                .setUrl(url)
                .setVoiceChannelId(voiceChannelId);
            
            if (options != null) {
                requestBuilder.putAllOptions(options);
            }
            
            PlayRequest request = requestBuilder.build();
            PlayResponse response = blockingStub.withDeadlineAfter(timeoutSeconds, TimeUnit.SECONDS)
                .play(request);
            
            recordCommand("play", response.getSuccess(), System.currentTimeMillis() - startTime);
            
            if (response.getSuccess()) {
                logger.info(String.format("🎵 Play request successful: %s - %s", 
                    response.getTrack().getTitle(), guildId));
            }
            
            return response;
            
        } catch (StatusRuntimeException e) {
            logger.log(Level.WARNING, "gRPC error in play", e);
            recordCommand("play", false, System.currentTimeMillis() - startTime);
            return PlayResponse.newBuilder()
                .setSuccess(false)
                .setMessage("gRPC error: " + e.getStatus().getCode())
                .build();
        }
    }
    
    /**
     * Pause playback
     */
    public PauseResponse pause(String guildId, String userId) {
        long startTime = System.currentTimeMillis();
        
        try {
            PauseRequest request = PauseRequest.newBuilder()
                .setGuildId(guildId)
                .setUserId(userId)
                .build();
            
            PauseResponse response = blockingStub.withDeadlineAfter(timeoutSeconds, TimeUnit.SECONDS)
                .pause(request);
            
            recordCommand("pause", response.getSuccess(), System.currentTimeMillis() - startTime);
            return response;
            
        } catch (StatusRuntimeException e) {
            logger.log(Level.WARNING, "gRPC error in pause", e);
            recordCommand("pause", false, System.currentTimeMillis() - startTime);
            return PauseResponse.newBuilder()
                .setSuccess(false)
                .setMessage("gRPC error: " + e.getStatus().getCode())
                .build();
        }
    }
    
    /**
     * Resume playback
     */
    public ResumeResponse resume(String guildId, String userId) {
        long startTime = System.currentTimeMillis();
        
        try {
            ResumeRequest request = ResumeRequest.newBuilder()
                .setGuildId(guildId)
                .setUserId(userId)
                .build();
            
            ResumeResponse response = blockingStub.withDeadlineAfter(timeoutSeconds, TimeUnit.SECONDS)
                .resume(request);
            
            recordCommand("resume", response.getSuccess(), System.currentTimeMillis() - startTime);
            return response;
            
        } catch (StatusRuntimeException e) {
            logger.log(Level.WARNING, "gRPC error in resume", e);
            recordCommand("resume", false, System.currentTimeMillis() - startTime);
            return ResumeResponse.newBuilder()
                .setSuccess(false)
                .setMessage("gRPC error: " + e.getStatus().getCode())
                .build();
        }
    }
    
    /**
     * Stop playback
     */
    public StopResponse stop(String guildId, String userId) {
        long startTime = System.currentTimeMillis();
        
        try {
            StopRequest request = StopRequest.newBuilder()
                .setGuildId(guildId)
                .setUserId(userId)
                .build();
            
            StopResponse response = blockingStub.withDeadlineAfter(timeoutSeconds, TimeUnit.SECONDS)
                .stop(request);
            
            recordCommand("stop", response.getSuccess(), System.currentTimeMillis() - startTime);
            return response;
            
        } catch (StatusRuntimeException e) {
            logger.log(Level.WARNING, "gRPC error in stop", e);
            recordCommand("stop", false, System.currentTimeMillis() - startTime);
            return StopResponse.newBuilder()
                .setSuccess(false)
                .setMessage("gRPC error: " + e.getStatus().getCode())
                .build();
        }
    }
    
    /**
     * Skip current track
     */
    public SkipResponse skip(String guildId, String userId) {
        long startTime = System.currentTimeMillis();
        
        try {
            SkipRequest request = SkipRequest.newBuilder()
                .setGuildId(guildId)
                .setUserId(userId)
                .build();
            
            SkipResponse response = blockingStub.withDeadlineAfter(timeoutSeconds, TimeUnit.SECONDS)
                .skip(request);
            
            recordCommand("skip", response.getSuccess(), System.currentTimeMillis() - startTime);
            
            if (response.getSuccess() && response.hasNextTrack()) {
                logger.info(String.format("⏭️ Skipped to: %s", response.getNextTrack().getTitle()));
            }
            
            return response;
            
        } catch (StatusRuntimeException e) {
            logger.log(Level.WARNING, "gRPC error in skip", e);
            recordCommand("skip", false, System.currentTimeMillis() - startTime);
            return SkipResponse.newBuilder()
                .setSuccess(false)
                .setMessage("gRPC error: " + e.getStatus().getCode())
                .build();
        }
    }
    
    /**
     * Set volume
     */
    public VolumeResponse setVolume(String guildId, String userId, int volume) {
        long startTime = System.currentTimeMillis();
        
        try {
            VolumeRequest request = VolumeRequest.newBuilder()
                .setGuildId(guildId)
                .setUserId(userId)
                .setVolume(volume)
                .build();
            
            VolumeResponse response = blockingStub.withDeadlineAfter(timeoutSeconds, TimeUnit.SECONDS)
                .volume(request);
            
            recordCommand("volume", response.getSuccess(), System.currentTimeMillis() - startTime);
            return response;
            
        } catch (StatusRuntimeException e) {
            logger.log(Level.WARNING, "gRPC error in setVolume", e);
            recordCommand("volume", false, System.currentTimeMillis() - startTime);
            return VolumeResponse.newBuilder()
                .setSuccess(false)
                .setMessage("gRPC error: " + e.getStatus().getCode())
                .build();
        }
    }
    
    /**
     * Get queue
     */
    public QueueResponse getQueue(String guildId, String userId) {
        long startTime = System.currentTimeMillis();
        
        try {
            QueueRequest request = QueueRequest.newBuilder()
                .setGuildId(guildId)
                .setUserId(userId)
                .build();
            
            QueueResponse response = blockingStub.withDeadlineAfter(timeoutSeconds, TimeUnit.SECONDS)
                .getQueue(request);
            
            recordCommand("queue", response.getSuccess(), System.currentTimeMillis() - startTime);
            return response;
            
        } catch (StatusRuntimeException e) {
            logger.log(Level.WARNING, "gRPC error in getQueue", e);
            recordCommand("queue", false, System.currentTimeMillis() - startTime);
            return QueueResponse.newBuilder()
                .setSuccess(false)
                .setMessage("gRPC error: " + e.getStatus().getCode())
                .build();
        }
    }
    
    /**
     * Get status
     */
    public StatusResponse getStatus(String guildId, String userId) {
        long startTime = System.currentTimeMillis();
        
        try {
            StatusRequest request = StatusRequest.newBuilder()
                .setGuildId(guildId)
                .build();
            
            StatusResponse response = blockingStub.withDeadlineAfter(timeoutSeconds, TimeUnit.SECONDS)
                .getStatus(request);
            
            recordCommand("status", response.getSuccess(), System.currentTimeMillis() - startTime);
            return response;
            
        } catch (StatusRuntimeException e) {
            logger.log(Level.WARNING, "gRPC error in getStatus", e);
            recordCommand("status", false, System.currentTimeMillis() - startTime);
            return StatusResponse.newBuilder()
                .setSuccess(false)
                .build();
        }
    }
    
    /**
     * Clear queue
     */
    public ClearQueueResponse clearQueue(String guildId, String userId) {
        long startTime = System.currentTimeMillis();
        
        try {
            ClearQueueRequest request = ClearQueueRequest.newBuilder()
                .setGuildId(guildId)
                .setUserId(userId)
                .build();
            
            ClearQueueResponse response = blockingStub.withDeadlineAfter(timeoutSeconds, TimeUnit.SECONDS)
                .clearQueue(request);
            
            recordCommand("clear_queue", response.getSuccess(), System.currentTimeMillis() - startTime);
            return response;
            
        } catch (StatusRuntimeException e) {
            logger.log(Level.WARNING, "gRPC error in clearQueue", e);
            recordCommand("clear_queue", false, System.currentTimeMillis() - startTime);
            return ClearQueueResponse.newBuilder()
                .setSuccess(false)
                .setMessage("gRPC error: " + e.getStatus().getCode())
                .build();
        }
    }
    
    /**
     * Shuffle queue
     */
    public ShuffleQueueResponse shuffleQueue(String guildId, String userId) {
        long startTime = System.currentTimeMillis();
        
        try {
            ShuffleQueueRequest request = ShuffleQueueRequest.newBuilder()
                .setGuildId(guildId)
                .setUserId(userId)
                .build();
            
            ShuffleQueueResponse response = blockingStub.withDeadlineAfter(timeoutSeconds, TimeUnit.SECONDS)
                .shuffleQueue(request);
            
            recordCommand("shuffle", response.getSuccess(), System.currentTimeMillis() - startTime);
            return response;
            
        } catch (StatusRuntimeException e) {
            logger.log(Level.WARNING, "gRPC error in shuffleQueue", e);
            recordCommand("shuffle", false, System.currentTimeMillis() - startTime);
            return ShuffleQueueResponse.newBuilder()
                .setSuccess(false)
                .setMessage("gRPC error: " + e.getStatus().getCode())
                .build();
        }
    }
    
    /**
     * Apply audio effects
     */
    public EffectsResponse applyEffects(String guildId, String userId, String effectType, 
                                         double intensity, Map<String, String> params) {
        long startTime = System.currentTimeMillis();
        
        try {
            EffectsRequest.Builder requestBuilder = EffectsRequest.newBuilder()
                .setGuildId(guildId)
                .setUserId(userId)
                .setEffectType(effectType)
                .setIntensity(intensity);
            
            if (params != null) {
                requestBuilder.putAllParams(params);
            }
            
            EffectsRequest request = requestBuilder.build();
            EffectsResponse response = blockingStub.withDeadlineAfter(timeoutSeconds, TimeUnit.SECONDS)
                .applyEffects(request);
            
            recordCommand("effects", response.getSuccess(), System.currentTimeMillis() - startTime);
            return response;
            
        } catch (StatusRuntimeException e) {
            logger.log(Level.WARNING, "gRPC error in applyEffects", e);
            recordCommand("effects", false, System.currentTimeMillis() - startTime);
            return EffectsResponse.newBuilder()
                .setSuccess(false)
                .setMessage("gRPC error: " + e.getStatus().getCode())
                .build();
        }
    }
    
    /**
     * Remove track from queue by position
     */
    public RemoveFromQueueResponse removeFromQueue(String guildId, String userId, int position) {
        long startTime = System.currentTimeMillis();
        
        try {
            RemoveFromQueueRequest request = RemoveFromQueueRequest.newBuilder()
                .setGuildId(guildId)
                .setUserId(userId)
                .setPosition(position)
                .build();
            
            RemoveFromQueueResponse response = blockingStub.withDeadlineAfter(timeoutSeconds, TimeUnit.SECONDS)
                .removeFromQueue(request);
            
            recordCommand("remove", response.getSuccess(), System.currentTimeMillis() - startTime);
            return response;
            
        } catch (StatusRuntimeException e) {
            logger.log(Level.WARNING, "gRPC error in removeFromQueue", e);
            recordCommand("remove", false, System.currentTimeMillis() - startTime);
            return RemoveFromQueueResponse.newBuilder()
                .setSuccess(false)
                .setMessage("gRPC error: " + e.getStatus().getCode())
                .build();
        }
    }
    
    /**
     * Move track in queue
     */
    public MoveInQueueResponse moveInQueue(String guildId, String userId, int fromPos, int toPos) {
        long startTime = System.currentTimeMillis();
        
        try {
            MoveInQueueRequest request = MoveInQueueRequest.newBuilder()
                .setGuildId(guildId)
                .setUserId(userId)
                .setFromPosition(fromPos)
                .setToPosition(toPos)
                .build();
            
            MoveInQueueResponse response = blockingStub.withDeadlineAfter(timeoutSeconds, TimeUnit.SECONDS)
                .moveInQueue(request);
            
            recordCommand("move", response.getSuccess(), System.currentTimeMillis() - startTime);
            return response;
            
        } catch (StatusRuntimeException e) {
            logger.log(Level.WARNING, "gRPC error in moveInQueue", e);
            recordCommand("move", false, System.currentTimeMillis() - startTime);
            return MoveInQueueResponse.newBuilder()
                .setSuccess(false)
                .setMessage("gRPC error: " + e.getStatus().getCode())
                .build();
        }
    }
    
    /**
     * Check server health
     */
    public HealthResponse healthCheck() {
        return healthCheck("all");
    }
    
    public HealthResponse healthCheck(String service) {
        long startTime = System.currentTimeMillis();
        
        try {
            HealthRequest request = HealthRequest.newBuilder()
                .setService(service)
                .build();
            
            HealthResponse response = blockingStub.withDeadlineAfter(5, TimeUnit.SECONDS)
                .healthCheck(request);
            
            logger.fine(String.format("Health check: %s - %s", response.getStatus(), response.getMessage()));
            return response;
            
        } catch (StatusRuntimeException e) {
            logger.log(Level.WARNING, "Health check failed", e);
            return HealthResponse.newBuilder()
                .setStatus("unhealthy")
                .setMessage("Connection failed: " + e.getStatus().getCode())
                .setTimestamp(System.currentTimeMillis())
                .build();
        }
    }
    
    /**
     * Record command statistics
     */
    private void recordCommand(String command, boolean success, long durationMs) {
        totalCommands.incrementAndGet();
        if (success) {
            successfulCommands.incrementAndGet();
        } else {
            failedCommands.incrementAndGet();
        }
        
        commandStats.computeIfAbsent(command, k -> new AtomicLong(0))
            .incrementAndGet();
        
        // Log slow commands
        if (durationMs > 5000) {
            logger.warning(String.format("Slow command: %s took %dms", command, durationMs));
        }
    }
    
    /**
     * Get statistics
     */
    public Map<String, Object> getStats() {
        Map<String, Object> stats = new HashMap<>();
        long total = totalCommands.get();
        long success = successfulCommands.get();
        
        stats.put("total_commands", total);
        stats.put("successful_commands", success);
        stats.put("failed_commands", failedCommands.get());
        stats.put("success_rate", total > 0 ? (success * 100.0 / total) : 0);
        stats.put("is_connected", isConnected());
        
        Map<String, Long> commands = new HashMap<>();
        commandStats.forEach((k, v) -> commands.put(k, v.get()));
        stats.put("commands", commands);
        
        return stats;
    }
    
    /**
     * Shutdown the client
     */
    public void shutdown() {
        logger.info("Shutting down gRPC client...");
        if (channel != null) {
            channel.shutdown();
            try {
                if (!channel.awaitTermination(5, TimeUnit.SECONDS)) {
                    channel.shutdownNow();
                }
            } catch (InterruptedException e) {
                channel.shutdownNow();
                Thread.currentThread().interrupt();
            }
        }
        isConnected = false;
        logger.info("gRPC client shutdown complete");
    }
    
    /**
     * Set timeout for requests
     */
    public void setTimeoutSeconds(long seconds) {
        this.timeoutSeconds = seconds;
    }
    
    /**
     * Format track info for display
     */
    public static String formatTrackInfo(TrackInfo track) {
        if (track == null) {
            return "Nothing playing";
        }
        
        String duration = formatDuration(track.getDuration());
        return String.format("**%s** by %s (%s) - requested by <@%s>",
            track.getTitle(),
            track.getArtist().isEmpty() ? "Unknown" : track.getArtist(),
            duration,
            track.getRequester());
    }
    
    /**
     * Format queue as string
     */
    public static String formatQueue(QueueResponse queue) {
        if (!queue.getSuccess()) {
            return "Error: " + queue.getMessage();
        }
        
        if (queue.getTracksCount() == 0 && !queue.hasCurrentTrack()) {
            return "Queue is empty";
        }
        
        StringBuilder sb = new StringBuilder();
        
        // Current track
        if (queue.hasCurrentTrack()) {
            sb.append("🎵 **Currently playing:**\n");
            sb.append("  ").append(formatTrackInfo(queue.getCurrentTrack())).append("\n\n");
        }
        
        // Queue
        if (queue.getTracksCount() > 0) {
            sb.append("📋 **Queue:**\n");
            int maxDisplay = Math.min(queue.getTracksCount(), 10);
            for (int i = 0; i < maxDisplay; i++) {
                TrackInfo track = queue.getTracks(i);
                sb.append(String.format("  %d. %s by %s (%s)\n",
                    i + 1,
                    track.getTitle(),
                    track.getArtist().isEmpty() ? "Unknown" : track.getArtist(),
                    formatDuration(track.getDuration())));
            }
            
            if (queue.getTracksCount() > 10) {
                sb.append(String.format("  ... and %d more tracks\n", queue.getTracksCount() - 10));
            }
            
            sb.append(String.format("\n📊 **Total duration:** %s", formatDuration(queue.getTotalDuration())));
        }
        
        return sb.toString();
    }
    
    /**
     * Format status as string
     */
    public static String formatStatus(StatusResponse status) {
        if (!status.getSuccess()) {
            return "Error getting status";
        }
        
        StringBuilder sb = new StringBuilder();
        sb.append("🎵 **Music Status**\n");
        
        if (status.getPlaying()) {
            sb.append("▶️ **Playing**");
            if (status.getPaused()) {
                sb.append(" (paused)");
            }
            sb.append("\n");
            
            if (status.hasCurrentTrack()) {
                sb.append(formatTrackInfo(status.getCurrentTrack())).append("\n");
                sb.append(String.format("📊 Position: %s / %s\n",
                    formatDuration((int) status.getPositionMs()),
                    formatDuration(status.getCurrentTrack().getDuration())));
            }
        } else {
            sb.append("⏹️ **Stopped**\n");
        }
        
        sb.append(String.format("🔊 Volume: %d%%\n", status.getVolume()));
        sb.append(String.format("📋 Queue length: %d tracks", status.getQueueLength()));
        
        return sb.toString();
    }
    
    /**
     * Format duration in milliseconds to mm:ss
     */
    private static String formatDuration(int durationMs) {
        long seconds = durationMs / 1000;
        long minutes = seconds / 60;
        seconds = seconds % 60;
        return String.format("%d:%02d", minutes, seconds);
    }
}