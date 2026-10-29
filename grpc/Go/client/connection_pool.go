package main

import (
	"context"
	"fmt"
	"log"
	"sync"
	"sync/atomic"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/connectivity"
	"google.golang.org/grpc/credentials/insecure"
)

// ClientConnectionPool — пул клиентских gRPC соединений
type ClientConnectionPool struct {
	mu              sync.RWMutex
	connections     map[string]*ClientPooledConnection
	address         string
	maxSize         int
	minSize         int
	idleTimeout     time.Duration
	healthCheck     time.Duration
	metrics         *ClientPoolMetrics
	nextID          int
	startTime       time.Time
}

// ClientPooledConnection — соединение в пуле
type ClientPooledConnection struct {
	ID         int
	Conn       *grpc.ClientConn
	Address    string
	CreatedAt  time.Time
	LastUsed   time.Time
	InUse      bool
	Healthy    bool
	UseCount   int64
	ErrorCount int64
}

// ClientPoolMetrics — метрики пула клиентских соединений
type ClientPoolMetrics struct {
	TotalConnections     int64
	ActiveConnections    int64
	IdleConnections      int64
	UnhealthyConnections int64
	TotalCreated         int64
	TotalClosed          int64
	TotalErrors          int64
	TotalReconnects      int64
	TotalUses            int64
	AvgConnectionAge     time.Duration
	Uptime               int64 // в наносекундах
	mu                   sync.RWMutex
}

// ClientPoolConfig — конфигурация клиентского пула
type ClientPoolConfig struct {
	Address        string
	MaxSize        int
	MinSize        int
	IdleTimeout    time.Duration
	HealthCheck    time.Duration
	ConnectTimeout time.Duration
}

// DefaultClientPoolConfig — конфигурация по умолчанию
func DefaultClientPoolConfig() *ClientPoolConfig {
	return &ClientPoolConfig{
		Address:        "localhost:50052",
		MaxSize:        10,
		MinSize:        2,
		IdleTimeout:    5 * time.Minute,
		HealthCheck:    30 * time.Second,
		ConnectTimeout: 10 * time.Second,
	}
}

// NewClientConnectionPool создаёт новый пул клиентских соединений
func NewClientConnectionPool(config *ClientPoolConfig) *ClientConnectionPool {
	if config == nil {
		config = DefaultClientPoolConfig()
	}

	pool := &ClientConnectionPool{
		connections: make(map[string]*ClientPooledConnection),
		address:     config.Address,
		maxSize:     config.MaxSize,
		minSize:     config.MinSize,
		idleTimeout: config.IdleTimeout,
		healthCheck: config.HealthCheck,
		metrics:     &ClientPoolMetrics{},
		startTime:   time.Now(),
	}

	// Создаём минимальное количество соединений
	for i := 0; i < config.MinSize; i++ {
		pool.addConnection()
	}

	// Запускаем фоновые задачи
	go pool.cleanupLoop()
	go pool.healthCheckLoop()
	go pool.metricsLoop()

	log.Printf("🚀 Client pool started for %s: min=%d, max=%d", config.Address, config.MinSize, config.MaxSize)

	return pool
}

// addConnection добавляет новое соединение
func (p *ClientConnectionPool) addConnection() *ClientPooledConnection {
	p.mu.Lock()
	defer p.mu.Unlock()

	if len(p.connections) >= p.maxSize {
		return nil
	}

	conn, err := grpc.NewClient(p.address, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Printf("❌ Failed to create connection to %s: %v", p.address, err)
		atomic.AddInt64(&p.metrics.TotalErrors, 1)
		return nil
	}

	p.nextID++
	pooled := &ClientPooledConnection{
		ID:        p.nextID,
		Conn:      conn,
		Address:   p.address,
		CreatedAt: time.Now(),
		LastUsed:  time.Now(),
		InUse:     false,
		Healthy:   true,
	}

	p.connections[p.address] = pooled

	atomic.AddInt64(&p.metrics.TotalConnections, 1)
	atomic.AddInt64(&p.metrics.IdleConnections, 1)
	atomic.AddInt64(&p.metrics.TotalCreated, 1)

	log.Printf("➕ Added client connection %d (total: %d)", pooled.ID, len(p.connections))

	return pooled
}

// removeConnection удаляет соединение
func (p *ClientConnectionPool) removeConnection(conn *ClientPooledConnection) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if conn.Conn != nil {
		conn.Conn.Close()
	}
	delete(p.connections, conn.Address)

	atomic.AddInt64(&p.metrics.TotalClosed, 1)
	atomic.AddInt64(&p.metrics.TotalConnections, -1)
	if conn.InUse {
		atomic.AddInt64(&p.metrics.ActiveConnections, -1)
	} else {
		atomic.AddInt64(&p.metrics.IdleConnections, -1)
	}
	if !conn.Healthy {
		atomic.AddInt64(&p.metrics.UnhealthyConnections, -1)
	}

	log.Printf("➖ Removed client connection %d (total: %d)", conn.ID, len(p.connections))
}

// GetConnection получает соединение из пула
func (p *ClientConnectionPool) GetConnection() (*grpc.ClientConn, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	// Ищем свободное здоровое соединение
	for _, conn := range p.connections {
		if !conn.InUse && conn.Healthy {
			conn.InUse = true
			conn.LastUsed = time.Now()
			atomic.AddInt64(&conn.UseCount, 1)
			atomic.AddInt64(&p.metrics.ActiveConnections, 1)
			atomic.AddInt64(&p.metrics.IdleConnections, -1)
			atomic.AddInt64(&p.metrics.TotalUses, 1)

			// Проверяем состояние канала
			state := conn.Conn.GetState()
			if state == connectivity.Ready || state == connectivity.Idle {
				return conn.Conn, nil
			}

			// Канал не готов — помечаем как unhealthy и удаляем
			conn.Healthy = false
			atomic.AddInt64(&p.metrics.UnhealthyConnections, 1)
			p.removeConnection(conn)
		}
	}

	// Создаём новое, если не превышен лимит
	if len(p.connections) < p.maxSize {
		conn := p.addConnection()
		if conn != nil {
			conn.InUse = true
			conn.LastUsed = time.Now()
			atomic.AddInt64(&conn.UseCount, 1)
			atomic.AddInt64(&p.metrics.ActiveConnections, 1)
			atomic.AddInt64(&p.metrics.IdleConnections, -1)
			atomic.AddInt64(&p.metrics.TotalUses, 1)
			return conn.Conn, nil
		}
	}

	return nil, fmt.Errorf("no available connections to %s", p.address)
}

// ReleaseConnection возвращает соединение в пул
func (p *ClientConnectionPool) ReleaseConnection(conn *grpc.ClientConn) {
	p.mu.Lock()
	defer p.mu.Unlock()

	for _, pooled := range p.connections {
		if pooled.Conn == conn && pooled.InUse {
			pooled.InUse = false
			pooled.LastUsed = time.Now()
			atomic.AddInt64(&p.metrics.ActiveConnections, -1)
			atomic.AddInt64(&p.metrics.IdleConnections, 1)
			return
		}
	}
}

// MarkUnhealthy помечает соединение как unhealthy
func (p *ClientConnectionPool) MarkUnhealthy(conn *grpc.ClientConn) {
	p.mu.Lock()
	defer p.mu.Unlock()

	for _, pooled := range p.connections {
		if pooled.Conn == conn && pooled.Healthy {
			pooled.Healthy = false
			atomic.AddInt64(&p.metrics.UnhealthyConnections, 1)
			atomic.AddInt64(&p.metrics.TotalErrors, 1)
			log.Printf("⚠️ Client connection %d marked unhealthy", pooled.ID)
		}
	}
}

// cleanupLoop — периодическая очистка неактивных соединений
func (p *ClientConnectionPool) cleanupLoop() {
	ticker := time.NewTicker(p.idleTimeout / 2)
	defer ticker.Stop()

	for range ticker.C {
		p.cleanupIdle()
	}
}

// cleanupIdle — очищает неактивные соединения
func (p *ClientConnectionPool) cleanupIdle() {
	p.mu.Lock()
	defer p.mu.Unlock()

	now := time.Now()
	for _, conn := range p.connections {
		if conn.InUse {
			continue
		}
		if now.Sub(conn.LastUsed) > p.idleTimeout && len(p.connections) > p.minSize {
			p.removeConnection(conn)
		}
	}
}

// healthCheckLoop — периодическая проверка здоровья соединений
func (p *ClientConnectionPool) healthCheckLoop() {
	ticker := time.NewTicker(p.healthCheck)
	defer ticker.Stop()

	for range ticker.C {
		p.checkHealth()
	}
}

// checkHealth — проверяет здоровье всех соединений
func (p *ClientConnectionPool) checkHealth() {
	p.mu.Lock()
	defer p.mu.Unlock()

	for _, conn := range p.connections {
		state := conn.Conn.GetState()

		if state != connectivity.Ready && state != connectivity.Idle {
			if conn.Healthy {
				conn.Healthy = false
				atomic.AddInt64(&p.metrics.UnhealthyConnections, 1)
				atomic.AddInt64(&p.metrics.TotalErrors, 1)
				log.Printf("⚠️ Client connection %d unhealthy (state: %s)", conn.ID, state)
			}
		} else {
			if !conn.Healthy {
				conn.Healthy = true
				atomic.AddInt64(&p.metrics.UnhealthyConnections, -1)
				atomic.AddInt64(&p.metrics.TotalReconnects, 1)
				log.Printf("✅ Client connection %d healthy again", conn.ID)
			}
		}

		if state == connectivity.Shutdown {
			p.removeConnection(conn)
		}
	}
}

// metricsLoop — сбор метрик
func (p *ClientConnectionPool) metricsLoop() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		p.updateMetrics()
	}
}

// updateMetrics — обновляет метрики
func (p *ClientConnectionPool) updateMetrics() {
	p.mu.RLock()
	defer p.mu.RUnlock()

	var totalAge time.Duration
	var active, idle, unhealthy int64

	for _, conn := range p.connections {
		if conn.InUse {
			active++
		} else {
			idle++
		}
		if !conn.Healthy {
			unhealthy++
		}
		totalAge += time.Since(conn.CreatedAt)
	}

	atomic.StoreInt64(&p.metrics.ActiveConnections, active)
	atomic.StoreInt64(&p.metrics.IdleConnections, idle)
	atomic.StoreInt64(&p.metrics.UnhealthyConnections, unhealthy)
	atomic.StoreInt64(&p.metrics.Uptime, int64(time.Since(p.startTime)))

	if len(p.connections) > 0 {
		avgAge := totalAge / time.Duration(len(p.connections))
		p.metrics.AvgConnectionAge = avgAge
	}

	// Логируем раз в минуту
	if time.Now().Second()%60 == 0 {
		log.Printf("📊 Client pool metrics: total=%d, active=%d, idle=%d, unhealthy=%d, uses=%d, avg_age=%v, uptime=%v",
			len(p.connections), active, idle, unhealthy,
			atomic.LoadInt64(&p.metrics.TotalUses),
			p.metrics.AvgConnectionAge,
			time.Duration(atomic.LoadInt64(&p.metrics.Uptime)).Round(time.Second))
	}
}

// GetStats возвращает статистику пула
func (p *ClientConnectionPool) GetStats() map[string]interface{} {
	p.mu.RLock()
	defer p.mu.RUnlock()

	metrics := p.GetMetrics()

	// Преобразуем Uptime из int64 (наносекунды) в time.Duration
	uptime := time.Duration(metrics.Uptime)

	stats := map[string]interface{}{
		"address":           p.address,
		"total_connections": len(p.connections),
		"max_size":          p.maxSize,
		"min_size":          p.minSize,
		"idle_timeout":      p.idleTimeout.String(),
		"health_check":      p.healthCheck.String(),
		"uptime":            uptime.String(),
		"metrics": map[string]interface{}{
			"active":     metrics.ActiveConnections,
			"idle":       metrics.IdleConnections,
			"unhealthy":  metrics.UnhealthyConnections,
			"created":    metrics.TotalCreated,
			"closed":     metrics.TotalClosed,
			"errors":     metrics.TotalErrors,
			"reconnects": metrics.TotalReconnects,
			"uses":       metrics.TotalUses,
			"avg_age":    metrics.AvgConnectionAge.String(),
		},
	}

	connections := make([]map[string]interface{}, 0, len(p.connections))
	for _, conn := range p.connections {
		connections = append(connections, map[string]interface{}{
			"id":          conn.ID,
			"created_at":  conn.CreatedAt.Format(time.RFC3339),
			"last_used":   conn.LastUsed.Format(time.RFC3339),
			"in_use":      conn.InUse,
			"healthy":     conn.Healthy,
			"state":       conn.Conn.GetState().String(),
			"use_count":   atomic.LoadInt64(&conn.UseCount),
			"error_count": atomic.LoadInt64(&conn.ErrorCount),
		})
	}
	stats["connections"] = connections

	return stats
}

// GetMetrics возвращает метрики пула
func (p *ClientConnectionPool) GetMetrics() *ClientPoolMetrics {
	p.metrics.mu.RLock()
	defer p.metrics.mu.RUnlock()

	return &ClientPoolMetrics{
		TotalConnections:     atomic.LoadInt64(&p.metrics.TotalConnections),
		ActiveConnections:    atomic.LoadInt64(&p.metrics.ActiveConnections),
		IdleConnections:      atomic.LoadInt64(&p.metrics.IdleConnections),
		UnhealthyConnections: atomic.LoadInt64(&p.metrics.UnhealthyConnections),
		TotalCreated:         atomic.LoadInt64(&p.metrics.TotalCreated),
		TotalClosed:          atomic.LoadInt64(&p.metrics.TotalClosed),
		TotalErrors:          atomic.LoadInt64(&p.metrics.TotalErrors),
		TotalReconnects:      atomic.LoadInt64(&p.metrics.TotalReconnects),
		TotalUses:            atomic.LoadInt64(&p.metrics.TotalUses),
		AvgConnectionAge:     p.metrics.AvgConnectionAge,
		Uptime:               atomic.LoadInt64(&p.metrics.Uptime), // int64 наносекунды
	}
}

// GetLoad возвращает загрузку пула (0-1)
func (p *ClientConnectionPool) GetLoad() float64 {
	p.mu.RLock()
	defer p.mu.RUnlock()

	if p.maxSize == 0 {
		return 0
	}

	inUse := 0
	for _, conn := range p.connections {
		if conn.InUse {
			inUse++
		}
	}
	return float64(inUse) / float64(p.maxSize)
}

// Close закрывает все соединения
func (p *ClientConnectionPool) Close() {
	p.mu.Lock()
	defer p.mu.Unlock()

	for _, conn := range p.connections {
		if conn.Conn != nil {
			conn.Conn.Close()
		}
	}
	p.connections = make(map[string]*ClientPooledConnection)

	log.Printf("🔌 Client pool closed for %s (uptime: %v, total_uses: %d)",
		p.address,
		time.Since(p.startTime).Round(time.Second),
		atomic.LoadInt64(&p.metrics.TotalUses))
}

// ========== Клиент с пулом ==========

// PooledClient — клиент с пулом соединений
type PooledClient struct {
	pool    *ClientConnectionPool
	address string
}

// NewPooledClient создаёт клиент с пулом
func NewPooledClient(address string, config *ClientPoolConfig) *PooledClient {
	if config == nil {
		config = DefaultClientPoolConfig()
	}
	config.Address = address

	return &PooledClient{
		pool:    NewClientConnectionPool(config),
		address: address,
	}
}

// Call выполняет gRPC вызов с управлением соединением
func (c *PooledClient) Call(ctx context.Context, fn func(*grpc.ClientConn) error) error {
	conn, err := c.pool.GetConnection()
	if err != nil {
		return err
	}
	defer c.pool.ReleaseConnection(conn)

	err = fn(conn)
	if err != nil && isConnectionError(err) {
		c.pool.MarkUnhealthy(conn)
	}
	return err
}

// GetStats возвращает статистику
func (c *PooledClient) GetStats() map[string]interface{} {
	return c.pool.GetStats()
}

// GetMetrics возвращает метрики
func (c *PooledClient) GetMetrics() *ClientPoolMetrics {
	return c.pool.GetMetrics()
}

// GetLoad возвращает загрузку
func (c *PooledClient) GetLoad() float64 {
	return c.pool.GetLoad()
}

// Close закрывает клиент
func (c *PooledClient) Close() {
	c.pool.Close()
}