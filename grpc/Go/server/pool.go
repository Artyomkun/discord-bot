package main

import (
	"context"
	"fmt"
	"log"
	"sync"
	"sync/atomic"
	"time"
)

// WorkerStatus — статус воркера
type WorkerStatus int

const (
	WorkerIdle     WorkerStatus = iota
	WorkerBusy
	WorkerStopped
	WorkerError
)

// WorkerMetrics — метрики воркера
type WorkerMetrics struct {
	ID                 int
	TasksProcessed     int64
	Errors             int64
	AvgTaskDuration    time.Duration
	LastActiveTime     time.Time
	Uptime             time.Duration
}

// PoolMetrics — метрики пула воркеров
type PoolMetrics struct {
	TotalWorkers        int32
	IdleWorkers         int32
	BusyWorkers         int32
	TotalTasks          int64
	ProcessedTasks      int64
	FailedTasks         int64
	AvgTaskDuration     time.Duration
	QueueSize           int
	WorkerUtilization   float64
	Throughput          float64 // tasks per second
	LastThroughputCalc  time.Time
	mu                  sync.RWMutex
}

// Worker — структура воркера
type Worker struct {
	ID             int
	Status         WorkerStatus
	TasksProcessed int64
	Errors         int64
	LastUsed       time.Time
	CreatedAt      time.Time
	mu             sync.Mutex
	cancel         context.CancelFunc
	metrics        *WorkerMetrics
}

// WorkerPool — пул воркеров для обработки задач
type WorkerPool struct {
	mu                 sync.RWMutex
	workers            map[int]*Worker
	maxWorkers         int
	minWorkers         int
	taskQueue          chan func()
	stopCh             chan struct{}
	wg                 sync.WaitGroup
	nextID             int
	autoScale          bool
	scaleUpThreshold   float64
	scaleDownThreshold float64
	stats              *PoolMetrics
	metrics            *PoolMetrics
	startTime          time.Time
}

// WorkerPoolConfig — конфигурация пула
type WorkerPoolConfig struct {
	MaxWorkers          int
	MinWorkers          int
	QueueSize           int
	AutoScale           bool
	ScaleUpThreshold    float64
	ScaleDownThreshold  float64
	ScaleInterval       time.Duration
	WorkerTimeout       time.Duration
}

// DefaultWorkerPoolConfig — конфигурация по умолчанию
func DefaultWorkerPoolConfig() *WorkerPoolConfig {
	return &WorkerPoolConfig{
		MaxWorkers:         10,
		MinWorkers:         2,
		QueueSize:          100,
		AutoScale:          true,
		ScaleUpThreshold:   0.7,
		ScaleDownThreshold: 0.3,
		ScaleInterval:      30 * time.Second,
		WorkerTimeout:      30 * time.Second,
	}
}

// NewWorkerPool создаёт новый пул воркеров
func NewWorkerPool(config *WorkerPoolConfig) *WorkerPool {
	if config == nil {
		config = DefaultWorkerPoolConfig()
	}

	pool := &WorkerPool{
		workers:            make(map[int]*Worker),
		maxWorkers:         config.MaxWorkers,
		minWorkers:         config.MinWorkers,
		taskQueue:          make(chan func(), config.QueueSize),
		stopCh:             make(chan struct{}),
		autoScale:          config.AutoScale,
		scaleUpThreshold:   config.ScaleUpThreshold,
		scaleDownThreshold: config.ScaleDownThreshold,
		metrics:            &PoolMetrics{},
		startTime:          time.Now(),
	}

	// Запускаем минимальное количество воркеров
	for i := 0; i < config.MinWorkers; i++ {
		pool.addWorker()
	}

	// Запускаем диспетчер задач
	go pool.dispatch()

	// Запускаем автоскейлинг
	if config.AutoScale {
		go pool.autoScaleLoop(config.ScaleInterval)
	}

	// Запускаем мониторинг и сбор метрик
	go pool.monitorLoop()
	go pool.metricsLoop()

	log.Printf("🚀 Worker pool started: min=%d, max=%d", config.MinWorkers, config.MaxWorkers)

	return pool
}

// addWorker добавляет нового воркера
func (p *WorkerPool) addWorker() {
	p.mu.Lock()
	defer p.mu.Unlock()

	if len(p.workers) >= p.maxWorkers {
		return
	}

	ctx, cancel := context.WithCancel(context.Background())

	worker := &Worker{
		ID:        p.nextID,
		Status:    WorkerIdle,
		LastUsed:  time.Now(),
		CreatedAt: time.Now(),
		cancel:    cancel,
		metrics: &WorkerMetrics{
			ID: p.nextID,
		},
	}
	p.nextID++
	p.workers[worker.ID] = worker

	atomic.AddInt32(&p.metrics.TotalWorkers, 1)
	atomic.AddInt32(&p.metrics.IdleWorkers, 1)

	// Запускаем воркера
	p.wg.Add(1)
	go p.workerLoop(worker, ctx)

	log.Printf("➕ Added worker %d (total: %d)", worker.ID, len(p.workers))
}

// removeWorker удаляет воркера
func (p *WorkerPool) removeWorker() {
	p.mu.Lock()
	defer p.mu.Unlock()

	if len(p.workers) <= p.minWorkers {
		return
	}

	// Находим idle воркера
	var idleWorker *Worker
	for _, w := range p.workers {
		if w.Status == WorkerIdle {
			idleWorker = w
			break
		}
	}

	if idleWorker != nil {
		idleWorker.cancel()
		delete(p.workers, idleWorker.ID)
		atomic.AddInt32(&p.metrics.TotalWorkers, -1)
		atomic.AddInt32(&p.metrics.IdleWorkers, -1)
		log.Printf("➖ Removed worker %d (total: %d)", idleWorker.ID, len(p.workers))
	}
}

// workerLoop — основной цикл воркера
func (p *WorkerPool) workerLoop(worker *Worker, ctx context.Context) {
	defer p.wg.Done()

	for {
		select {
		case <-ctx.Done():
			// Обновляем метрики воркера при остановке
			worker.metrics.Uptime = time.Since(worker.CreatedAt)
			worker.metrics.AvgTaskDuration = p.calculateWorkerAvgDuration(worker)
			log.Printf("🛑 Worker %d stopped (tasks: %d, errors: %d, uptime: %v)",
				worker.ID, worker.TasksProcessed, worker.Errors, worker.metrics.Uptime)
			return

		case task, ok := <-p.taskQueue:
			if !ok {
				return
			}

			worker.mu.Lock()
			worker.Status = WorkerBusy
			worker.LastUsed = time.Now()
			worker.mu.Unlock()

			atomic.AddInt32(&p.metrics.BusyWorkers, 1)
			atomic.AddInt32(&p.metrics.IdleWorkers, -1)

			// Выполняем задачу
			start := time.Now()
			func() {
				defer func() {
					if r := recover(); r != nil {
						log.Printf("❌ Worker %d panic: %v", worker.ID, r)
						atomic.AddInt64(&worker.Errors, 1)
						atomic.AddInt64(&p.metrics.FailedTasks, 1)
					}
				}()
				task()
			}()
			duration := time.Since(start)

			atomic.AddInt64(&worker.TasksProcessed, 1)
			atomic.AddInt64(&p.metrics.ProcessedTasks, 1)

			// Обновляем среднюю длительность
			p.updateAvgTaskDuration(duration)

			// Обновляем метрики воркера
			worker.metrics.TasksProcessed = atomic.LoadInt64(&worker.TasksProcessed)
			worker.metrics.Errors = atomic.LoadInt64(&worker.Errors)
			worker.metrics.LastActiveTime = time.Now()

			worker.mu.Lock()
			worker.Status = WorkerIdle
			worker.mu.Unlock()

			atomic.AddInt32(&p.metrics.BusyWorkers, -1)
			atomic.AddInt32(&p.metrics.IdleWorkers, 1)
		}
	}
}

// calculateWorkerAvgDuration вычисляет среднюю длительность задач воркера
func (p *WorkerPool) calculateWorkerAvgDuration(worker *Worker) time.Duration {
	processed := atomic.LoadInt64(&worker.TasksProcessed)
	if processed == 0 {
		return 0
	}
	// Здесь можно хранить общее время в воркере, пока упрощённо
	return p.metrics.AvgTaskDuration
}

// updateAvgTaskDuration обновляет среднюю длительность задач
func (p *WorkerPool) updateAvgTaskDuration(duration time.Duration) {
	processed := atomic.LoadInt64(&p.metrics.ProcessedTasks)
	if processed == 0 {
		return
	}

	oldAvg := p.metrics.AvgTaskDuration
	newAvg := time.Duration((int64(oldAvg)*(processed-1) + int64(duration)) / processed)
	p.metrics.mu.Lock()
	p.metrics.AvgTaskDuration = newAvg
	p.metrics.mu.Unlock()
}

// dispatch — диспетчер задач
func (p *WorkerPool) dispatch() {
	<-p.stopCh
	close(p.taskQueue)
}

// Submit отправляет задачу в пул
func (p *WorkerPool) Submit(task func()) bool {
	select {
	case p.taskQueue <- task:
		atomic.AddInt64(&p.metrics.TotalTasks, 1)
		p.updateQueueSize()
		return true
	default:
		log.Printf("⚠️ Task queue is full")
		return false
	}
}

// SubmitWithTimeout отправляет задачу с таймаутом
func (p *WorkerPool) SubmitWithTimeout(task func(), timeout time.Duration) error {
	select {
	case p.taskQueue <- task:
		atomic.AddInt64(&p.metrics.TotalTasks, 1)
		p.updateQueueSize()
		return nil
	case <-time.After(timeout):
		return context.DeadlineExceeded
	}
}

// SubmitAndWait отправляет задачу и ждёт её выполнения
func (p *WorkerPool) SubmitAndWait(task func()) {
	done := make(chan struct{})
	p.Submit(func() {
		task()
		close(done)
	})
	<-done
}

// updateQueueSize обновляет размер очереди в статистике
func (p *WorkerPool) updateQueueSize() {
	p.metrics.QueueSize = len(p.taskQueue)
}

// autoScaleLoop — цикл автоскейлинга
func (p *WorkerPool) autoScaleLoop(interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for range ticker.C {
		p.checkAndScale()
	}
}

// checkAndScale — проверяет загрузку и масштабирует
func (p *WorkerPool) checkAndScale() {
	if !p.autoScale {
		return
	}

	load := p.GetLoad()

	// Масштабируем вверх
	if load > p.scaleUpThreshold && len(p.workers) < p.maxWorkers {
		p.addWorker()
	}

	// Масштабируем вниз
	if load < p.scaleDownThreshold && len(p.workers) > p.minWorkers {
		p.removeWorker()
	}
}

// monitorLoop — цикл мониторинга
func (p *WorkerPool) monitorLoop() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		p.updateQueueSize()
		load := p.GetLoad()
		log.Printf("📊 Pool stats: workers=%d, load=%.2f, queue=%d, tasks=%d",
			len(p.workers), load, p.metrics.QueueSize, p.metrics.ProcessedTasks)
	}
}

// metricsLoop — сбор метрик
func (p *WorkerPool) metricsLoop() {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		p.updateMetrics()
	}
}

// updateMetrics обновляет метрики пула
func (p *WorkerPool) updateMetrics() {
	p.mu.RLock()
	defer p.mu.RUnlock()

	// Обновляем throughput
	now := time.Now()
	if !p.metrics.LastThroughputCalc.IsZero() {
		elapsed := now.Sub(p.metrics.LastThroughputCalc).Seconds()
		if elapsed > 0 {
			processed := atomic.LoadInt64(&p.metrics.ProcessedTasks)
			p.metrics.mu.Lock()
			p.metrics.Throughput = float64(processed) / elapsed
			p.metrics.mu.Unlock()
		}
	}
	p.metrics.LastThroughputCalc = now

	// Обновляем утилизацию
	if len(p.workers) > 0 {
		busy := atomic.LoadInt32(&p.metrics.BusyWorkers)
		utilization := float64(busy) / float64(len(p.workers))
		p.metrics.mu.Lock()
		p.metrics.WorkerUtilization = utilization
		p.metrics.mu.Unlock()
	}

	// Логируем метрики раз в 30 секунд
	if now.Second()%30 == 0 {
		log.Printf("📈 Pool metrics: throughput=%.2f tasks/s, utilization=%.2f%%, avg_duration=%v",
			p.metrics.Throughput,
			p.metrics.WorkerUtilization*100,
			p.metrics.AvgTaskDuration)
	}
}

// GetLoad возвращает текущую загрузку пула (0-1)
func (p *WorkerPool) GetLoad() float64 {
	if len(p.workers) == 0 {
		return 0
	}
	return float64(atomic.LoadInt32(&p.metrics.BusyWorkers)) / float64(len(p.workers))
}

// GetStats возвращает статистику пула
func (p *WorkerPool) GetStats() *PoolMetrics {
	return &PoolMetrics{
		TotalWorkers:    atomic.LoadInt32(&p.metrics.TotalWorkers),
		IdleWorkers:     atomic.LoadInt32(&p.metrics.IdleWorkers),
		BusyWorkers:     atomic.LoadInt32(&p.metrics.BusyWorkers),
		TotalTasks:      atomic.LoadInt64(&p.metrics.TotalTasks),
		ProcessedTasks:  atomic.LoadInt64(&p.metrics.ProcessedTasks),
		FailedTasks:     atomic.LoadInt64(&p.metrics.FailedTasks),
		AvgTaskDuration: p.metrics.AvgTaskDuration,
		QueueSize:       len(p.taskQueue),
		WorkerUtilization: p.metrics.WorkerUtilization,
		Throughput:      p.metrics.Throughput,
	}
}

// GetWorkerStats возвращает статистику по воркерам
func (p *WorkerPool) GetWorkerStats() []WorkerMetrics {
	p.mu.RLock()
	defer p.mu.RUnlock()

	stats := make([]WorkerMetrics, 0, len(p.workers))
	for _, w := range p.workers {
		stats = append(stats, WorkerMetrics{
			ID:              w.ID,
			TasksProcessed:  atomic.LoadInt64(&w.TasksProcessed),
			Errors:          atomic.LoadInt64(&w.Errors),
			AvgTaskDuration: p.calculateWorkerAvgDuration(w),
			LastActiveTime:  w.LastUsed,
			Uptime:          time.Since(w.CreatedAt),
		})
	}
	return stats
}

// Stop останавливает пул
func (p *WorkerPool) Stop() {
	log.Println("🛑 Stopping worker pool...")
	close(p.stopCh)

	// Ждём завершения всех задач
	done := make(chan struct{})
	go func() {
		p.wg.Wait()
		close(done)
	}()

	select {
	case <-done:
		log.Println("✅ Worker pool stopped gracefully")
		log.Printf("📊 Final stats: tasks=%d, failed=%d, avg_duration=%v",
			p.metrics.ProcessedTasks, p.metrics.FailedTasks, p.metrics.AvgTaskDuration)
	case <-time.After(30 * time.Second):
		log.Println("⚠️ Worker pool stop timeout")
	}
}

// ========== Task Pool для обработки команд ==========

// CommandTask — задача для обработки команды
type CommandTask struct {
	Command   *Command
	Response  chan interface{}
	Error     chan error
	Timeout   time.Duration
	CreatedAt time.Time
}

// CommandPoolMetrics — метрики пула команд
type CommandPoolMetrics struct {
	TotalCommands   int64
	ProcessedCommands int64
	FailedCommands  int64
	AvgCommandDuration time.Duration
	QueueSize       int
	mu              sync.RWMutex
}

// CommandPool — пул для обработки команд
type CommandPool struct {
	workerPool *WorkerPool
	tasks      chan *CommandTask
	stopCh     chan struct{}
	metrics    *CommandPoolMetrics
}

// NewCommandPool создаёт пул для команд
func NewCommandPool(maxWorkers int) *CommandPool {
	pool := &CommandPool{
		workerPool: NewWorkerPool(&WorkerPoolConfig{
			MaxWorkers: maxWorkers,
			MinWorkers: 2,
			QueueSize:  100,
			AutoScale:  true,
		}),
		tasks:   make(chan *CommandTask, 100),
		stopCh:  make(chan struct{}),
		metrics: &CommandPoolMetrics{},
	}

	go pool.processLoop()
	go pool.metricsLoop()

	return pool
}

// processLoop — цикл обработки команд
func (p *CommandPool) processLoop() {
	for {
		select {
		case <-p.stopCh:
			return
		case task := <-p.tasks:
			p.workerPool.Submit(func() {
				p.processTask(task)
			})
		}
	}
}

// processTask — обработка одной команды
func (p *CommandPool) processTask(task *CommandTask) {
	start := time.Now()
	atomic.AddInt64(&p.metrics.ProcessedCommands, 1)

	defer func() {
		if r := recover(); r != nil {
			atomic.AddInt64(&p.metrics.FailedCommands, 1)
			if task.Error != nil {
				task.Error <- fmt.Errorf("panic: %v", r)
			}
		}

		// Обновляем среднюю длительность
		duration := time.Since(start)
		p.updateAvgCommandDuration(duration)

		if task.Response != nil {
			task.Response <- map[string]interface{}{
				"success":   true,
				"message":   "Command processed",
				"duration":  duration.String(),
			}
		}
	}()

	// Здесь будет логика обработки команды
	// Пока заглушка
}

// updateAvgCommandDuration обновляет среднюю длительность команд
func (p *CommandPool) updateAvgCommandDuration(duration time.Duration) {
	processed := atomic.LoadInt64(&p.metrics.ProcessedCommands)
	if processed == 0 {
		return
	}

	oldAvg := p.metrics.AvgCommandDuration
	newAvg := time.Duration((int64(oldAvg)*(processed-1) + int64(duration)) / processed)
	p.metrics.mu.Lock()
	p.metrics.AvgCommandDuration = newAvg
	p.metrics.mu.Unlock()
}

// metricsLoop — сбор метрик команд
func (p *CommandPool) metricsLoop() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		p.metrics.QueueSize = len(p.tasks)
		processed := atomic.LoadInt64(&p.metrics.ProcessedCommands)
		failed := atomic.LoadInt64(&p.metrics.FailedCommands)

		if processed > 0 {
			log.Printf("📊 Command pool: processed=%d, failed=%d, success_rate=%.2f%%, avg_duration=%v, queue=%d",
				processed,
				failed,
				float64(processed-failed)/float64(processed)*100,
				p.metrics.AvgCommandDuration,
				p.metrics.QueueSize)
		}
	}
}

// Submit отправляет команду в пул
func (p *CommandPool) Submit(cmd *Command) (*CommandResponse, error) {
	task := &CommandTask{
		Command:   cmd,
		Response:  make(chan interface{}, 1),
		Error:     make(chan error, 1),
		Timeout:   30 * time.Second,
		CreatedAt: time.Now(),
	}

	atomic.AddInt64(&p.metrics.TotalCommands, 1)

	select {
	case p.tasks <- task:
		select {
		case resp := <-task.Response:
			return &CommandResponse{
				Success: true,
				Data:    resp,
			}, nil
		case err := <-task.Error:
			atomic.AddInt64(&p.metrics.FailedCommands, 1)
			return nil, err
		case <-time.After(task.Timeout):
			atomic.AddInt64(&p.metrics.FailedCommands, 1)
			return nil, context.DeadlineExceeded
		}
	case <-time.After(5 * time.Second):
		return nil, fmt.Errorf("task queue is full")
	}
}

// GetCommandPoolMetrics возвращает метрики пула команд
func (p *CommandPool) GetCommandPoolMetrics() *CommandPoolMetrics {
	return &CommandPoolMetrics{
		TotalCommands:      atomic.LoadInt64(&p.metrics.TotalCommands),
		ProcessedCommands:  atomic.LoadInt64(&p.metrics.ProcessedCommands),
		FailedCommands:     atomic.LoadInt64(&p.metrics.FailedCommands),
		AvgCommandDuration: p.metrics.AvgCommandDuration,
		QueueSize:          len(p.tasks),
	}
}

// Stop останавливает пул команд
func (p *CommandPool) Stop() {
	close(p.stopCh)
	p.workerPool.Stop()

	log.Printf("📊 Command pool final: total=%d, processed=%d, failed=%d, avg_duration=%v",
		p.metrics.TotalCommands,
		p.metrics.ProcessedCommands,
		p.metrics.FailedCommands,
		p.metrics.AvgCommandDuration)
}

// CommandResponse — ответ на команду
type CommandResponse struct {
	Success bool
	Message string
	Data    interface{}
}