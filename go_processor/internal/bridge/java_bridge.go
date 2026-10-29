package bridge

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sync/atomic"
	"time"
)

// JavaBridge обеспечивает связь Go → Java → Python
type JavaBridge struct {
	javaURL     string
	httpClient  *http.Client
	timeout     time.Duration
	requestID   atomic.Int64
	circuitBreaker *CircuitBreaker  // Добавляем circuit breaker
}

// Конфигурация
type BridgeConfig struct {
	JavaURL         string
	Timeout         time.Duration
	MaxIdleConns    int
	IdleConnTimeout time.Duration
	RetryCount      int
	RetryDelay      time.Duration
}

// NewJavaBridge создает новый мост к Java
func NewJavaBridge(javaURL string) *JavaBridge {
	return NewJavaBridgeWithConfig(&BridgeConfig{
		JavaURL:         javaURL,
		Timeout:         30 * time.Second,
		MaxIdleConns:    10,
		IdleConnTimeout: 90 * time.Second,
	})
}

// NewJavaBridgeWithConfig создает мост с кастомной конфигурацией
func NewJavaBridgeWithConfig(cfg *BridgeConfig) *JavaBridge {
	return &JavaBridge{
		javaURL: cfg.JavaURL,
		httpClient: &http.Client{
			Timeout: cfg.Timeout,
			Transport: &http.Transport{
				MaxIdleConns:        cfg.MaxIdleConns,
				IdleConnTimeout:     cfg.IdleConnTimeout,
				DisableCompression:  false,
				DisableKeepAlives:   false,
				MaxIdleConnsPerHost: cfg.MaxIdleConns,
			},
		},
		timeout:       cfg.Timeout,
		circuitBreaker: NewCircuitBreaker(5, 30*time.Second), // 5 failures, 30s timeout
	}
}

// CommandRequest запрос к Java API
type CommandRequest struct {
	Command   string            `json:"command"`
	URL       string            `json:"url,omitempty"`
	UserID    string            `json:"user_id"`
	GuildID   string            `json:"guild_id"`
	ChannelID string            `json:"channel_id,omitempty"`
	Options   map[string]string `json:"options,omitempty"`
	Audio     []byte            `json:"audio,omitempty"`
	TimeoutMs int               `json:"timeout_ms,omitempty"`
}

// CommandResponse ответ от Java API
type CommandResponse struct {
	Success bool                   `json:"success"`
	Message string                 `json:"message"`
	Data    map[string]interface{} `json:"data,omitempty"`
	Error   string                 `json:"error,omitempty"`
	Latency time.Duration          `json:"latency,omitempty"`
}

// SendWithContext отправляет команду с контекстом (для отмены/таймаута)
func (jb *JavaBridge) SendWithContext(ctx context.Context, req *CommandRequest) (*CommandResponse, error) {
	// Проверяем circuit breaker
	if !jb.circuitBreaker.Allow() {
		return nil, fmt.Errorf("circuit breaker open for %s", jb.javaURL)
	}

	start := time.Now()
	jsonData, err := json.Marshal(req)
	if err != nil {
		jb.circuitBreaker.RecordFailure()
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, "POST", jb.javaURL+"/api/command", bytes.NewBuffer(jsonData))
	if err != nil {
		jb.circuitBreaker.RecordFailure()
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("X-Go-Processor", "true")
	httpReq.Header.Set("X-Request-ID", jb.generateRequestID())

	resp, err := jb.httpClient.Do(httpReq)
	if err != nil {
		jb.circuitBreaker.RecordFailure()
		return nil, fmt.Errorf("failed to send request to Java: %w", err)
	}
	defer resp.Body.Close()

	latency := time.Since(start)

	if resp.StatusCode != http.StatusOK {
		jb.circuitBreaker.RecordFailure()
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("java returned error %d: %s", resp.StatusCode, string(body))
	}

	var commandResp CommandResponse
	if err := json.NewDecoder(resp.Body).Decode(&commandResp); err != nil {
		jb.circuitBreaker.RecordFailure()
		return nil, fmt.Errorf("failed to decode Java response: %w", err)
	}

	if !commandResp.Success {
		jb.circuitBreaker.RecordFailure()
		return nil, fmt.Errorf("java processing failed: %s", commandResp.Error)
	}

	// Успех — записываем
	jb.circuitBreaker.RecordSuccess()
	commandResp.Latency = latency

	return &commandResp, nil
}

// SendToJava отправляет команду в Java Gateway (совместимость со старым API)
func (jb *JavaBridge) SendToJava(req *CommandRequest) (*CommandResponse, error) {
	return jb.SendWithContext(context.Background(), req)
}

// ProcessAudio отправляет аудио данные в Java (улучшенная версия)
func (jb *JavaBridge) ProcessAudio(ctx context.Context, audioData []byte, userID, guildID string, format string) (*CommandResponse, error) {
	req := &CommandRequest{
		Command:  "process_audio",
		UserID:   userID,
		GuildID:  guildID,
		Options:  map[string]string{"format": format},
		Audio:    audioData,
	}

	return jb.SendWithContext(ctx, req)
}

// ForwardToPython отправляет команду через Java в Python
func (jb *JavaBridge) ForwardToPython(ctx context.Context, command, url, userID, guildID string) (*CommandResponse, error) {
	req := &CommandRequest{
		Command:  command,
		URL:      url,
		UserID:   userID,
		GuildID:  guildID,
	}

	resp, err := jb.SendWithContext(ctx, req)
	if err != nil {
		return nil, err
	}

	// Проверяем, что Java переслала в Python
	if resp.Message != "forwarded_to_python" {
		return nil, fmt.Errorf("java failed to forward to Python: %s", resp.Message)
	}

	return resp, nil
}

// HealthCheck проверяет доступность Java Gateway (с таймаутом)
func (jb *JavaBridge) HealthCheck(ctx context.Context) (bool, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", jb.javaURL+"/health", nil)
	if err != nil {
		return false, err
	}

	resp, err := jb.httpClient.Do(req)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()

	return resp.StatusCode == http.StatusOK, nil
}

// GetJavaStatus получает статус Java Gateway
func (jb *JavaBridge) GetJavaStatus(ctx context.Context) (map[string]interface{}, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", jb.javaURL+"/api/status", nil)
	if err != nil {
		return nil, err
	}

	resp, err := jb.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var status map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&status); err != nil {
		return nil, err
	}

	return status, nil
}

// BatchProcess пакетная обработка команд
func (jb *JavaBridge) BatchProcess(ctx context.Context, requests []*CommandRequest) ([]*CommandResponse, error) {
	jsonData, err := json.Marshal(requests)
	if err != nil {
		return nil, err
	}

	httpReq, err := http.NewRequestWithContext(ctx, "POST", jb.javaURL+"/api/batch", bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := jb.httpClient.Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var responses []*CommandResponse
	if err := json.NewDecoder(resp.Body).Decode(&responses); err != nil {
		return nil, err
	}

	return responses, nil
}

// RegisterProcessor регистрирует Go процессор в Java
func (jb *JavaBridge) RegisterProcessor(ctx context.Context, processorID, capabilities string) error {
	registration := map[string]interface{}{
		"processor_id": processorID,
		"capabilities": capabilities,
		"type":         "go_audio_processor",
		"version":      "1.0.0",
		"timestamp":    time.Now().Unix(),
	}

	jsonData, err := json.Marshal(registration)
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, "POST", jb.javaURL+"/api/register/processor", bytes.NewBuffer(jsonData))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := jb.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("registration failed: %s", string(body))
	}

	return nil
}

// generateRequestID генерирует ID для запроса (sequence number)
func (jb *JavaBridge) generateRequestID() string {
	id := jb.requestID.Add(1)
	return fmt.Sprintf("go_%d_%d", time.Now().UnixMilli(), id)
}

// CircuitBreaker простой предохранитель
type CircuitBreaker struct {
	failures     atomic.Int32
	maxFailures  int32
	timeout      time.Duration
	lastFailure  atomic.Int64  // Unix nano
	state        atomic.Int32  // 0=closed, 1=open, 2=half-open
}

func NewCircuitBreaker(maxFailures int32, timeout time.Duration) *CircuitBreaker {
	return &CircuitBreaker{
		maxFailures: maxFailures,
		timeout:     timeout,
	}
}

func (cb *CircuitBreaker) Allow() bool {
	if cb.state.Load() == 1 { // open
		lastFail := time.Unix(0, cb.lastFailure.Load())
		if time.Since(lastFail) > cb.timeout {
			cb.state.Store(2) // half-open
			return true
		}
		return false
	}
	return true
}

func (cb *CircuitBreaker) RecordSuccess() {
	cb.failures.Store(0)
	if cb.state.Load() == 2 {
		cb.state.Store(0) // closed
	}
}

func (cb *CircuitBreaker) RecordFailure() {
	failures := cb.failures.Add(1)
	cb.lastFailure.Store(time.Now().UnixNano())
	if failures >= cb.maxFailures {
		cb.state.Store(1) // open
	}
}