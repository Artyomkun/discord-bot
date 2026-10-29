package com.bot.grpc.server;

import com.bot.services.RouterService;
import com.bot.grpc.DiscordClientServiceGrpc.DiscordClientServiceImplBase;
import com.bot.grpc.client.DiscordClientProto.CommandRequest;
import com.bot.grpc.client.DiscordClientProto.CommandResponse;

import io.grpc.Server;
import io.grpc.ServerBuilder;
import io.grpc.stub.StreamObserver;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import javax.annotation.PostConstruct;
import javax.annotation.PreDestroy;
import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import java.util.logging.Logger;

@Component
public class server {
    private static final Logger logger = Logger.getLogger(server.class.getName());
    private final int port = 8081;
    private io.grpc.Server grpcServer;
    
    @Autowired
    private RouterService routerService;
    
    @PostConstruct
    public void start() throws IOException {
        grpcServer = ServerBuilder.forPort(port)
                .addService(new DiscordClientService())
                .build()
                .start();
        logger.info("🚀 gRPC сервер запущен на порту " + port);
        
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            try {
                server.this.stop();
            } catch (InterruptedException e) {
                logger.warning("Shutdown interrupted");
            }
        }));
    }
    
    @PreDestroy
    public void stop() throws InterruptedException {
        if (grpcServer != null) {
            grpcServer.shutdown().awaitTermination(30, TimeUnit.SECONDS);
            logger.info("🛑 gRPC сервер остановлен");
        }
    }
    
    private class DiscordClientService extends DiscordClientServiceGrpc.DiscordClientServiceImplBase {
        
        @Override
        public void sendCommand(CommandRequest request, StreamObserver<CommandResponse> responseObserver) {
            logger.info("📥 gRPC команда: " + request.getCommand() + " от " + request.getUserId());
            
            Map<String, Object> params = new HashMap<>();
            params.put("url", request.getUrl());
            params.put("user_id", request.getUserId());
            params.put("guild_id", request.getGuildId());
            params.put("channel_id", request.getChannelId());
            params.putAll(request.getOptionsMap());
            
            routerService.routeCommand(request.getCommand(), request.getUserId(), params)
                .subscribe(
                    data -> {
                        Map<String, String> dataMap = new HashMap<>();
                        data.forEach((k, v) -> dataMap.put(k, String.valueOf(v)));
                        
                        CommandResponse response = CommandResponse.newBuilder()
                            .setSuccess(Boolean.parseBoolean(data.getOrDefault("success", true).toString()))
                            .setMessage(data.getOrDefault("message", "OK").toString())
                            .putAllData(dataMap)
                            .build();
                        responseObserver.onNext(response);
                        responseObserver.onCompleted();
                    },
                    error -> {
                        logger.severe("Error: " + error.getMessage());
                        CommandResponse errorResponse = CommandResponse.newBuilder()
                            .setSuccess(false)
                            .setMessage("Error: " + error.getMessage())
                            .build();
                        responseObserver.onNext(errorResponse);
                        responseObserver.onCompleted();
                    }
                );
        }
        
        @Override
        public void getStatus(StatusRequest request, StreamObserver<StatusResponse> responseObserver) {
            logger.info("📊 gRPC запрос статуса для guild " + request.getGuildId());
            
            routerService.getStatus(request.getGuildId()).subscribe(
                status -> {
                    StatusResponse response = StatusResponse.newBuilder()
                        .setSuccess(true)
                        .setPlaying(Boolean.parseBoolean(status.getOrDefault("playing", false).toString()))
                        .setCurrentTrack(status.getOrDefault("current_track", "").toString())
                        .setVolume(Integer.parseInt(status.getOrDefault("volume", 50).toString()))
                        .setQueueLength(Integer.parseInt(status.getOrDefault("queue_length", 0).toString()))
                        .build();
                    responseObserver.onNext(response);
                    responseObserver.onCompleted();
                },
                error -> {
                    logger.severe("Error getting status: " + error.getMessage());
                    StatusResponse errorResponse = StatusResponse.newBuilder()
                        .setSuccess(false)
                        .build();
                    responseObserver.onNext(errorResponse);
                    responseObserver.onCompleted();
                }
            );
        }
        
        @Override
        public void play(PlayRequest request, StreamObserver<PlayResponse> responseObserver) {
            logger.info("🎵 gRPC воспроизведение: " + request.getUrl() + " в канале " + request.getVoiceChannelId());
            
            Map<String, Object> params = new HashMap<>();
            params.put("url", request.getUrl());
            params.put("user_id", request.getUserId());
            params.put("guild_id", request.getGuildId());
            params.put("voice_channel_id", request.getVoiceChannelId());
            params.putAll(request.getOptionsMap());
            
            routerService.routeCommand("play", request.getUserId(), params)
                .subscribe(
                    data -> {
                        PlayResponse response = PlayResponse.newBuilder()
                            .setSuccess(true)
                            .setMessage(data.getOrDefault("message", "Playing").toString())
                            .build();
                        responseObserver.onNext(response);
                        responseObserver.onCompleted();
                    },
                    error -> {
                        logger.severe("Error playing: " + error.getMessage());
                        PlayResponse errorResponse = PlayResponse.newBuilder()
                            .setSuccess(false)
                            .setMessage("Error: " + error.getMessage())
                            .build();
                        responseObserver.onNext(errorResponse);
                        responseObserver.onCompleted();
                    }
                );
        }
        
        @Override
        public void pause(PauseRequest request, StreamObserver<PauseResponse> responseObserver) {
            logger.info("⏸️ gRPC пауза для guild " + request.getGuildId());
            
            Map<String, Object> params = new HashMap<>();
            params.put("guild_id", request.getGuildId());
            params.put("user_id", request.getUserId());
            
            routerService.routeCommand("pause", request.getUserId(), params)
                .subscribe(
                    data -> {
                        PauseResponse response = PauseResponse.newBuilder()
                            .setSuccess(true)
                            .setMessage("Paused")
                            .build();
                        responseObserver.onNext(response);
                        responseObserver.onCompleted();
                    },
                    error -> {
                        PauseResponse errorResponse = PauseResponse.newBuilder()
                            .setSuccess(false)
                            .setMessage("Error: " + error.getMessage())
                            .build();
                        responseObserver.onNext(errorResponse);
                        responseObserver.onCompleted();
                    }
                );
        }
        
        @Override
        public void resume(ResumeRequest request, StreamObserver<ResumeResponse> responseObserver) {
            logger.info("▶️ gRPC возобновление для guild " + request.getGuildId());
            
            Map<String, Object> params = new HashMap<>();
            params.put("guild_id", request.getGuildId());
            params.put("user_id", request.getUserId());
            
            routerService.routeCommand("resume", request.getUserId(), params)
                .subscribe(
                    data -> {
                        ResumeResponse response = ResumeResponse.newBuilder()
                            .setSuccess(true)
                            .setMessage("Resumed")
                            .build();
                        responseObserver.onNext(response);
                        responseObserver.onCompleted();
                    },
                    error -> {
                        ResumeResponse errorResponse = ResumeResponse.newBuilder()
                            .setSuccess(false)
                            .setMessage("Error: " + error.getMessage())
                            .build();
                        responseObserver.onNext(errorResponse);
                        responseObserver.onCompleted();
                    }
                );
        }
        
        @Override
        public void stop(StopRequest request, StreamObserver<StopResponse> responseObserver) {
            logger.info("⏹️ gRPC остановка для guild " + request.getGuildId());
            
            Map<String, Object> params = new HashMap<>();
            params.put("guild_id", request.getGuildId());
            params.put("user_id", request.getUserId());
            
            routerService.routeCommand("stop", request.getUserId(), params)
                .subscribe(
                    data -> {
                        StopResponse response = StopResponse.newBuilder()
                            .setSuccess(true)
                            .setMessage("Stopped")
                            .build();
                        responseObserver.onNext(response);
                        responseObserver.onCompleted();
                    },
                    error -> {
                        StopResponse errorResponse = StopResponse.newBuilder()
                            .setSuccess(false)
                            .setMessage("Error: " + error.getMessage())
                            .build();
                        responseObserver.onNext(errorResponse);
                        responseObserver.onCompleted();
                    }
                );
        }
        
        @Override
        public void skip(SkipRequest request, StreamObserver<SkipResponse> responseObserver) {
            logger.info("⏭️ gRPC пропуск для guild " + request.getGuildId());
            
            Map<String, Object> params = new HashMap<>();
            params.put("guild_id", request.getGuildId());
            params.put("user_id", request.getUserId());
            
            routerService.routeCommand("skip", request.getUserId(), params)
                .subscribe(
                    data -> {
                        SkipResponse response = SkipResponse.newBuilder()
                            .setSuccess(true)
                            .setMessage("Skipped")
                            .build();
                        responseObserver.onNext(response);
                        responseObserver.onCompleted();
                    },
                    error -> {
                        SkipResponse errorResponse = SkipResponse.newBuilder()
                            .setSuccess(false)
                            .setMessage("Error: " + error.getMessage())
                            .build();
                        responseObserver.onNext(errorResponse);
                        responseObserver.onCompleted();
                    }
                );
        }
        
        @Override
        public void volume(VolumeRequest request, StreamObserver<VolumeResponse> responseObserver) {
            int volume = request.getVolume();
            logger.info("🔊 gRPC громкость: " + volume + "% для guild " + request.getGuildId());
            
            Map<String, Object> params = new HashMap<>();
            params.put("guild_id", request.getGuildId());
            params.put("user_id", request.getUserId());
            params.put("volume", volume);
            
            routerService.routeCommand("volume", request.getUserId(), params)
                .subscribe(
                    data -> {
                        VolumeResponse response = VolumeResponse.newBuilder()
                            .setSuccess(true)
                            .setMessage("Volume set to " + volume + "%")
                            .setVolume(volume)
                            .build();
                        responseObserver.onNext(response);
                        responseObserver.onCompleted();
                    },
                    error -> {
                        VolumeResponse errorResponse = VolumeResponse.newBuilder()
                            .setSuccess(false)
                            .setMessage("Error: " + error.getMessage())
                            .setVolume(volume)
                            .build();
                        responseObserver.onNext(errorResponse);
                        responseObserver.onCompleted();
                    }
                );
        }
        
        @Override
        public void getQueue(QueueRequest request, StreamObserver<QueueResponse> responseObserver) {
            logger.info("📋 gRPC запрос очереди для guild " + request.getGuildId());
            
            Map<String, Object> params = new HashMap<>();
            params.put("guild_id", request.getGuildId());
            params.put("user_id", request.getUserId());
            
            routerService.routeCommand("queue", request.getUserId(), params)
                .subscribe(
                    data -> {
                        QueueResponse.Builder builder = QueueResponse.newBuilder()
                            .setSuccess(true);
                        
                        // Добавляем треки из ответа
                        // Здесь нужно распарсить data и добавить в builder
                        
                        responseObserver.onNext(builder.build());
                        responseObserver.onCompleted();
                    },
                    error -> {
                        QueueResponse errorResponse = QueueResponse.newBuilder()
                            .setSuccess(false)
                            .setMessage("Error: " + error.getMessage())
                            .build();
                        responseObserver.onNext(errorResponse);
                        responseObserver.onCompleted();
                    }
                );
        }
        
        @Override
        public void applyEffects(EffectsRequest request, StreamObserver<EffectsResponse> responseObserver) {
            logger.info("🎚️ gRPC эффект: " + request.getEffectType() + " для пользователя " + request.getUserId());
            
            Map<String, Object> params = new HashMap<>();
            params.put("guild_id", request.getGuildId());
            params.put("user_id", request.getUserId());
            params.put("effect_type", request.getEffectType());
            params.put("intensity", request.getIntensity());
            params.putAll(request.getParamsMap());
            
            routerService.routeCommand("effects", request.getUserId(), params)
                .subscribe(
                    data -> {
                        EffectsResponse response = EffectsResponse.newBuilder()
                            .setSuccess(true)
                            .setMessage(data.getOrDefault("message", "Effect applied").toString())
                            .addAppliedEffects(request.getEffectType())
                            .build();
                        responseObserver.onNext(response);
                        responseObserver.onCompleted();
                    },
                    error -> {
                        EffectsResponse errorResponse = EffectsResponse.newBuilder()
                            .setSuccess(false)
                            .setMessage("Error: " + error.getMessage())
                            .build();
                        responseObserver.onNext(errorResponse);
                        responseObserver.onCompleted();
                    }
                );
        }
        
        @Override
        public void healthCheck(HealthRequest request, StreamObserver<HealthResponse> responseObserver) {
            logger.info("❤️ gRPC health check");
            
            HealthResponse response = HealthResponse.newBuilder()
                .setStatus("healthy")
                .setMessage("Java Gateway is running")
                .setTimestamp(System.currentTimeMillis())
                .build();
            responseObserver.onNext(response);
            responseObserver.onCompleted();
        }
    }
}