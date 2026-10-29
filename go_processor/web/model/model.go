package model

import (
	"context"
	"fmt"
	"io"
	"log"
	"math"
	"os"
	"sort"
	"sync"
	"sync/atomic"
	"time"

	ort "github.com/yalue/onnxruntime_go"
)

// ========== Config ==========

type Config struct {
	ModelPath       string
	MaxSeqLen       int
	EmbeddingDim    int
	PoolSize        int
	BatchSize       int
	ShutdownTimeout time.Duration
}

// ========== Metrics ==========

type Metrics struct {
	TotalRequests  atomic.Int64
	TotalErrors    atomic.Int64
	TotalLatencyMs atomic.Int64
	ActiveSessions atomic.Int64
	PoolHits       atomic.Int64
	PoolMisses     atomic.Int64
	StartTime      time.Time
	EndTime        time.Time
	BestLoss       float64
	TotalEpochs    int
	LastTrainLoss  float64
	LastValLoss    float64
}

func (m *Metrics) RecordLatency(start time.Time) {
	m.TotalLatencyMs.Add(time.Since(start).Milliseconds())
}

func (m *Metrics) AvgLatencyMs() float64 {
	if m.TotalRequests.Load() == 0 {
		return 0
	}
	return float64(m.TotalLatencyMs.Load()) / float64(m.TotalRequests.Load())
}

// ========== Session Pool ==========

type SessionWithTensors struct {
	Session *ort.Session[float32]
	Inputs  []*ort.Tensor[float32]
	Outputs []*ort.Tensor[float32]
}

type SessionPool struct {
	pool    chan *SessionWithTensors
	config  Config
	metrics *Metrics
	mu      sync.Mutex
	closed  bool
}

func NewSessionPool(config Config, metrics *Metrics) (*SessionPool, error) {
	// Инициализируем ONNX Runtime один раз
	if err := ort.InitializeEnvironment(); err != nil {
		return nil, fmt.Errorf("ONNX init failed: %w", err)
	}

	pool := &SessionPool{
		pool:    make(chan *SessionWithTensors, config.PoolSize),
		config:  config,
		metrics: metrics,
	}

	for i := 0; i < config.PoolSize; i++ {
		session, err := createSession(config)
		if err != nil {
			return nil, fmt.Errorf("create session %d: %w", i, err)
		}
		pool.pool <- session
	}

	return pool, nil
}

func createSession(config Config) (*SessionWithTensors, error) {
    // Только один вход
    inputShape := ort.Shape{int64(config.BatchSize), 288}
    inputData := make([]float32, config.BatchSize*288)
    inputTensor, err := ort.NewTensor(inputShape, inputData)
    if err != nil {
        return nil, fmt.Errorf("failed to create input tensor: %w", err)
    }

    outputShape := ort.Shape{int64(config.BatchSize), 288}
    outputData := make([]float32, config.BatchSize*288)
    outputTensor, err := ort.NewTensor(outputShape, outputData)
    if err != nil {
        inputTensor.Destroy()
        return nil, fmt.Errorf("failed to create output tensor: %w", err)
    }

    inputs := []*ort.Tensor[float32]{inputTensor}
    outputs := []*ort.Tensor[float32]{outputTensor}

    session, err := ort.NewSession(
        config.ModelPath,
        []string{"input"},
        []string{"output"},
        inputs,
        outputs,
    )
    if err != nil {
        inputTensor.Destroy()
        outputTensor.Destroy()
        return nil, fmt.Errorf("failed to create session: %w", err)
    }

    return &SessionWithTensors{
        Session: session,
        Inputs:  inputs,
        Outputs: outputs,
    }, nil
}

func (p *SessionPool) Acquire(ctx context.Context) (*SessionWithTensors, error) {
	p.mu.Lock()
	if p.closed {
		p.mu.Unlock()
		return nil, fmt.Errorf("pool is closed")
	}
	p.mu.Unlock()

	select {
	case session := <-p.pool:
		p.metrics.PoolHits.Add(1)
		return session, nil
	case <-ctx.Done():
		return nil, ctx.Err()
	default:
		p.metrics.PoolMisses.Add(1)
		return createSession(p.config)
	}
}

func (p *SessionPool) Release(session *SessionWithTensors) {
	if session == nil {
		return
	}
	
	p.mu.Lock()
	defer p.mu.Unlock()
	
	if p.closed {
		session.Session.Destroy()
		return
	}

	select {
	case p.pool <- session:
	default:
		session.Session.Destroy()
	}
}

func (p *SessionPool) Close() {
	p.mu.Lock()
	defer p.mu.Unlock()
	
	if p.closed {
		return
	}
	
	p.closed = true
	close(p.pool)
	for session := range p.pool {
		if session != nil {
			session.Session.Destroy()
		}
	}
}

// ========== Embedding Model ==========

type EmbeddingModel struct {
	pool    *SessionPool
	cfg     Config
	metrics *Metrics
	mu      sync.RWMutex
	loaded  bool
}

func NewEmbeddingModel(cfg Config) (*EmbeddingModel, error) {
	if cfg.PoolSize == 0 {
		cfg.PoolSize = 5
	}
	if cfg.BatchSize == 0 {
		cfg.BatchSize = 1
	}
	if cfg.ShutdownTimeout == 0 {
		cfg.ShutdownTimeout = 30 * time.Second
	}
	if cfg.MaxSeqLen == 0 {
		cfg.MaxSeqLen = 128
	}
	if cfg.EmbeddingDim == 0 {
		cfg.EmbeddingDim = 288
	}

	if _, err := os.Stat(cfg.ModelPath); os.IsNotExist(err) {
		return nil, fmt.Errorf("model not found: %s", cfg.ModelPath)
	}

	metrics := &Metrics{}
	pool, err := NewSessionPool(cfg, metrics)
	if err != nil {
		return nil, fmt.Errorf("create session pool failed: %w", err)
	}

	return &EmbeddingModel{
		pool:    pool,
		cfg:     cfg,
		metrics: metrics,
		loaded:  true,
	}, nil
}

// Encode - кодирование одного текста
func (m *EmbeddingModel) Encode(tokens []int64, mask []int64) ([]float32, error) {
	start := time.Now()
	defer m.metrics.RecordLatency(start)
	
	m.metrics.TotalRequests.Add(1)

	m.mu.RLock()
	if !m.loaded {
		m.mu.RUnlock()
		m.metrics.TotalErrors.Add(1)
		return nil, fmt.Errorf("model not loaded")
	}
	m.mu.RUnlock()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	
	sessionWrapper, err := m.pool.Acquire(ctx)
	if err != nil {
		m.metrics.TotalErrors.Add(1)
		return nil, fmt.Errorf("acquire session failed: %w", err)
	}
	defer m.pool.Release(sessionWrapper)

	seqLen := len(tokens)
	if seqLen > m.cfg.MaxSeqLen {
		seqLen = m.cfg.MaxSeqLen
	}

	// Только ОДИН входной тензор
	inputData := sessionWrapper.Inputs[0].GetData()
	
	// Очищаем
	for i := range inputData {
		inputData[i] = 0
	}

	// Заполняем входные данные
	for i := 0; i < seqLen && i < len(inputData); i++ {
		inputData[i] = float32(tokens[i])
	}

	// Запускаем инференс
	if err := sessionWrapper.Session.Run(); err != nil {
		m.metrics.TotalErrors.Add(1)
		return nil, fmt.Errorf("inference failed: %w", err)
	}

	// Получаем выходные данные (только ОДИН выход)
	outputData := sessionWrapper.Outputs[0].GetData()
	
	// Копируем результат
	embedding := make([]float32, m.cfg.EmbeddingDim)
	if len(outputData) >= m.cfg.EmbeddingDim {
		copy(embedding, outputData[:m.cfg.EmbeddingDim])
	}

	// L2 normalize
	var norm float32
	for _, v := range embedding {
		norm += v * v
	}
	norm = float32(math.Sqrt(float64(norm)))
	if norm > 0 {
		for i := range embedding {
			embedding[i] /= norm
		}
	}

	return embedding, nil
}

// EncodeBatch - батчевое кодирование
func (m *EmbeddingModel) EncodeBatch(batchTokens [][]int64, batchMask [][]int64) ([][]float32, error) {
	if len(batchTokens) == 0 {
		return nil, nil
	}

	results := make([][]float32, len(batchTokens))
	
	for i := range batchTokens {
		vec, err := m.Encode(batchTokens[i], batchMask[i])
		if err != nil {
			return nil, err
		}
		results[i] = vec
	}
	
	return results, nil
}

func (m *EmbeddingModel) GetMetrics() map[string]interface{} {
	return map[string]interface{}{
		"total_requests":  m.metrics.TotalRequests.Load(),
		"total_errors":    m.metrics.TotalErrors.Load(),
		"avg_latency_ms":  m.metrics.AvgLatencyMs(),
		"pool_hits":       m.metrics.PoolHits.Load(),
		"pool_misses":     m.metrics.PoolMisses.Load(),
		"active_sessions": m.metrics.ActiveSessions.Load(),
	}
}

func (m *EmbeddingModel) Shutdown(ctx context.Context) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	
	if !m.loaded {
		return nil
	}
	
	m.loaded = false
	
	// Закрываем пул сессий
	m.pool.Close()
	
	// Ждём или таймаут
	select {
	case <-time.After(m.cfg.ShutdownTimeout):
		return fmt.Errorf("shutdown timeout after %v", m.cfg.ShutdownTimeout)
	case <-ctx.Done():
		return ctx.Err()
	default:
		return ort.DestroyEnvironment()
	}
}

func (m *EmbeddingModel) Close() error {
	return m.Shutdown(context.Background())
}

// ========== Вспомогательные функции ==========

func SetupLogging() *os.File {
	logFile, err := os.OpenFile("training.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
	if err != nil {
		log.Printf("Warning: cannot create log file: %v", err)
		return nil
	}
	log.SetOutput(io.MultiWriter(os.Stdout, logFile))
	return logFile
}

func BuildMask(tokens []int64, maxSeqLen int) []int64 {
	mask := make([]int64, maxSeqLen)
	for i := 0; i < len(tokens) && i < maxSeqLen; i++ {
		if tokens[i] != 0 {
			mask[i] = 1
		}
	}
	return mask
}

// ========== Search Index ==========

type SearchIndex struct {
    model        *EmbeddingModel
    vectors      map[string][]float32
    metadata     map[string]string
    mu           sync.RWMutex
}

func NewSearchIndex(model *EmbeddingModel) *SearchIndex {
	return &SearchIndex{
		model:    model,
		vectors:  make(map[string][]float32),
		metadata: make(map[string]string),
	}
}

func (idx *SearchIndex) Add(id, text string, tokens, mask []int64) error {
	vec, err := idx.model.Encode(tokens, mask)
	if err != nil {
		return err
	}

	idx.mu.Lock()
	defer idx.mu.Unlock()
	idx.vectors[id] = vec
	idx.metadata[id] = text
	return nil
}

func (idx *SearchIndex) Search(queryTokens, queryMask []int64, topK int) ([]struct {
	ID      string
	Score   float32
	Content string
}, error) {
	queryVec, err := idx.model.Encode(queryTokens, queryMask)
	if err != nil {
		return nil, err
	}

	idx.mu.RLock()
	defer idx.mu.RUnlock()

	results := make([]struct {
		ID      string
		Score   float32
		Content string
	}, 0, len(idx.vectors))

	for id, vec := range idx.vectors {
		var dot float32
		for i := range queryVec {
			dot += queryVec[i] * vec[i]
		}
		results = append(results, struct {
			ID      string
			Score   float32
			Content string
		}{id, dot, idx.metadata[id]})
	}

	sort.Slice(results, func(i, j int) bool {
		return results[i].Score > results[j].Score
	})

	if topK > 0 && topK < len(results) {
		results = results[:topK]
	}
	return results, nil
}