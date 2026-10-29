package main

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"sync"
	"sync/atomic"
	"time"

	"google.golang.org/grpc"
)

// LoadBalanceStrategy — стратегия балансировки
type LoadBalanceStrategy int

const (
	RoundRobin LoadBalanceStrategy = iota
	Random
	LeastConnections
	FastestResponse
)

// String возвращает строковое представление стратегии
func (s LoadBalanceStrategy) String() string {
	switch s {
	case RoundRobin:
		return "round_robin"
	case Random:
		return "random"
	case LeastConnections:
		return "least_connections"
	case FastestResponse:
		return "fastest_response"
	default:
		return "unknown"
	}
}

// PoolClientMetrics — метрики пула клиентов (переименовано, чтобы не конфликтовать)
type PoolClientMetrics struct {
	TotalClients     int64
	ActiveClients    int64
	TotalRequests    int64
	SuccessfulReqs   int64
	FailedReqs       int64
	AvgResponseTime  time.Duration
	mu               sync.RWMutex
}

// PoolConfig — конфигурация пула клиентов (переименовано)
type PoolConfig struct {
	Addresses        []string
	Strategy         LoadBalanceStrategy
	HealthCheck      time.Duration
	ConnectTimeout   time.Duration
	MaxRetries       int
	RetryDelay       time.Duration
}

// DefaultPoolConfig — конфигурация по умолчанию
func DefaultPoolConfig() *PoolConfig {
	return &PoolConfig{
		Addresses:      []string{"localhost:50052"},
		Strategy:       RoundRobin,
		HealthCheck:    30 * time.Second,
		ConnectTimeout: 10 * time.Second,
		MaxRetries:     3,
		RetryDelay:     1 * time.Second,
	}
}

// ClientPool — пул клиентов для нескольких серверов
type ClientPool struct {
	mu           sync.RWMutex
	clients      map[string]*PooledClient
	addresses    []string
	strategy     LoadBalanceStrategy
	metrics      *PoolClientMetrics
	healthCheck  time.Duration
	counter      int64 // для round-robin
}

// NewClientPool создаёт новый пул клиентов
func NewClientPool(config *PoolConfig) *ClientPool {
	if config == nil {
		config = DefaultPoolConfig()
	}

	pool := &ClientPool{
		clients:     make(map[string]*PooledClient),
		addresses:   config.Addresses,
		strategy:    config.Strategy,
		metrics:     &PoolClientMetrics{},
		healthCheck: config.HealthCheck,
		counter:     0,
	}

	// Создаём клиентов для каждого адреса
	for _, addr := range config.Addresses {
		clientConfig := &ClientPoolConfig{
			Address:        addr,
			HealthCheck:    config.HealthCheck,
			ConnectTimeout: config.ConnectTimeout,
		}
		client := NewPooledClient(addr, clientConfig)
		pool.clients[addr] = client
	}

	atomic.AddInt64(&pool.metrics.TotalClients, int64(len(pool.clients)))

	// Запускаем health check
	go pool.healthCheckLoop()
	// Запускаем сбор метрик
	go pool.metricsLoop()

	log.Printf("🚀 Client pool started with %d clients, strategy=%s", len(pool.clients), pool.strategy)

	return pool
}

// healthCheckLoop — периодическая проверка здоровья клиентов
func (p *ClientPool) healthCheckLoop() {
	ticker := time.NewTicker(p.healthCheck)
	defer ticker.Stop()

	for range ticker.C {
		p.checkHealth()
	}
}

// checkHealth — проверяет здоровье всех клиентов
func (p *ClientPool) checkHealth() {
	p.mu.RLock()
	clients := make(map[string]*PooledClient, len(p.clients))
	for addr, client := range p.clients {
		clients[addr] = client
	}
	p.mu.RUnlock()

	healthyCount := 0
	for addr, client := range clients {
		load := client.GetLoad()
		if load < 1.0 {
			healthyCount++
		} else {
			log.Printf("⚠️ Client %s is overloaded (load=%.2f)", addr, load)
		}
	}

	log.Printf("🏥 Health check: %d/%d clients healthy", healthyCount, len(clients))
}

// metricsLoop — сбор метрик
func (p *ClientPool) metricsLoop() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		p.updateMetrics()
	}
}

// updateMetrics — обновляет метрики
func (p *ClientPool) updateMetrics() {
	p.mu.RLock()
	defer p.mu.RUnlock()

	active := 0
	for _, client := range p.clients {
		if client.GetLoad() > 0 {
			active++
		}
	}
	atomic.StoreInt64(&p.metrics.ActiveClients, int64(active))

	// Логируем метрики
	if time.Now().Second()%30 == 0 {
		log.Printf("📊 Client pool metrics: clients=%d, active=%d, requests=%d, success_rate=%.2f%%",
			atomic.LoadInt64(&p.metrics.TotalClients),
			atomic.LoadInt64(&p.metrics.ActiveClients),
			atomic.LoadInt64(&p.metrics.TotalRequests),
			p.getSuccessRate())
	}
}

// getSuccessRate возвращает процент успешных запросов
func (p *ClientPool) getSuccessRate() float64 {
	total := atomic.LoadInt64(&p.metrics.TotalRequests)
	if total == 0 {
		return 100.0
	}
	success := atomic.LoadInt64(&p.metrics.SuccessfulReqs)
	return float64(success) / float64(total) * 100
}

// selectClient выбирает клиент по стратегии балансировки
func (p *ClientPool) selectClient() *PooledClient {
	p.mu.RLock()
	defer p.mu.RUnlock()

	if len(p.clients) == 0 {
		return nil
	}

	// Фильтруем здоровых клиентов
	healthyClients := make([]*PooledClient, 0)
	for _, client := range p.clients {
		if client.GetLoad() < 1.0 {
			healthyClients = append(healthyClients, client)
		}
	}

	if len(healthyClients) == 0 {
		// Если нет здоровых, берём любых
		for _, client := range p.clients {
			healthyClients = append(healthyClients, client)
		}
	}

	switch p.strategy {
	case RoundRobin:
		return p.roundRobin(healthyClients)
	case Random:
		return p.random(healthyClients)
	case LeastConnections:
		return p.leastConnections(healthyClients)
	case FastestResponse:
		return p.fastestResponse(healthyClients)
	default:
		return healthyClients[0]
	}
}

// roundRobin — round-robin балансировка
func (p *ClientPool) roundRobin(clients []*PooledClient) *PooledClient {
	idx := atomic.AddInt64(&p.counter, 1) % int64(len(clients))
	return clients[idx]
}

// random — случайная балансировка
func (p *ClientPool) random(clients []*PooledClient) *PooledClient {
	idx := rand.Intn(len(clients))
	return clients[idx]
}

// leastConnections — балансировка по наименьшему количеству соединений
func (p *ClientPool) leastConnections(clients []*PooledClient) *PooledClient {
	var best *PooledClient
	minLoad := 2.0

	for _, client := range clients {
		load := client.GetLoad()
		if load < minLoad {
			minLoad = load
			best = client
		}
	}
	return best
}

// fastestResponse — балансировка по самому быстрому ответу
func (p *ClientPool) fastestResponse(clients []*PooledClient) *PooledClient {
	// Простая заглушка — возвращаем первого
	return clients[0]
}

// Call выполняет gRPC вызов с автоматическим выбором клиента
func (p *ClientPool) Call(ctx context.Context, fn func(*grpc.ClientConn) error) error {
	start := time.Now()
	atomic.AddInt64(&p.metrics.TotalRequests, 1)

	var lastErr error
	for attempt := 0; attempt < 3; attempt++ {
		client := p.selectClient()
		if client == nil {
			lastErr = fmt.Errorf("no client available")
			continue
		}

		err := client.Call(ctx, fn)
		if err == nil {
			atomic.AddInt64(&p.metrics.SuccessfulReqs, 1)
			p.updateResponseTime(time.Since(start))
			return nil
		}

		lastErr = err

		// Если ошибка соединения, ждём перед следующей попыткой
		if isConnectionError(err) {
			time.Sleep(time.Duration(attempt+1) * 100 * time.Millisecond)
		}
	}

	atomic.AddInt64(&p.metrics.FailedReqs, 1)
	return lastErr
}

// updateResponseTime обновляет среднее время ответа
func (p *ClientPool) updateResponseTime(duration time.Duration) {
	total := atomic.LoadInt64(&p.metrics.TotalRequests)
	if total == 0 {
		return
	}

	p.metrics.mu.Lock()
	oldAvg := p.metrics.AvgResponseTime
	newAvg := time.Duration((int64(oldAvg)*(total-1) + int64(duration)) / total)
	p.metrics.AvgResponseTime = newAvg
	p.metrics.mu.Unlock()
}

// AddClient добавляет нового клиента в пул
func (p *ClientPool) AddClient(address string) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if _, exists := p.clients[address]; exists {
		return
	}

	clientConfig := &ClientPoolConfig{
		Address:        address,
		HealthCheck:    p.healthCheck,
		ConnectTimeout: 10 * time.Second,
	}
	client := NewPooledClient(address, clientConfig)

	p.clients[address] = client
	p.addresses = append(p.addresses, address)
	atomic.AddInt64(&p.metrics.TotalClients, 1)

	log.Printf("➕ Added client %s to pool", address)
}

// RemoveClient удаляет клиент из пула
func (p *ClientPool) RemoveClient(address string) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if client, exists := p.clients[address]; exists {
		client.Close()
		delete(p.clients, address)

		// Обновляем список адресов
		newAddresses := make([]string, 0, len(p.addresses)-1)
		for _, addr := range p.addresses {
			if addr != address {
				newAddresses = append(newAddresses, addr)
			}
		}
		p.addresses = newAddresses
		atomic.AddInt64(&p.metrics.TotalClients, -1)

		log.Printf("➖ Removed client %s from pool", address)
	}
}

// GetStats возвращает статистику пула
func (p *ClientPool) GetStats() map[string]interface{} {
	p.mu.RLock()
	defer p.mu.RUnlock()

	clientsStats := make(map[string]interface{})
	for addr, client := range p.clients {
		clientsStats[addr] = client.GetStats()
	}

	return map[string]interface{}{
		"strategy":        p.strategy.String(),
		"total_clients":   atomic.LoadInt64(&p.metrics.TotalClients),
		"active_clients":  atomic.LoadInt64(&p.metrics.ActiveClients),
		"total_requests":  atomic.LoadInt64(&p.metrics.TotalRequests),
		"successful_reqs": atomic.LoadInt64(&p.metrics.SuccessfulReqs),
		"failed_reqs":     atomic.LoadInt64(&p.metrics.FailedReqs),
		"avg_response_ms": p.metrics.AvgResponseTime.Milliseconds(),
		"success_rate":    p.getSuccessRate(),
		"clients":         clientsStats,
	}
}

// Close закрывает все клиенты в пуле
func (p *ClientPool) Close() {
	p.mu.Lock()
	defer p.mu.Unlock()

	for _, client := range p.clients {
		client.Close()
	}
	p.clients = make(map[string]*PooledClient)
	p.addresses = []string{}

	log.Printf("🔌 Client pool closed")
}

// ========== MultiPool — пул пулов для разных сервисов ==========

// MultiClientPool — пул клиентов для разных сервисов
type MultiClientPool struct {
	mu     sync.RWMutex
	pools  map[string]*ClientPool
	config *PoolConfig
}

// NewMultiClientPool создаёт мульти-пул
func NewMultiClientPool(config *PoolConfig) *MultiClientPool {
	if config == nil {
		config = DefaultPoolConfig()
	}

	return &MultiClientPool{
		pools:  make(map[string]*ClientPool),
		config: config,
	}
}

// GetPool возвращает пул для указанного сервиса
func (m *MultiClientPool) GetPool(service string) *ClientPool {
	m.mu.RLock()
	pool, exists := m.pools[service]
	m.mu.RUnlock()

	if exists {
		return pool
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	if pool, exists := m.pools[service]; exists {
		return pool
	}

	pool = NewClientPool(m.config)
	m.pools[service] = pool
	return pool
}

// Call выполняет вызов к указанному сервису
func (m *MultiClientPool) Call(service string, ctx context.Context, fn func(*grpc.ClientConn) error) error {
	pool := m.GetPool(service)
	return pool.Call(ctx, fn)
}

// GetStats возвращает статистику всех пулов
func (m *MultiClientPool) GetStats() map[string]interface{} {
	m.mu.RLock()
	defer m.mu.RUnlock()

	stats := make(map[string]interface{})
	for service, pool := range m.pools {
		stats[service] = pool.GetStats()
	}
	return stats
}

// Close закрывает все пулы
func (m *MultiClientPool) Close() {
	m.mu.Lock()
	defer m.mu.Unlock()

	for _, pool := range m.pools {
		pool.Close()
	}
	m.pools = make(map[string]*ClientPool)
}