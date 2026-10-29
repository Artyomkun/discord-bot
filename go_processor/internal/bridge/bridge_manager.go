package bridge

import (
	"context"
	"fmt"
	"sync"
	"time"
)

// BridgeManager управляет всеми мостами
type BridgeManager struct {
	javaBridge   *JavaBridge
	elixirBridge *ElixirBridge
	status       map[string]bool
	mu           sync.RWMutex
	stats        *BridgeStats
}

// BridgeStats статистика мостов
type BridgeStats struct {
	JavaRequests     int64         `json:"java_requests"`
	ElixirRequests   int64         `json:"elixir_requests"`
	JavaErrors       int64         `json:"java_errors"`
	ElixirErrors     int64         `json:"elixir_errors"`
	AvgJavaLatency   time.Duration `json:"avg_java_latency"`
	AvgElixirLatency time.Duration `json:"avg_elixir_latency"`
	LastJavaCheck    time.Time     `json:"last_java_check"`
	LastElixirCheck  time.Time     `json:"last_elixir_check"`
}

// NewBridgeManager создает менеджер мостов
func NewBridgeManager(javaURL, elixirURL string) *BridgeManager {
	return &BridgeManager{
		javaBridge:   NewJavaBridge(javaURL),
		elixirBridge: NewElixirBridge(elixirURL),
		status:       make(map[string]bool),
		stats:        &BridgeStats{},
	}
}

// ProcessFullPipeline обрабатывает полный пайплайн с контекстом
func (bm *BridgeManager) ProcessFullPipeline(ctx context.Context, audioData []byte, userID, guildID, url string) (*AudioProcessingResponse, error) {
	startTime := time.Now()

	// 1. Go → Java
	javaReq := &CommandRequest{
		Command: "play",
		URL:     url,
		UserID:  userID,
		GuildID: guildID,
	}

	_, err := bm.javaBridge.SendWithContext(ctx, javaReq)
	if err != nil {
		bm.recordError("java")
		return nil, fmt.Errorf("java step failed: %w", err)
	}

	bm.recordLatency("java", time.Since(startTime))

	// 2. Go → Elixir
	elixirReq := &AudioProcessingRequest{
		AudioData: audioData,
		UserID:    userID,
		GuildID:   guildID,
		Format:    "opus",
		Quality:   "high",
		Priority:  1,
		Effects: map[string]interface{}{
			"normalize": true,
			"equalizer": map[string]float64{
				"100":  2.0,
				"1000": 1.0,
				"5000": 0.5,
			},
		},
	}

	elixirResp, err := bm.elixirBridge.ProcessAudioWithContext(ctx, elixirReq)
	if err != nil {
		bm.recordError("elixir")
		return nil, fmt.Errorf("elixir step failed: %w", err)
	}

	bm.recordLatency("elixir", time.Since(startTime))

	return elixirResp, nil
}

// ProcessFullPipelineV2 альтернативная версия (только Go → Java → Elixir)
func (bm *BridgeManager) ProcessFullPipelineV2(ctx context.Context, userID, guildID, url string) (*AudioProcessingResponse, error) {
	startTime := time.Now()

	// 1. Go → Java (просто проверяем соединение)
	_, err := bm.javaBridge.SendWithContext(ctx, &CommandRequest{
		Command: "play",
		URL:     url,
		UserID:  userID,
		GuildID: guildID,
	})
	if err != nil {
		bm.recordError("java")
		return nil, fmt.Errorf("java step failed: %w", err)
	}

	bm.recordLatency("java", time.Since(startTime))

	// 2. Go → Elixir (применяем эффекты)
	elixirReq := &AudioProcessingRequest{
		UserID:  userID,
		GuildID: guildID,
		Format:  "opus",
		Quality: "high",
		Priority: 1,
	}

	elixirResp, err := bm.elixirBridge.ProcessAudioWithContext(ctx, elixirReq)
	if err != nil {
		bm.recordError("elixir")
		return nil, fmt.Errorf("elixir step failed: %w", err)
	}

	bm.recordLatency("elixir", time.Since(startTime))

	return elixirResp, nil
}

// ProcessSimplePipeline упрощенный пайплайн (без Java)
func (bm *BridgeManager) ProcessSimplePipeline(ctx context.Context, userID, guildID string) (*AudioProcessingResponse, error) {
	startTime := time.Now()

	elixirReq := &AudioProcessingRequest{
		UserID:  userID,
		GuildID: guildID,
		Format:  "opus",
		Quality: "high",
	}

	elixirResp, err := bm.elixirBridge.ProcessAudioWithContext(ctx, elixirReq)
	if err != nil {
		bm.recordError("elixir")
		return nil, fmt.Errorf("elixir processing failed: %w", err)
	}

	bm.recordLatency("elixir", time.Since(startTime))

	return elixirResp, nil
}

// CheckBridgesHealth проверяет здоровье всех мостов
func (bm *BridgeManager) CheckBridgesHealth(ctx context.Context) map[string]bool {
	bm.mu.Lock()
	defer bm.mu.Unlock()

	// Проверяем Java
	javaHealthy, javaErr := bm.javaBridge.HealthCheck(ctx)
	if javaErr != nil {
		bm.status["java"] = false
	} else {
		bm.status["java"] = javaHealthy
	}
	bm.stats.LastJavaCheck = time.Now()

	// Проверяем Elixir
	elixirHealthy, elixirErr := bm.elixirBridge.HealthCheckWithContext(ctx)
	if elixirErr != nil {
		bm.status["elixir"] = false
	} else {
		bm.status["elixir"] = elixirHealthy
	}
	bm.stats.LastElixirCheck = time.Now()

	return bm.status
}

// GetStats возвращает статистику
func (bm *BridgeManager) GetStats() *BridgeStats {
	bm.mu.RLock()
	defer bm.mu.RUnlock()

	return &BridgeStats{
		JavaRequests:     bm.stats.JavaRequests,
		ElixirRequests:   bm.stats.ElixirRequests,
		JavaErrors:       bm.stats.JavaErrors,
		ElixirErrors:     bm.stats.ElixirErrors,
		AvgJavaLatency:   bm.stats.AvgJavaLatency,
		AvgElixirLatency: bm.stats.AvgElixirLatency,
		LastJavaCheck:    bm.stats.LastJavaCheck,
		LastElixirCheck:  bm.stats.LastElixirCheck,
	}
}

// GetStatus возвращает текущий статус
func (bm *BridgeManager) GetStatus() map[string]interface{} {
	bm.mu.RLock()
	defer bm.mu.RUnlock()

	return map[string]interface{}{
		"java_healthy":   bm.status["java"],
		"elixir_healthy": bm.status["elixir"],
		"stats":          bm.stats,
		"uptime":         time.Since(bm.stats.LastJavaCheck).String(),
		"timestamp":      time.Now().Unix(),
	}
}

// GetJavaStatus получает статус Java Gateway
func (bm *BridgeManager) GetJavaStatus(ctx context.Context) (map[string]interface{}, error) {
	return bm.javaBridge.GetJavaStatus(ctx)
}

// RegisterAll регистрирует все компоненты
func (bm *BridgeManager) RegisterAll(ctx context.Context, processorID string) error {
	return bm.javaBridge.RegisterProcessor(ctx, processorID, "audio_processing,effects")
}

// UpdateUserEffects обновляет настройки эффектов пользователя в Elixir
func (bm *BridgeManager) UpdateUserEffects(ctx context.Context, userID string, effects map[string]interface{}) error {
	return bm.elixirBridge.UpdateUserEffectsWithContext(ctx, userID, effects)
}

// GetEffectsPresets получает пресеты эффектов из Elixir
func (bm *BridgeManager) GetEffectsPresets(ctx context.Context, userID string) (map[string]interface{}, error) {
	return bm.elixirBridge.GetEffectsPresetsWithContext(ctx, userID)
}

// ShutdownGracefully корректно завершает работу менеджера
func (bm *BridgeManager) ShutdownGracefully(ctx context.Context) error {
	done := make(chan struct{})

	go func() {
		bm.mu.Lock()
		defer bm.mu.Unlock()
		close(done)
	}()

	select {
	case <-done:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

// recordLatency записывает задержку
func (bm *BridgeManager) recordLatency(bridge string, latency time.Duration) {
	bm.mu.Lock()
	defer bm.mu.Unlock()

	switch bridge {
	case "java":
		bm.stats.JavaRequests++
		if bm.stats.AvgJavaLatency == 0 {
			bm.stats.AvgJavaLatency = latency
		} else {
			bm.stats.AvgJavaLatency = (bm.stats.AvgJavaLatency*time.Duration(bm.stats.JavaRequests-1) + latency) /
				time.Duration(bm.stats.JavaRequests)
		}
	case "elixir":
		bm.stats.ElixirRequests++
		if bm.stats.AvgElixirLatency == 0 {
			bm.stats.AvgElixirLatency = latency
		} else {
			bm.stats.AvgElixirLatency = (bm.stats.AvgElixirLatency*time.Duration(bm.stats.ElixirRequests-1) + latency) /
				time.Duration(bm.stats.ElixirRequests)
		}
	}
}

// recordError записывает ошибку
func (bm *BridgeManager) recordError(bridge string) {
	bm.mu.Lock()
	defer bm.mu.Unlock()

	switch bridge {
	case "java":
		bm.stats.JavaErrors++
	case "elixir":
		bm.stats.ElixirErrors++
	}
}