package main

import (
	"context"
	"log"
	"sync"
	"sync/atomic"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/connectivity"
	"google.golang.org/grpc/credentials/insecure"
)

// ConnectionPoolMetrics — метрики пула соединений
type ConnectionPoolMetrics struct {
	TotalConnections    int64
	ActiveConnections   int64
	IdleConnections     int64
	UnhealthyConnections int64
	TotalCreated        int64
	TotalClosed         int64
	TotalErrors         int64
	TotalReconnects     int64
	AvgConnectionAge    time.Duration
}

// ConnectionPool — пул gRPC соединений
type ConnectionPool struct {
	mu            sync.RWMutex
	connections   map[string]*PooledConnection
	maxSize       int
	idleTimeout   time.Duration
	healthCheck   time.Duration
	metrics       *ConnectionPoolMetrics
}

// PooledConnection — соединение в пуле
type PooledConnection struct {
	conn      *grpc.ClientConn
	address   string
	createdAt time.Time
	lastUsed  time.Time
	inUse     bool
	healthy   bool
}

// ConnectionPoolConfig — конфигурация пула
type ConnectionPoolConfig struct {
	MaxSize     int
	IdleTimeout time.Duration
	HealthCheck time.Duration
}

// DefaultPoolConfig — конфигурация по умолчанию
func DefaultPoolConfig() *ConnectionPoolConfig {
	return &ConnectionPoolConfig{
		MaxSize:     10,
		IdleTimeout: 5 * time.Minute,
		HealthCheck: 30 * time.Second,
	}
}

// NewConnectionPool создаёт новый пул соединений
func NewConnectionPool(config *ConnectionPoolConfig) *ConnectionPool {
	if config == nil {
		config = DefaultPoolConfig()
	}

	pool := &ConnectionPool{
		connections: make(map[string]*PooledConnection),
		maxSize:     config.MaxSize,
		idleTimeout: config.IdleTimeout,
		healthCheck: config.HealthCheck,
		metrics:     &ConnectionPoolMetrics{},
	}

	// Запускаем фоновые задачи
	go pool.cleanupLoop()
	go pool.healthCheckLoop()
	go pool.metricsLoop()

	return pool
}

// GetConnection получает соединение из пула или создаёт новое
func (p *ConnectionPool) GetConnection(address string) (*grpc.ClientConn, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	// Проверяем существующее соединение
	if conn, exists := p.connections[address]; exists && conn.healthy && !conn.inUse {
		conn.lastUsed = time.Now()
		conn.inUse = true

		// Проверяем состояние канала
		state := conn.conn.GetState()
		if state == connectivity.Ready || state == connectivity.Idle {
			atomic.AddInt64(&p.metrics.ActiveConnections, 1)
			atomic.AddInt64(&p.metrics.IdleConnections, -1)
			return conn.conn, nil
		}

		// Канал не готов — закрываем и удаляем
		conn.conn.Close()
		delete(p.connections, address)
		atomic.AddInt64(&p.metrics.TotalClosed, 1)
		atomic.AddInt64(&p.metrics.TotalErrors, 1)
	}

	// Создаём новое соединение
	conn, err := grpc.NewClient(address, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		atomic.AddInt64(&p.metrics.TotalErrors, 1)
		return nil, err
	}

	p.connections[address] = &PooledConnection{
		conn:      conn,
		address:   address,
		createdAt: time.Now(),
		lastUsed:  time.Now(),
		inUse:     true,
		healthy:   true,
	}

	atomic.AddInt64(&p.metrics.TotalConnections, 1)
	atomic.AddInt64(&p.metrics.TotalCreated, 1)
	atomic.AddInt64(&p.metrics.ActiveConnections, 1)

	log.Printf("✅ Created new connection to %s (total: %d)", address, len(p.connections))

	return conn, nil
}

// ReleaseConnection возвращает соединение в пул
func (p *ConnectionPool) ReleaseConnection(address string) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if conn, exists := p.connections[address]; exists {
		conn.inUse = false
		conn.lastUsed = time.Now()
		atomic.AddInt64(&p.metrics.ActiveConnections, -1)
		atomic.AddInt64(&p.metrics.IdleConnections, 1)
	}
}

// CloseConnection закрывает соединение и удаляет из пула
func (p *ConnectionPool) CloseConnection(address string) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if conn, exists := p.connections[address]; exists {
		conn.conn.Close()
		delete(p.connections, address)
		atomic.AddInt64(&p.metrics.TotalClosed, 1)
		if conn.inUse {
			atomic.AddInt64(&p.metrics.ActiveConnections, -1)
		} else {
			atomic.AddInt64(&p.metrics.IdleConnections, -1)
		}
		atomic.AddInt64(&p.metrics.TotalConnections, -1)
		log.Printf("🔌 Closed connection to %s", address)
	}
}

// CloseAll закрывает все соединения
func (p *ConnectionPool) CloseAll() {
	p.mu.Lock()
	defer p.mu.Unlock()

	for address, conn := range p.connections {
		conn.conn.Close()
		delete(p.connections, address)
		atomic.AddInt64(&p.metrics.TotalClosed, 1)
		log.Printf("🔌 Closed connection to %s", address)
	}
	atomic.StoreInt64(&p.metrics.TotalConnections, 0)
	atomic.StoreInt64(&p.metrics.ActiveConnections, 0)
	atomic.StoreInt64(&p.metrics.IdleConnections, 0)
}

// cleanupLoop — периодическая очистка неактивных соединений
func (p *ConnectionPool) cleanupLoop() {
	ticker := time.NewTicker(p.idleTimeout / 2)
	defer ticker.Stop()

	for range ticker.C {
		p.cleanupIdle()
	}
}

// cleanupIdle — очищает неактивные соединения
func (p *ConnectionPool) cleanupIdle() {
	p.mu.Lock()
	defer p.mu.Unlock()

	now := time.Now()
	for address, conn := range p.connections {
		// Пропускаем используемые
		if conn.inUse {
			continue
		}

		// Проверяем idle таймаут
		if now.Sub(conn.lastUsed) > p.idleTimeout {
			conn.conn.Close()
			delete(p.connections, address)
			atomic.AddInt64(&p.metrics.TotalClosed, 1)
			atomic.AddInt64(&p.metrics.IdleConnections, -1)
			atomic.AddInt64(&p.metrics.TotalConnections, -1)
			log.Printf("🧹 Cleaned idle connection to %s", address)
		}
	}
}

// healthCheckLoop — периодическая проверка здоровья соединений
func (p *ConnectionPool) healthCheckLoop() {
	ticker := time.NewTicker(p.healthCheck)
	defer ticker.Stop()

	for range ticker.C {
		p.checkHealth()
	}
}

// checkHealth — проверяет здоровье всех соединений
func (p *ConnectionPool) checkHealth() {
	p.mu.Lock()
	defer p.mu.Unlock()

	for address, conn := range p.connections {
		state := conn.conn.GetState()

		// Если канал не готов — помечаем как unhealthy
		if state != connectivity.Ready && state != connectivity.Idle {
			if conn.healthy {
				conn.healthy = false
				atomic.AddInt64(&p.metrics.UnhealthyConnections, 1)
				atomic.AddInt64(&p.metrics.TotalErrors, 1)
				log.Printf("⚠️ Connection to %s is unhealthy (state: %s)", address, state)
			}
		} else {
			if !conn.healthy {
				conn.healthy = true
				atomic.AddInt64(&p.metrics.UnhealthyConnections, -1)
				atomic.AddInt64(&p.metrics.TotalReconnects, 1)
				log.Printf("✅ Connection to %s is healthy again", address)
			}
		}

		// Если канал завершён — удаляем
		if state == connectivity.Shutdown {
			conn.conn.Close()
			delete(p.connections, address)
			atomic.AddInt64(&p.metrics.TotalClosed, 1)
			atomic.AddInt64(&p.metrics.TotalConnections, -1)
			if conn.inUse {
				atomic.AddInt64(&p.metrics.ActiveConnections, -1)
			} else {
				atomic.AddInt64(&p.metrics.IdleConnections, -1)
			}
			log.Printf("🔌 Removed shutdown connection to %s", address)
		}
	}
}

// metricsLoop — периодический сбор метрик
func (p *ConnectionPool) metricsLoop() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		p.updateMetrics()
	}
}

// updateMetrics — обновляет метрики пула
func (p *ConnectionPool) updateMetrics() {
	p.mu.RLock()
	defer p.mu.RUnlock()

	var active, idle, unhealthy int64
	var totalAge time.Duration

	for _, conn := range p.connections {
		if conn.inUse {
			active++
		} else {
			idle++
		}
		if !conn.healthy {
			unhealthy++
		}
		totalAge += time.Since(conn.createdAt)
	}

	atomic.StoreInt64(&p.metrics.ActiveConnections, active)
	atomic.StoreInt64(&p.metrics.IdleConnections, idle)
	atomic.StoreInt64(&p.metrics.UnhealthyConnections, unhealthy)
	atomic.StoreInt64(&p.metrics.TotalConnections, int64(len(p.connections)))

	if len(p.connections) > 0 {
		avgAge := totalAge / time.Duration(len(p.connections))
		p.metrics.AvgConnectionAge = avgAge
	}

	// Логируем метрики раз в минуту
	if time.Now().Second()%60 == 0 {
		log.Printf("📊 Pool metrics: total=%d, active=%d, idle=%d, unhealthy=%d, avg_age=%v",
			len(p.connections), active, idle, unhealthy, p.metrics.AvgConnectionAge)
	}
}

// GetMetrics возвращает метрики пула
func (p *ConnectionPool) GetMetrics() *ConnectionPoolMetrics {
	return &ConnectionPoolMetrics{
		TotalConnections:    atomic.LoadInt64(&p.metrics.TotalConnections),
		ActiveConnections:   atomic.LoadInt64(&p.metrics.ActiveConnections),
		IdleConnections:     atomic.LoadInt64(&p.metrics.IdleConnections),
		UnhealthyConnections: atomic.LoadInt64(&p.metrics.UnhealthyConnections),
		TotalCreated:        atomic.LoadInt64(&p.metrics.TotalCreated),
		TotalClosed:         atomic.LoadInt64(&p.metrics.TotalClosed),
		TotalErrors:         atomic.LoadInt64(&p.metrics.TotalErrors),
		TotalReconnects:     atomic.LoadInt64(&p.metrics.TotalReconnects),
		AvgConnectionAge:    p.metrics.AvgConnectionAge,
	}
}

// GetStats возвращает статистику пула
func (p *ConnectionPool) GetStats() map[string]interface{} {
	p.mu.RLock()
	defer p.mu.RUnlock()

	metrics := p.GetMetrics()

	stats := map[string]interface{}{
		"total_connections": len(p.connections),
		"max_size":          p.maxSize,
		"idle_timeout":      p.idleTimeout.String(),
		"health_check":      p.healthCheck.String(),
		"metrics": map[string]interface{}{
			"active":     metrics.ActiveConnections,
			"idle":       metrics.IdleConnections,
			"unhealthy":  metrics.UnhealthyConnections,
			"created":    metrics.TotalCreated,
			"closed":     metrics.TotalClosed,
			"errors":     metrics.TotalErrors,
			"reconnects": metrics.TotalReconnects,
			"avg_age":    metrics.AvgConnectionAge.String(),
		},
	}

	connections := make([]map[string]interface{}, 0, len(p.connections))
	for address, conn := range p.connections {
		connections = append(connections, map[string]interface{}{
			"address":    address,
			"created_at": conn.createdAt.Format(time.RFC3339),
			"last_used":  conn.lastUsed.Format(time.RFC3339),
			"in_use":     conn.inUse,
			"healthy":    conn.healthy,
			"state":      conn.conn.GetState().String(),
			"idle_for":   time.Since(conn.lastUsed).String(),
		})
	}
	stats["connections"] = connections

	return stats
}

// GetLoad возвращает загрузку пула (0-1)
func (p *ConnectionPool) GetLoad() float64 {
	p.mu.RLock()
	defer p.mu.RUnlock()

	if p.maxSize == 0 {
		return 0
	}

	inUse := 0
	for _, conn := range p.connections {
		if conn.inUse {
			inUse++
		}
	}

	return float64(inUse) / float64(p.maxSize)
}

// ========== GRPC Client Pool Wrapper ==========

// GRPCClientPool — пул gRPC клиентов для разных сервисов
type GRPCClientPool struct {
	mu      sync.RWMutex
	pools   map[string]*ConnectionPool
	config  *ConnectionPoolConfig
}

// NewGRPCClientPool создаёт пул gRPC клиентов
func NewGRPCClientPool(config *ConnectionPoolConfig) *GRPCClientPool {
	if config == nil {
		config = DefaultPoolConfig()
	}

	return &GRPCClientPool{
		pools:  make(map[string]*ConnectionPool),
		config: config,
	}
}

// GetClient получает gRPC клиент для указанного адреса
func (p *GRPCClientPool) GetClient(address string) (*grpc.ClientConn, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	// Получаем или создаём пул для этого адреса
	pool, exists := p.pools[address]
	if !exists {
		pool = NewConnectionPool(p.config)
		p.pools[address] = pool
	}

	return pool.GetConnection(address)
}

// ReleaseClient возвращает клиент в пул
func (p *GRPCClientPool) ReleaseClient(address string) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if pool, exists := p.pools[address]; exists {
		pool.ReleaseConnection(address)
	}
}

// CloseAll закрывает все пулы
func (p *GRPCClientPool) CloseAll() {
	p.mu.Lock()
	defer p.mu.Unlock()

	for address, pool := range p.pools {
		pool.CloseAll()
		delete(p.pools, address)
	}
}

// GetStats возвращает статистику всех пулов
func (p *GRPCClientPool) GetStats() map[string]interface{} {
	p.mu.RLock()
	defer p.mu.RUnlock()

	stats := make(map[string]interface{})
	for address, pool := range p.pools {
		stats[address] = pool.GetStats()
	}

	return stats
}

// GetTotalMetrics возвращает суммарные метрики по всем пулам
func (p *GRPCClientPool) GetTotalMetrics() *ConnectionPoolMetrics {
	p.mu.RLock()
	defer p.mu.RUnlock()

	total := &ConnectionPoolMetrics{}

	for _, pool := range p.pools {
		m := pool.GetMetrics()
		total.TotalConnections += m.TotalConnections
		total.ActiveConnections += m.ActiveConnections
		total.IdleConnections += m.IdleConnections
		total.UnhealthyConnections += m.UnhealthyConnections
		total.TotalCreated += m.TotalCreated
		total.TotalClosed += m.TotalClosed
		total.TotalErrors += m.TotalErrors
		total.TotalReconnects += m.TotalReconnects
	}

	return total
}

// ========== Утилиты для работы с соединениями ==========

// WithConnection выполняет функцию с соединением из пула
func WithConnection(pool *GRPCClientPool, address string, fn func(*grpc.ClientConn) error) error {
	conn, err := pool.GetClient(address)
	if err != nil {
		return err
	}
	defer pool.ReleaseClient(address)

	return fn(conn)
}

// WithTimeout выполняет функцию с таймаутом
func WithTimeout(ctx context.Context, timeout time.Duration, fn func(context.Context) error) error {
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	return fn(ctx)
}