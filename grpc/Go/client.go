package main

import (
	"context"
	"log"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	pb "goclient" // путь к сгенерированному пакету client
)

// GoClient — клиент для отправки команд в Java Gateway и другие сервисы
type GoClient struct {
	javaGatewayConn   *grpc.ClientConn
	elixirGatewayConn *grpc.ClientConn
	javaStub          pb.GoClientClient
	elixirStub        pb.GoClientClient
}

// NewGoClient создаёт новый клиент
func NewGoClient(javaGatewayAddr, elixirGatewayAddr string) (*GoClient, error) {
	// Подключение к Java Gateway
	javaConn, err := grpc.NewClient(javaGatewayAddr, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return nil, err
	}
	
	// Подключение к Elixir Gateway
	elixirConn, err := grpc.NewClient(elixirGatewayAddr, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		javaConn.Close()
		return nil, err
	}
	
	return &GoClient{
		javaGatewayConn:   javaConn,
		elixirGatewayConn: elixirConn,
		javaStub:          pb.NewGoClientClient(javaConn),
		elixirStub:        pb.NewGoClientClient(elixirConn),
	}, nil
}

// Close закрывает все соединения
func (c *GoClient) Close() {
	if c.javaGatewayConn != nil {
		c.javaGatewayConn.Close()
	}
	if c.elixirGatewayConn != nil {
		c.elixirGatewayConn.Close()
	}
}

// ========== Методы для отправки команд ==========

// SendCommandToJava отправляет команду в Java Gateway
func (c *GoClient) SendCommandToJava(ctx context.Context, command, userID, guildID, channelID string, options map[string]string) (*pb.CommandResponse, error) {
	req := &pb.CommandRequest{
		Command:   command,
		UserId:    userID,
		GuildId:   guildID,
		ChannelId: channelID,
		Options:   options,
	}
	
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	
	return c.javaStub.SendCommand(ctx, req)
}

// SendCommandToElixir отправляет команду в Elixir Gateway
func (c *GoClient) SendCommandToElixir(ctx context.Context, command, userID, guildID, channelID string, options map[string]string) (*pb.CommandResponse, error) {
	req := &pb.CommandRequest{
		Command:   command,
		UserId:    userID,
		GuildId:   guildID,
		ChannelId: channelID,
		Options:   options,
	}
	
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	
	return c.elixirStub.SendCommand(ctx, req)
}

// ========== Методы для управления воспроизведением ==========

// Play отправляет команду воспроизведения
func (c *GoClient) Play(ctx context.Context, guildID, userID, query, voiceChannelID string, options map[string]string) (*pb.PlayResponse, error) {
	req := &pb.PlayRequest{
		GuildId:        guildID,
		UserId:         userID,
		Query:          query,
		VoiceChannelId: voiceChannelID,
		Options:        options,
	}
	
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	
	return c.javaStub.Play(ctx, req)
}

func (c *GoClient) Search(ctx context.Context, req *pb.SearchRequest) (*pb.SearchResponse, error) {
	log.Printf("🔍 Search: query=%s, platform=%s", req.Query, req.Platform)
	
	// В реальном проекте здесь был бы поиск через YouTube/Spotify/etc
	return &pb.SearchResponse{
		Success:  true,
		Results:  []*pb.TrackInfo{},
		Platform: req.Platform,
	}, nil
}

// Stop отправляет команду остановки
func (c *GoClient) Stop(ctx context.Context, guildID, userID string) (*pb.StopResponse, error) {
	req := &pb.StopRequest{
		GuildId: guildID,
		UserId:  userID,
	}
	
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	
	return c.javaStub.Stop(ctx, req)
}

// Pause отправляет команду паузы
func (c *GoClient) Pause(ctx context.Context, guildID, userID string) (*pb.PauseResponse, error) {
	req := &pb.PauseRequest{
		GuildId: guildID,
		UserId:  userID,
	}
	
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	
	return c.javaStub.Pause(ctx, req)
}

// Resume отправляет команду возобновления
func (c *GoClient) Resume(ctx context.Context, guildID, userID string) (*pb.ResumeResponse, error) {
	req := &pb.ResumeRequest{
		GuildId: guildID,
		UserId:  userID,
	}
	
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	
	return c.javaStub.Resume(ctx, req)
}

// Skip отправляет команду пропуска
func (c *GoClient) Skip(ctx context.Context, guildID, userID string, count int32) (*pb.SkipResponse, error) {
	req := &pb.SkipRequest{
		GuildId: guildID,
		UserId:  userID,
		Count:   count,
	}
	
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	
	return c.javaStub.Skip(ctx, req)
}

// Seek отправляет команду перемотки
func (c *GoClient) Seek(ctx context.Context, guildID, userID string, positionMs int32) (*pb.SeekResponse, error) {
	req := &pb.SeekRequest{
		GuildId:    guildID,
		UserId:     userID,
		PositionMs: positionMs,
	}
	
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	
	return c.javaStub.Seek(ctx, req)
}

// SetVolume отправляет команду изменения громкости
func (c *GoClient) SetVolume(ctx context.Context, guildID, userID string, volume int32) (*pb.VolumeResponse, error) {
	req := &pb.VolumeRequest{
		GuildId: guildID,
		UserId:  userID,
		Volume:  volume,
	}
	
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	
	return c.javaStub.SetVolume(ctx, req)
}

// ========== Методы для очереди ==========

// GetQueue получает очередь
func (c *GoClient) GetQueue(ctx context.Context, guildID, userID string, limit, offset int32) (*pb.QueueResponse, error) {
	req := &pb.QueueRequest{
		GuildId: guildID,
		UserId:  userID,
		Limit:   limit,
		Offset:  offset,
	}
	
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	
	return c.javaStub.GetQueue(ctx, req)
}

// AddToQueue добавляет трек в очередь
func (c *GoClient) AddToQueue(ctx context.Context, guildID, userID, query string, position int32) (*pb.AddToQueueResponse, error) {
	req := &pb.AddToQueueRequest{
		GuildId:  guildID,
		UserId:   userID,
		Query:    query,
		Position: position,
	}
	
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	
	return c.javaStub.AddToQueue(ctx, req)
}

// RemoveFromQueue удаляет трек из очереди
func (c *GoClient) RemoveFromQueue(ctx context.Context, guildID, userID string, position int32) (*pb.RemoveFromQueueResponse, error) {
	req := &pb.RemoveFromQueueRequest{
		GuildId:  guildID,
		UserId:   userID,
		Position: position,
	}
	
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	
	return c.javaStub.RemoveFromQueue(ctx, req)
}

// ClearQueue очищает очередь
func (c *GoClient) ClearQueue(ctx context.Context, guildID, userID string) (*pb.ClearQueueResponse, error) {
	req := &pb.ClearQueueRequest{
		GuildId: guildID,
		UserId:  userID,
	}
	
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	
	return c.javaStub.ClearQueue(ctx, req)
}

// ShuffleQueue перемешивает очередь
func (c *GoClient) ShuffleQueue(ctx context.Context, guildID, userID string) (*pb.ShuffleQueueResponse, error) {
	req := &pb.ShuffleQueueRequest{
		GuildId: guildID,
		UserId:  userID,
	}
	
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	
	return c.javaStub.ShuffleQueue(ctx, req)
}

// ========== Методы для эффектов ==========

// ApplyEffects применяет эффекты
func (c *GoClient) ApplyEffects(ctx context.Context, guildID, userID, effectType string, intensity float64, params map[string]string) (*pb.EffectsResponse, error) {
	req := &pb.EffectsRequest{
		GuildId:    guildID,
		UserId:     userID,
		EffectType: effectType,
		Intensity:  intensity,
		Params:     params,
	}
	
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	
	return c.javaStub.ApplyEffects(ctx, req)
}

// GetEffects получает активные эффекты
func (c *GoClient) GetEffects(ctx context.Context, guildID, userID string) (*pb.GetEffectsResponse, error) {
	req := &pb.GetEffectsRequest{
		GuildId: guildID,
		UserId:  userID,
	}
	
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	
	return c.javaStub.GetEffects(ctx, req)
}

// ResetEffects сбрасывает эффекты
func (c *GoClient) ResetEffects(ctx context.Context, guildID, userID string) (*pb.ResetEffectsResponse, error) {
	req := &pb.ResetEffectsRequest{
		GuildId: guildID,
		UserId:  userID,
	}
	
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	
	return c.javaStub.ResetEffects(ctx, req)
}

// ========== Статус ==========

// GetStatus получает статус
func (c *GoClient) GetStatus(ctx context.Context, guildID, userID string) (*pb.StatusResponse, error) {
	req := &pb.StatusRequest{
		GuildId: guildID,
		UserId:  userID,
	}
	
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	
	return c.javaStub.GetStatus(ctx, req)
}

// HealthCheck проверяет здоровье сервиса
func (c *GoClient) HealthCheck(ctx context.Context, service string) (*pb.HealthResponse, error) {
	req := &pb.HealthRequest{
		Service: service,
	}
	
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	
	return c.javaStub.HealthCheck(ctx, req)
}