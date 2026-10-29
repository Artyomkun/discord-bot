package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	pb "goclient" // путь к сгенерированному пакету client
)

// ClientProtocol — протокол для работы с gRPC клиентом
type ClientProtocol struct {
	mu               sync.RWMutex
	conn             *grpc.ClientConn
	stub             pb.GoClientClient
	address          string
	connected        bool
	reconnectAttempt int
	maxReconnect     int
	metrics          *ClientProtocolMetrics
}

// ClientProtocolMetrics — метрики клиента
type ClientProtocolMetrics struct {
	TotalCalls      int64
	SuccessfulCalls int64
	FailedCalls     int64
	TotalDuration   time.Duration
	AvgDuration     time.Duration
	Reconnects      int64
	mu              sync.RWMutex
}

// ClientProtocolConfig — конфигурация клиента
type ClientProtocolConfig struct {
	Address        string
	MaxReconnect   int
	ReconnectDelay time.Duration
	Timeout        time.Duration
}

// DefaultClientConfig — конфигурация по умолчанию
func DefaultClientConfig() *ClientProtocolConfig {
	return &ClientProtocolConfig{
		Address:        "localhost:50052",
		MaxReconnect:   5,
		ReconnectDelay: 2 * time.Second,
		Timeout:        10 * time.Second,
	}
}

// NewClientProtocol создаёт новый клиентский протокол
func NewClientProtocol(config *ClientProtocolConfig) (*ClientProtocol, error) {
	if config == nil {
		config = DefaultClientConfig()
	}

	client := &ClientProtocol{
		address:      config.Address,
		maxReconnect: config.MaxReconnect,
		metrics:      &ClientProtocolMetrics{},
	}

	if err := client.connect(); err != nil {
		return nil, err
	}

	return client, nil
}

// connect устанавливает соединение с сервером
func (c *ClientProtocol) connect() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.conn != nil {
		c.conn.Close()
	}

	conn, err := grpc.NewClient(c.address, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return fmt.Errorf("failed to connect: %v", err)
	}

	c.conn = conn
	c.stub = pb.NewGoClientClient(conn)
	c.connected = true
	c.reconnectAttempt = 0

	log.Printf("✅ Connected to gRPC server at %s", c.address)
	return nil
}

// reconnect пытается переподключиться
func (c *ClientProtocol) reconnect() error {
	c.mu.Lock()
	attempt := c.reconnectAttempt + 1
	c.mu.Unlock()

	if attempt > c.maxReconnect {
		return fmt.Errorf("max reconnect attempts (%d) reached", c.maxReconnect)
	}

	delay := time.Duration(attempt) * 2 * time.Second
	log.Printf("🔄 Reconnecting to %s (attempt %d/%d) in %v",
		c.address, attempt, c.maxReconnect, delay)

	time.Sleep(delay)

	c.mu.Lock()
	c.reconnectAttempt = attempt
	c.mu.Unlock()

	if err := c.connect(); err != nil {
		return err
	}

	atomic.AddInt64(&c.metrics.Reconnects, 1)
	return nil
}

// ensureConnected проверяет соединение и переподключает при необходимости
func (c *ClientProtocol) ensureConnected() error {
	c.mu.RLock()
	connected := c.connected
	c.mu.RUnlock()

	if connected {
		return nil
	}

	return c.reconnect()
}

// Call выполняет gRPC вызов с автоматическим переподключением
func (c *ClientProtocol) Call(ctx context.Context, fn func(pb.GoClientClient) error) error {
	start := time.Now()

	if err := c.ensureConnected(); err != nil {
		c.recordCall(false, time.Since(start))
		return err
	}

	c.mu.RLock()
	stub := c.stub
	c.mu.RUnlock()

	err := fn(stub)

	if err != nil {
		// Если ошибка связана с соединением — пробуем переподключиться
		if isConnectionError(err) {
			log.Printf("⚠️ Connection error: %v, attempting reconnect", err)
			if reconnectErr := c.reconnect(); reconnectErr == nil {
				c.mu.RLock()
				stub = c.stub
				c.mu.RUnlock()
				err = fn(stub)
			}
		}
	}

	c.recordCall(err == nil, time.Since(start))
	return err
}

// recordCall записывает метрики вызова
func (c *ClientProtocol) recordCall(success bool, duration time.Duration) {
	atomic.AddInt64(&c.metrics.TotalCalls, 1)
	if success {
		atomic.AddInt64(&c.metrics.SuccessfulCalls, 1)
	} else {
		atomic.AddInt64(&c.metrics.FailedCalls, 1)
	}

	c.metrics.mu.Lock()
	c.metrics.TotalDuration += duration
	processed := atomic.LoadInt64(&c.metrics.SuccessfulCalls) + atomic.LoadInt64(&c.metrics.FailedCalls)
	if processed > 0 {
		c.metrics.AvgDuration = c.metrics.TotalDuration / time.Duration(processed)
	}
	c.metrics.mu.Unlock()
}

// isConnectionError проверяет, является ли ошибка ошибкой соединения
func isConnectionError(err error) bool {
	if err == nil {
		return false
	}
	errStr := err.Error()
	return strings.Contains(errStr, "connection") ||
		strings.Contains(errStr, "unavailable") ||
		strings.Contains(errStr, "deadline") ||
		strings.Contains(errStr, "timeout")
}

// ========== Методы для отправки команд ==========

// SendCommand отправляет команду в Java Gateway
func (c *ClientProtocol) SendCommand(ctx context.Context, command, userID, guildID, channelID string, options map[string]string) (*pb.CommandResponse, error) {
	req := &pb.CommandRequest{
		Command:   command,
		UserId:    userID,
		GuildId:   guildID,
		ChannelId: channelID,
		Options:   options,
	}

	var resp *pb.CommandResponse
	err := c.Call(ctx, func(stub pb.GoClientClient) error {
		var callErr error
		resp, callErr = stub.SendCommand(ctx, req)
		return callErr
	})

	return resp, err
}

// Play отправляет команду воспроизведения
func (c *ClientProtocol) Play(ctx context.Context, guildID, userID, query, voiceChannelID string, options map[string]string) (*pb.PlayResponse, error) {
	req := &pb.PlayRequest{
		GuildId:        guildID,
		UserId:         userID,
		Query:          query,
		VoiceChannelId: voiceChannelID,
		Options:        options,
	}

	var resp *pb.PlayResponse
	err := c.Call(ctx, func(stub pb.GoClientClient) error {
		var callErr error
		resp, callErr = stub.Play(ctx, req)
		return callErr
	})

	return resp, err
}

// Stop отправляет команду остановки
func (c *ClientProtocol) Stop(ctx context.Context, guildID, userID string) (*pb.StopResponse, error) {
	req := &pb.StopRequest{
		GuildId: guildID,
		UserId:  userID,
	}

	var resp *pb.StopResponse
	err := c.Call(ctx, func(stub pb.GoClientClient) error {
		var callErr error
		resp, callErr = stub.Stop(ctx, req)
		return callErr
	})

	return resp, err
}

// Pause отправляет команду паузы
func (c *ClientProtocol) Pause(ctx context.Context, guildID, userID string) (*pb.PauseResponse, error) {
	req := &pb.PauseRequest{
		GuildId: guildID,
		UserId:  userID,
	}

	var resp *pb.PauseResponse
	err := c.Call(ctx, func(stub pb.GoClientClient) error {
		var callErr error
		resp, callErr = stub.Pause(ctx, req)
		return callErr
	})

	return resp, err
}

// Resume отправляет команду возобновления
func (c *ClientProtocol) Resume(ctx context.Context, guildID, userID string) (*pb.ResumeResponse, error) {
	req := &pb.ResumeRequest{
		GuildId: guildID,
		UserId:  userID,
	}

	var resp *pb.ResumeResponse
	err := c.Call(ctx, func(stub pb.GoClientClient) error {
		var callErr error
		resp, callErr = stub.Resume(ctx, req)
		return callErr
	})

	return resp, err
}

// Skip отправляет команду пропуска
func (c *ClientProtocol) Skip(ctx context.Context, guildID, userID string, count int32) (*pb.SkipResponse, error) {
	req := &pb.SkipRequest{
		GuildId: guildID,
		UserId:  userID,
		Count:   count,
	}

	var resp *pb.SkipResponse
	err := c.Call(ctx, func(stub pb.GoClientClient) error {
		var callErr error
		resp, callErr = stub.Skip(ctx, req)
		return callErr
	})

	return resp, err
}

// Seek отправляет команду перемотки
func (c *ClientProtocol) Seek(ctx context.Context, guildID, userID string, positionMs int32) (*pb.SeekResponse, error) {
	req := &pb.SeekRequest{
		GuildId:    guildID,
		UserId:     userID,
		PositionMs: positionMs,
	}

	var resp *pb.SeekResponse
	err := c.Call(ctx, func(stub pb.GoClientClient) error {
		var callErr error
		resp, callErr = stub.Seek(ctx, req)
		return callErr
	})

	return resp, err
}

// SetVolume отправляет команду изменения громкости
func (c *ClientProtocol) SetVolume(ctx context.Context, guildID, userID string, volume int32) (*pb.VolumeResponse, error) {
	req := &pb.VolumeRequest{
		GuildId: guildID,
		UserId:  userID,
		Volume:  volume,
	}

	var resp *pb.VolumeResponse
	err := c.Call(ctx, func(stub pb.GoClientClient) error {
		var callErr error
		resp, callErr = stub.SetVolume(ctx, req)
		return callErr
	})

	return resp, err
}

// ========== Методы для очереди ==========

// GetQueue получает очередь
func (c *ClientProtocol) GetQueue(ctx context.Context, guildID, userID string, limit, offset int32) (*pb.QueueResponse, error) {
	req := &pb.QueueRequest{
		GuildId: guildID,
		UserId:  userID,
		Limit:   limit,
		Offset:  offset,
	}

	var resp *pb.QueueResponse
	err := c.Call(ctx, func(stub pb.GoClientClient) error {
		var callErr error
		resp, callErr = stub.GetQueue(ctx, req)
		return callErr
	})

	return resp, err
}

// AddToQueue добавляет трек в очередь
func (c *ClientProtocol) AddToQueue(ctx context.Context, guildID, userID, query string, position int32) (*pb.AddToQueueResponse, error) {
	req := &pb.AddToQueueRequest{
		GuildId:  guildID,
		UserId:   userID,
		Query:    query,
		Position: position,
	}

	var resp *pb.AddToQueueResponse
	err := c.Call(ctx, func(stub pb.GoClientClient) error {
		var callErr error
		resp, callErr = stub.AddToQueue(ctx, req)
		return callErr
	})

	return resp, err
}

// RemoveFromQueue удаляет трек из очереди
func (c *ClientProtocol) RemoveFromQueue(ctx context.Context, guildID, userID string, position int32) (*pb.RemoveFromQueueResponse, error) {
	req := &pb.RemoveFromQueueRequest{
		GuildId:  guildID,
		UserId:   userID,
		Position: position,
	}

	var resp *pb.RemoveFromQueueResponse
	err := c.Call(ctx, func(stub pb.GoClientClient) error {
		var callErr error
		resp, callErr = stub.RemoveFromQueue(ctx, req)
		return callErr
	})

	return resp, err
}

// ClearQueue очищает очередь
func (c *ClientProtocol) ClearQueue(ctx context.Context, guildID, userID string) (*pb.ClearQueueResponse, error) {
	req := &pb.ClearQueueRequest{
		GuildId: guildID,
		UserId:  userID,
	}

	var resp *pb.ClearQueueResponse
	err := c.Call(ctx, func(stub pb.GoClientClient) error {
		var callErr error
		resp, callErr = stub.ClearQueue(ctx, req)
		return callErr
	})

	return resp, err
}

// ShuffleQueue перемешивает очередь
func (c *ClientProtocol) ShuffleQueue(ctx context.Context, guildID, userID string) (*pb.ShuffleQueueResponse, error) {
	req := &pb.ShuffleQueueRequest{
		GuildId: guildID,
		UserId:  userID,
	}

	var resp *pb.ShuffleQueueResponse
	err := c.Call(ctx, func(stub pb.GoClientClient) error {
		var callErr error
		resp, callErr = stub.ShuffleQueue(ctx, req)
		return callErr
	})

	return resp, err
}

// ========== Методы для эффектов ==========

// ApplyEffects применяет эффекты
func (c *ClientProtocol) ApplyEffects(ctx context.Context, guildID, userID, effectType string, intensity float64, params map[string]string) (*pb.EffectsResponse, error) {
	req := &pb.EffectsRequest{
		GuildId:    guildID,
		UserId:     userID,
		EffectType: effectType,
		Intensity:  intensity,
		Params:     params,
	}

	var resp *pb.EffectsResponse
	err := c.Call(ctx, func(stub pb.GoClientClient) error {
		var callErr error
		resp, callErr = stub.ApplyEffects(ctx, req)
		return callErr
	})

	return resp, err
}

// GetEffects получает активные эффекты
func (c *ClientProtocol) GetEffects(ctx context.Context, guildID, userID string) (*pb.GetEffectsResponse, error) {
	req := &pb.GetEffectsRequest{
		GuildId: guildID,
		UserId:  userID,
	}

	var resp *pb.GetEffectsResponse
	err := c.Call(ctx, func(stub pb.GoClientClient) error {
		var callErr error
		resp, callErr = stub.GetEffects(ctx, req)
		return callErr
	})

	return resp, err
}

// ResetEffects сбрасывает эффекты
func (c *ClientProtocol) ResetEffects(ctx context.Context, guildID, userID string) (*pb.ResetEffectsResponse, error) {
	req := &pb.ResetEffectsRequest{
		GuildId: guildID,
		UserId:  userID,
	}

	var resp *pb.ResetEffectsResponse
	err := c.Call(ctx, func(stub pb.GoClientClient) error {
		var callErr error
		resp, callErr = stub.ResetEffects(ctx, req)
		return callErr
	})

	return resp, err
}

// ========== Статус ==========

// GetStatus получает статус
func (c *ClientProtocol) GetStatus(ctx context.Context, guildID, userID string) (*pb.StatusResponse, error) {
	req := &pb.StatusRequest{
		GuildId: guildID,
		UserId:  userID,
	}

	var resp *pb.StatusResponse
	err := c.Call(ctx, func(stub pb.GoClientClient) error {
		var callErr error
		resp, callErr = stub.GetStatus(ctx, req)
		return callErr
	})

	return resp, err
}

// HealthCheck проверяет здоровье сервиса
func (c *ClientProtocol) HealthCheck(ctx context.Context, service string) (*pb.HealthResponse, error) {
	req := &pb.HealthRequest{
		Service: service,
	}

	var resp *pb.HealthResponse
	err := c.Call(ctx, func(stub pb.GoClientClient) error {
		var callErr error
		resp, callErr = stub.HealthCheck(ctx, req)
		return callErr
	})

	return resp, err
}

// ========== Метрики ==========

// GetMetrics возвращает метрики клиента
func (c *ClientProtocol) GetMetrics() *ClientProtocolMetrics {
	c.metrics.mu.RLock()
	defer c.metrics.mu.RUnlock()

	return &ClientProtocolMetrics{
		TotalCalls:      atomic.LoadInt64(&c.metrics.TotalCalls),
		SuccessfulCalls: atomic.LoadInt64(&c.metrics.SuccessfulCalls),
		FailedCalls:     atomic.LoadInt64(&c.metrics.FailedCalls),
		TotalDuration:   c.metrics.TotalDuration,
		AvgDuration:     c.metrics.AvgDuration,
		Reconnects:      atomic.LoadInt64(&c.metrics.Reconnects),
	}
}

// GetMetricsJSON возвращает метрики в JSON
func (c *ClientProtocol) GetMetricsJSON() ([]byte, error) {
	metrics := c.GetMetrics()
	return json.MarshalIndent(metrics, "", "  ")
}

// Close закрывает соединение
func (c *ClientProtocol) Close() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.conn != nil {
		log.Printf("🔌 Closing connection to %s", c.address)
		return c.conn.Close()
	}
	return nil
}