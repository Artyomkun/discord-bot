package bridge

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// ElixirBridge обеспечивает связь Go → Elixir
type ElixirBridge struct {
	elixirURL   string
	httpClient  *http.Client
	retryCount  int
	retryDelay  time.Duration
}

// NewElixirBridge создает новый мост к Elixir
func NewElixirBridge(elixirURL string) *ElixirBridge {
	return &ElixirBridge{
		elixirURL: elixirURL,
		httpClient: &http.Client{
			Timeout: 60 * time.Second,
			Transport: &http.Transport{
				MaxIdleConns:        20,
				IdleConnTimeout:     120 * time.Second,
				DisableCompression:  true,
				DisableKeepAlives:   false,
				MaxIdleConnsPerHost: 20,
			},
		},
		retryCount: 3,
		retryDelay: 2 * time.Second,
	}
}

// AudioProcessingRequest запрос на обработку аудио в Elixir
type AudioProcessingRequest struct {
	AudioData  []byte                 `json:"audio_data"`
	UserID     string                 `json:"user_id"`
	GuildID    string                 `json:"guild_id"`
	Format     string                 `json:"format"`
	Effects    map[string]interface{} `json:"effects,omitempty"`
	Quality    string                 `json:"quality,omitempty"`
	Priority   int                    `json:"priority,omitempty"`
	Metadata   map[string]string      `json:"metadata,omitempty"`
}

// AudioProcessingResponse ответ от Elixir
type AudioProcessingResponse struct {
	Success        bool     `json:"success"`
	Processed      bool     `json:"processed"`
	AudioData      []byte   `json:"audio_data,omitempty"`
	AudioURL       string   `json:"audio_url,omitempty"`
	Duration       float64  `json:"duration,omitempty"`
	Format         string   `json:"format,omitempty"`
	Bitrate        int      `json:"bitrate,omitempty"`
	EffectsApplied []string `json:"effects_applied,omitempty"`
	Message        string   `json:"message,omitempty"`
	Error          string   `json:"error,omitempty"`
}

// ProcessAudioWithContext отправляет аудио в Elixir с поддержкой контекста
func (eb *ElixirBridge) ProcessAudioWithContext(ctx context.Context, req *AudioProcessingRequest) (*AudioProcessingResponse, error) {
	var lastError error

	for attempt := 0; attempt < eb.retryCount; attempt++ {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(eb.retryDelay * time.Duration(attempt)):
			}
		}

		resp, err := eb.sendAudioProcessingRequestWithContext(ctx, req)
		if err == nil {
			return resp, nil
		}

		lastError = err
		fmt.Printf("Attempt %d failed: %v\n", attempt+1, err)
	}

	return nil, fmt.Errorf("all %d attempts failed. Last error: %w", eb.retryCount, lastError)
}

// ProcessAudioWithEffects сохраняет обратную совместимость (без context)
func (eb *ElixirBridge) ProcessAudioWithEffects(req *AudioProcessingRequest) (*AudioProcessingResponse, error) {
	return eb.ProcessAudioWithContext(context.Background(), req)
}

// sendAudioProcessingRequestWithContext отправляет запрос с контекстом
func (eb *ElixirBridge) sendAudioProcessingRequestWithContext(ctx context.Context, req *AudioProcessingRequest) (*AudioProcessingResponse, error) {
	jsonData, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal audio request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, "POST", eb.elixirURL+"/api/audio/from-go", bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("X-Audio-Size", fmt.Sprintf("%d", len(req.AudioData)))
	httpReq.Header.Set("X-User-ID", req.UserID)
	httpReq.Header.Set("X-Request-ID", generateElixirRequestID(req.UserID))

	resp, err := eb.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("failed to send request to Elixir: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("elixir returned error %d: %s", resp.StatusCode, string(body))
	}

	var audioResp AudioProcessingResponse
	if err := json.NewDecoder(resp.Body).Decode(&audioResp); err != nil {
		return nil, fmt.Errorf("failed to decode Elixir response: %w", err)
	}

	if !audioResp.Success {
		return nil, fmt.Errorf("elixir processing failed: %s", audioResp.Error)
	}

	return &audioResp, nil
}

// GetEffectsPresetsWithContext получает пресеты эффектов с контекстом
func (eb *ElixirBridge) GetEffectsPresetsWithContext(ctx context.Context, userID string) (map[string]interface{}, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", eb.elixirURL+"/api/effects/presets", nil)
	if err != nil {
		return nil, err
	}

	req.Header.Set("X-User-ID", userID)

	resp, err := eb.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var presets map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&presets); err != nil {
		return nil, err
	}

	return presets, nil
}

// GetEffectsPresets сохраняет обратную совместимость
func (eb *ElixirBridge) GetEffectsPresets(userID string) (map[string]interface{}, error) {
	return eb.GetEffectsPresetsWithContext(context.Background(), userID)
}

// UpdateUserEffectsWithContext обновляет настройки эффектов с контекстом
func (eb *ElixirBridge) UpdateUserEffectsWithContext(ctx context.Context, userID string, effects map[string]interface{}) error {
	updateReq := map[string]interface{}{
		"user_id": userID,
		"effects": effects,
	}

	jsonData, err := json.Marshal(updateReq)
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, "POST", eb.elixirURL+"/api/effects/"+userID, bytes.NewBuffer(jsonData))
	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", "application/json")

	resp, err := eb.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("failed to update effects: %s", string(body))
	}

	return nil
}

// UpdateUserEffects сохраняет обратную совместимость
func (eb *ElixirBridge) UpdateUserEffects(userID string, effects map[string]interface{}) error {
	return eb.UpdateUserEffectsWithContext(context.Background(), userID, effects)
}

// HealthCheckWithContext проверяет доступность Elixir с контекстом
func (eb *ElixirBridge) HealthCheckWithContext(ctx context.Context) (bool, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", eb.elixirURL+"/health", nil)
	if err != nil {
		return false, err
	}

	resp, err := eb.httpClient.Do(req)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()

	return resp.StatusCode == http.StatusOK, nil
}

// HealthCheck сохраняет обратную совместимость
func (eb *ElixirBridge) HealthCheck() (bool, error) {
	return eb.HealthCheckWithContext(context.Background())
}

// StreamAudioWithContext начинает стриминг аудио с контекстом
func (eb *ElixirBridge) StreamAudioWithContext(ctx context.Context, audioData []byte, userID, guildID string) error {
	streamReq := map[string]interface{}{
		"audio_data": audioData,
		"user_id":    userID,
		"guild_id":   guildID,
		"action":     "start_stream",
	}

	jsonData, err := json.Marshal(streamReq)
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, "POST", eb.elixirURL+"/api/audio/stream", bytes.NewBuffer(jsonData))
	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", "application/json")

	resp, err := eb.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("streaming failed: %s", string(body))
	}

	return nil
}

// NormalizeAudioWithContext отправляет аудио для нормализации с контекстом
func (eb *ElixirBridge) NormalizeAudioWithContext(ctx context.Context, audioData []byte, targetPeak float64, mode string) ([]byte, error) {
	req := map[string]interface{}{
		"audio_data":   audioData,
		"target_peak":  targetPeak,
		"mode":         mode,
	}

	jsonData, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal normalize request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, "POST", eb.elixirURL+"/api/audio/normalize", bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := eb.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("failed to send normalize request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("elixir normalize error %d: %s", resp.StatusCode, string(body))
	}

	var result struct {
		AudioData []byte `json:"audio_data"`
		Success   bool   `json:"success"`
		Error     string `json:"error"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode normalize response: %w", err)
	}

	if !result.Success {
		return nil, fmt.Errorf("elixir normalize failed: %s", result.Error)
	}

	return result.AudioData, nil
}

// GetMetricsWithContext получает метрики с контекстом
func (eb *ElixirBridge) GetMetricsWithContext(ctx context.Context) (map[string]interface{}, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", eb.elixirURL+"/metrics", nil)
	if err != nil {
		return nil, err
	}

	resp, err := eb.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var metrics map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&metrics); err != nil {
		return nil, err
	}

	return metrics, nil
}

// generateElixirRequestID генерирует ID для запроса к Elixir
func generateElixirRequestID(userID string) string {
	timestamp := time.Now().UnixNano()
	return fmt.Sprintf("go_elixir_%s_%d", userID, timestamp)
}