// client/metrics.go
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"
	"strings" 
)

// ========== Типы метрик ==========

// MetricType — тип метрики
type MetricType string

const (
	Counter   MetricType = "counter"
	Gauge     MetricType = "gauge"
	Histogram MetricType = "histogram"
)

// Metric — структура метрики
type Metric struct {
	Name      string                 `json:"name"`
	Type      MetricType             `json:"type"`
	Value     interface{}            `json:"value"`
	Labels    map[string]string      `json:"labels,omitempty"`
	Timestamp time.Time              `json:"timestamp"`
}

// ========== Клиентские метрики ==========

// ClientRequestMetrics — метрики запроса
type ClientRequestMetrics struct {
	Method    string
	Service   string
	Duration  time.Duration
	Success   bool
	Error     string
	Timestamp time.Time
}

// ClientMethodStats — статистика по методу
type ClientMethodStats struct {
	Total         int64
	Success       int64
	Failed        int64
	TotalDuration time.Duration
	MinDuration   time.Duration
	MaxDuration   time.Duration
	LastCalled    time.Time
	mu            sync.RWMutex
}

// ClientPoolStats — статистика пула клиентов
type ClientPoolStats struct {
	TotalConnections  int64
	ActiveConnections int64
	IdleConnections   int64
	TotalRequests     int64
	SuccessfulReqs    int64
	FailedReqs        int64
	AvgLatency        time.Duration
	mu                sync.RWMutex
}

// ClientMetricsConfig — конфигурация метрик
type ClientMetricsConfig struct {
	MaxHistorySize   int
	EnableHistogram  bool
	HistogramBuckets []float64
	LogInterval      time.Duration
	ServerMetricsURL string
}

// DefaultClientMetricsConfig — конфигурация по умолчанию
func DefaultClientMetricsConfig() *ClientMetricsConfig {
	return &ClientMetricsConfig{
		MaxHistorySize:   1000,
		EnableHistogram:  true,
		HistogramBuckets: []float64{1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000},
		LogInterval:      30 * time.Second,
		ServerMetricsURL: "http://localhost:8080",
	}
}

// ========== Клиентские алерты и команды ==========

// ClientAlertSeverity — уровень критичности алерта
type ClientAlertSeverity string

const (
	ClientAlertInfo     ClientAlertSeverity = "info"
	ClientAlertWarning  ClientAlertSeverity = "warning"
	ClientAlertError    ClientAlertSeverity = "error"
	ClientAlertCritical ClientAlertSeverity = "critical"
)

// ClientCommand — команды от сервера
type ClientCommand string

const (
	ClientCmdIncreaseTimeout ClientCommand = "increase_timeout"
	ClientCmdDecreaseTimeout ClientCommand = "decrease_timeout"
	ClientCmdReconnect       ClientCommand = "reconnect"
	ClientCmdShutdown        ClientCommand = "shutdown"
	ClientCmdReset           ClientCommand = "reset"
	ClientCmdIncreaseRetry   ClientCommand = "increase_retry"
	ClientCmdDecreaseRetry   ClientCommand = "decrease_retry"
	ClientCmdSwitchBackend   ClientCommand = "switch_backend"
	ClientCmdReportStatus    ClientCommand = "report_status"
)

// ClientAlert — структура алерта
type ClientAlert struct {
	Severity  ClientAlertSeverity    `json:"severity"`
	Message   string                 `json:"message"`
	Timestamp int64                  `json:"timestamp"`
	Details   map[string]interface{} `json:"details,omitempty"`
}

// ServerCommand — команда от сервера
type ServerCommand struct {
	Command   ClientCommand          `json:"command"`
	Params    map[string]interface{} `json:"params"`
	Timestamp int64                  `json:"timestamp"`
	Source    string                 `json:"source"`
}

// UnresolvedTask — нерешённая задача для отправки на сервер
type UnresolvedTask struct {
	TaskID      string `json:"task_id"`
	ErrorType   string `json:"error_type"`
	Error       string `json:"error"`
	Method      string `json:"method"`
	ClientID    string `json:"client_id"`
	Timestamp   int64  `json:"timestamp"`
	RetryCount  int    `json:"retry_count"`
	LastAttempt int64  `json:"last_attempt"`
}

// ========== MetricsCollector — основной сборщик ==========

// MetricsCollector — сборщик метрик для клиента
type MetricsCollector struct {
	mu               sync.RWMutex
	requests         []ClientRequestMetrics
	methodStats      map[string]*ClientMethodStats
	counters         map[string]int64
	gauges           map[string]int64
	histograms       map[string][]float64
	startTime        time.Time
	maxHistorySize   int
	poolStats        *ClientPoolStats
	alertHandlers    []func(ClientAlert)
	commandHandlers  map[ClientCommand][]func(ServerCommand)
	serverCommands   []ServerCommand
	alerts           []ClientAlert
	unresolvedTasks  map[string]*UnresolvedTask
	thresholds       map[string]interface{}
	serverMetricsURL string
	maxRetries       int
	retryDelay       time.Duration
	running          bool
	httpClient       *http.Client
}

// NewMetricsCollector создаёт новый сборщик метрик
func NewMetricsCollector(config *ClientMetricsConfig) *MetricsCollector {
	if config == nil {
		config = DefaultClientMetricsConfig()
	}

	c := &MetricsCollector{
		requests:         make([]ClientRequestMetrics, 0, config.MaxHistorySize),
		methodStats:      make(map[string]*ClientMethodStats),
		counters:         make(map[string]int64),
		gauges:           make(map[string]int64),
		histograms:       make(map[string][]float64),
		startTime:        time.Now(),
		maxHistorySize:   config.MaxHistorySize,
		poolStats:        &ClientPoolStats{},
		commandHandlers:  make(map[ClientCommand][]func(ServerCommand)),
		serverCommands:   make([]ServerCommand, 0, 100),
		alerts:           make([]ClientAlert, 0, 100),
		unresolvedTasks:  make(map[string]*UnresolvedTask),
		serverMetricsURL: config.ServerMetricsURL,
		maxRetries:       3,
		retryDelay:       5 * time.Second,
		running:          true,
		httpClient:       &http.Client{Timeout: 5 * time.Second},
		thresholds: map[string]interface{}{
			"error_rate":                0.1,
			"high_latency_ms":           5000.0,
			"connection_failures":       5,
			"request_rate":              100.0,
			"max_timeout_ms":            30000.0,
			"min_timeout_ms":            1000.0,
			"current_timeout_ms":        5000.0,
			"retry_count":               3,
			"backend":                   "primary",
			"critical_error_threshold":  3,
			"critical_error_window":     60.0,
		},
	}

	// Запускаем фоновую обработку
	go c.processLoop()

	return c
}

// ========== Фоновая обработка ==========

// processLoop — фоновая обработка
func (c *MetricsCollector) processLoop() {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		if !c.running {
			return
		}
		c.processUnresolvedTasks()
	}
}

// processUnresolvedTasks — обработка нерешённых задач
func (c *MetricsCollector) processUnresolvedTasks() {
	now := time.Now().Unix()
	var toSend []*UnresolvedTask

	c.mu.Lock()
	for taskID, task := range c.unresolvedTasks {
		if now-task.LastAttempt > int64(c.retryDelay.Seconds()) && task.RetryCount < c.maxRetries {
			task.RetryCount++
			task.LastAttempt = now
			toSend = append(toSend, task)
		}

		if task.RetryCount >= c.maxRetries {
			c.sendCriticalAlert(task)
			delete(c.unresolvedTasks, taskID)
		}
	}
	c.mu.Unlock()

	for _, task := range toSend {
		c.sendToServer(task)
	}
}

// sendToServer — отправка задачи на сервер
func (c *MetricsCollector) sendToServer(task *UnresolvedTask) {
	data, err := json.Marshal(task)
	if err != nil {
		log.Printf("❌ Failed to marshal task: %v", err)
		return
	}

	resp, err := c.httpClient.Post(c.serverMetricsURL+"/api/unresolved_task", "application/json", bytes.NewReader(data))
	if err != nil {
		log.Printf("❌ Failed to send task: %v", err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode == 200 {
		log.Printf("📤 Unresolved task %s sent to server", task.TaskID)
	}
}

// sendCriticalAlert — отправка критического алерта
func (c *MetricsCollector) sendCriticalAlert(task *UnresolvedTask) {
	c.triggerAlert(ClientAlertCritical,
		fmt.Sprintf("Unresolved task after %d retries: %s - %s", c.maxRetries, task.ErrorType, task.Method),
		map[string]interface{}{
			"task_id":   task.TaskID,
			"error":     task.Error,
			"method":    task.Method,
			"client_id": task.ClientID,
			"retries":   task.RetryCount,
		})

	data, _ := json.Marshal(map[string]interface{}{
		"type":        "critical_alert",
		"task_id":     task.TaskID,
		"error_count": task.RetryCount,
		"source":      "client_metrics",
	})

	c.httpClient.Post(c.serverMetricsURL+"/api/critical_alert", "application/json", bytes.NewReader(data))
}

// addUnresolvedTask — добавление нерешённой задачи
func (c *MetricsCollector) addUnresolvedTask(errorMsg, errorType, method, clientID string) {
	taskID := fmt.Sprintf("%d_%s_%d", time.Now().Unix(), method, time.Now().UnixNano())

	task := &UnresolvedTask{
		TaskID:      taskID,
		ErrorType:   errorType,
		Error:       errorMsg,
		Method:      method,
		ClientID:    clientID,
		Timestamp:   time.Now().Unix(),
		RetryCount:  0,
		LastAttempt: time.Now().Unix(),
	}

	c.mu.Lock()
	c.unresolvedTasks[taskID] = task
	c.mu.Unlock()

	log.Printf("📋 Added unresolved task %s: %s", taskID, errorMsg[:minInt(100, len(errorMsg))])
}

// triggerAlert — создание алерта
func (c *MetricsCollector) triggerAlert(severity ClientAlertSeverity, message string, details map[string]interface{}) {
	alert := ClientAlert{
		Severity:  severity,
		Message:   message,
		Timestamp: time.Now().Unix(),
		Details:   details,
	}

	c.mu.Lock()
	c.alerts = append(c.alerts, alert)
	if len(c.alerts) > 100 {
		c.alerts = c.alerts[1:]
	}
	c.mu.Unlock()

	log.Printf("🔔 ALERT [%s]: %s", severity, message)

	for _, handler := range c.alertHandlers {
		go handler(alert)
	}
}

// ========== Запись метрик ==========

// RecordRequest записывает метрики запроса
func (c *MetricsCollector) RecordRequest(req ClientRequestMetrics) {
	c.mu.Lock()
	defer c.mu.Unlock()

	// Добавляем в историю
	c.requests = append(c.requests, req)
	if len(c.requests) > c.maxHistorySize {
		c.requests = c.requests[1:]
	}

	// Обновляем статистику по методу
	key := req.Service + ":" + req.Method
	stats, exists := c.methodStats[key]
	if !exists {
		stats = &ClientMethodStats{
			MinDuration: time.Hour,
		}
		c.methodStats[key] = stats
	}

	stats.mu.Lock()
	defer stats.mu.Unlock()

	stats.Total++
	if req.Success {
		stats.Success++
	} else {
		stats.Failed++
	}

	stats.TotalDuration += req.Duration
	if req.Duration < stats.MinDuration {
		stats.MinDuration = req.Duration
	}
	if req.Duration > stats.MaxDuration {
		stats.MaxDuration = req.Duration
	}
	stats.LastCalled = req.Timestamp

	// Обновляем гистограмму
	if c.maxHistorySize > 0 {
		durationMs := float64(req.Duration.Milliseconds())
		c.histograms["request_duration_ms"] = append(c.histograms["request_duration_ms"], durationMs)
		if len(c.histograms["request_duration_ms"]) > c.maxHistorySize {
			c.histograms["request_duration_ms"] = c.histograms["request_duration_ms"][1:]
		}
	}

	// Проверяем критические ошибки
	if !req.Success && req.Error != "" && c.isCriticalError(req.Error) {
		c.addUnresolvedTask(req.Error, "critical", req.Method, "")
	}

	c.checkAlerts()
}

// IncrementCounter увеличивает счётчик
func (c *MetricsCollector) IncrementCounter(name string, delta int64) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.counters[name] += delta
}

// SetGauge устанавливает значение gauge
func (c *MetricsCollector) SetGauge(name string, value int64) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.gauges[name] = value
}

// RecordHistogram записывает значение в гистограмму
func (c *MetricsCollector) RecordHistogram(name string, value float64) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if _, exists := c.histograms[name]; !exists {
		c.histograms[name] = make([]float64, 0, c.maxHistorySize)
	}
	c.histograms[name] = append(c.histograms[name], value)
	if len(c.histograms[name]) > c.maxHistorySize {
		c.histograms[name] = c.histograms[name][1:]
	}
}

// UpdatePoolStats обновляет статистику пула
func (c *MetricsCollector) UpdatePoolStats(stats *ClientPoolStats) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.poolStats = stats
}

// ========== Команды от сервера ==========

// ReceiveServerCommand — получение команды от сервера
func (c *MetricsCollector) ReceiveServerCommand(cmdData map[string]interface{}) {
	cmd, ok := cmdData["command"].(string)
	if !ok {
		return
	}

	command := ClientCommand(cmd)
	params, _ := cmdData["params"].(map[string]interface{})

	serverCmd := ServerCommand{
		Command:   command,
		Params:    params,
		Timestamp: time.Now().Unix(),
		Source:    cmdData["source"].(string),
	}

	c.mu.Lock()
	c.serverCommands = append(c.serverCommands, serverCmd)
	if len(c.serverCommands) > 100 {
		c.serverCommands = c.serverCommands[1:]
	}
	c.mu.Unlock()

	log.Printf("📡 Received server command: %s (params: %v)", command, params)

	if handlers, ok := c.commandHandlers[command]; ok {
		for _, h := range handlers {
			go h(serverCmd)
		}
	}

	c.executeCommand(serverCmd)
}

// RegisterCommandHandler — регистрация обработчика команд
func (c *MetricsCollector) RegisterCommandHandler(cmd ClientCommand, handler func(ServerCommand)) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.commandHandlers[cmd] = append(c.commandHandlers[cmd], handler)
}

// executeCommand — выполнение команды от сервера
func (c *MetricsCollector) executeCommand(cmd ServerCommand) {
	switch cmd.Command {
	case ClientCmdIncreaseTimeout:
		current := c.thresholds["current_timeout_ms"].(float64)
		newVal := minFloat(current*1.5, c.thresholds["max_timeout_ms"].(float64))
		c.thresholds["current_timeout_ms"] = newVal
		log.Printf("⏱️ Timeout increased to %.0fms", newVal)

	case ClientCmdDecreaseTimeout:
		current := c.thresholds["current_timeout_ms"].(float64)
		newVal := maxFloat(current*0.8, c.thresholds["min_timeout_ms"].(float64))
		c.thresholds["current_timeout_ms"] = newVal
		log.Printf("⏱️ Timeout decreased to %.0fms", newVal)

	case ClientCmdReconnect:
		log.Printf("🔄 Reconnect command received")

	case ClientCmdShutdown:
		log.Printf("⚠️ Shutdown command received")

	case ClientCmdReset:
		log.Printf("🔄 Reset command received")
		c.Reset()

	case ClientCmdIncreaseRetry:
		newRetry := minInt(c.thresholds["retry_count"].(int)+1, 10)
		c.thresholds["retry_count"] = newRetry
		log.Printf("🔄 Retry count increased to %d", newRetry)

	case ClientCmdDecreaseRetry:
		newRetry := maxInt(c.thresholds["retry_count"].(int)-1, 1)
		c.thresholds["retry_count"] = newRetry
		log.Printf("🔄 Retry count decreased to %d", newRetry)

	case ClientCmdSwitchBackend:
		newBackend, _ := cmd.Params["backend"].(string)
		if newBackend != "" {
			oldBackend := c.thresholds["backend"].(string)
			c.thresholds["backend"] = newBackend
			log.Printf("🔄 Backend switched: %s -> %s", oldBackend, newBackend)
		}

	case ClientCmdReportStatus:
		log.Printf("📊 Status report requested")
	}
}

// ========== Проверка алертов ==========

// checkAlerts — проверка порогов алертов
func (c *MetricsCollector) checkAlerts() {
	stats := c.GetStats()

	if stats.ErrorRate > c.thresholds["error_rate"].(float64) {
		c.triggerAlert(ClientAlertError,
			fmt.Sprintf("High error rate: %.1f%%", stats.ErrorRate*100),
			map[string]interface{}{"error_rate": stats.ErrorRate})
	}

	if stats.AvgResponseTime > c.thresholds["high_latency_ms"].(float64) {
		c.triggerAlert(ClientAlertWarning,
			fmt.Sprintf("High latency: %.0fms", stats.AvgResponseTime),
			map[string]interface{}{"avg_response_time_ms": stats.AvgResponseTime})
	}

	// Проверка критических ошибок
	c.mu.RLock()
	now := time.Now().Unix()
	windowStart := now - int64(c.thresholds["critical_error_window"].(float64))
	errorsInWindow := 0
	for _, r := range c.requests {
		if !r.Success && r.Timestamp.Unix() > windowStart {
			errorsInWindow++
		}
	}
	c.mu.RUnlock()

	if errorsInWindow >= c.thresholds["critical_error_threshold"].(int) {
		c.triggerAlert(ClientAlertCritical,
			fmt.Sprintf("Critical error rate: %d errors in %.0fs", errorsInWindow, c.thresholds["critical_error_window"]),
			map[string]interface{}{"errors": errorsInWindow, "window": c.thresholds["critical_error_window"]})

		c.sendCriticalToServer(errorsInWindow)
	}
}

// sendCriticalToServer — отправка критического уведомления на сервер
func (c *MetricsCollector) sendCriticalToServer(errorCount int) {
	data, _ := json.Marshal(map[string]interface{}{
		"type":           "critical_error_rate",
		"error_count":    errorCount,
		"window_seconds": c.thresholds["critical_error_window"],
		"timestamp":      time.Now().Unix(),
		"source":         "client_metrics",
	})

	c.httpClient.Post(c.serverMetricsURL+"/api/critical_alert", "application/json", bytes.NewReader(data))
}

// isCriticalError — проверка критичности ошибки
func (c *MetricsCollector) isCriticalError(errMsg string) bool {
	patterns := []string{
		"memory", "out of memory", "oom",
		"connection refused", "connection reset",
		"timeout", "deadline exceeded",
		"unavailable", "internal error",
		"database", "crash", "fatal",
	}

	for _, p := range patterns {
		if len(errMsg) >= len(p) && contains(errMsg, p) {
			return true
		}
	}
	return false
}

// ========== Получение статистики ==========

// ClientStats — структура статистики
type ClientStats struct {
	UptimeSeconds     float64                  `json:"uptime_seconds"`
	TotalRequests     int64                    `json:"total_requests"`
	SuccessfulReqs    int64                    `json:"successful_requests"`
	FailedReqs        int64                    `json:"failed_requests"`
	SuccessRate       float64                  `json:"success_rate"`
	ErrorRate         float64                  `json:"error_rate"`
	RequestsPerSecond float64                  `json:"requests_per_second"`
	AvgResponseTime   float64                  `json:"avg_response_time_ms"`
	TotalAlerts       int64                    `json:"total_alerts"`
	CurrentTimeoutMs  float64                  `json:"current_timeout_ms"`
	RetryCount        int                      `json:"retry_count"`
	Backend           string                   `json:"backend"`
	UnresolvedTasks   int64                    `json:"unresolved_tasks"`
	Methods           map[string]MethodStats   `json:"methods"`
	Alerts            []AlertInfo              `json:"alerts"`
	ServerCommands    []CommandInfo            `json:"server_commands"`
}

// MethodStats — статистика метода
type MethodStats struct {
	Total         int64   `json:"total"`
	Success       int64   `json:"success"`
	Failed        int64   `json:"failed"`
	Alerts        int64   `json:"alerts"`
	AvgDurationMs float64 `json:"avg_duration_ms"`
	MinDurationMs float64 `json:"min_duration_ms"`
	MaxDurationMs float64 `json:"max_duration_ms"`
}

// AlertInfo — информация об алерте
type AlertInfo struct {
	Severity  string `json:"severity"`
	Message   string `json:"message"`
	Timestamp int64  `json:"timestamp"`
}

// CommandInfo — информация о команде
type CommandInfo struct {
	Command   string                 `json:"command"`
	Params    map[string]interface{} `json:"params"`
	Timestamp int64                  `json:"timestamp"`
}

// GetStats возвращает статистику
func (c *MetricsCollector) GetStats() ClientStats {
	c.mu.RLock()
	defer c.mu.RUnlock()

	uptime := time.Since(c.startTime).Seconds()

	now := time.Now()
	var recentDuration float64
	var recentCount int
	for _, r := range c.requests {
		if now.Sub(r.Timestamp) <= time.Minute {
			recentDuration += float64(r.Duration.Milliseconds())
			recentCount++
		}
	}
	avgRecentDuration := 0.0
	if recentCount > 0 {
		avgRecentDuration = recentDuration / float64(recentCount)
	}
	rps := float64(recentCount) / 60

	totalRequests := int64(0)
	totalSuccess := int64(0)
	totalFailed := int64(0)

	stats := ClientStats{
		UptimeSeconds:     uptime,
		TotalRequests:     0,
		SuccessfulReqs:    0,
		FailedReqs:        0,
		SuccessRate:       0,
		ErrorRate:         0,
		RequestsPerSecond: rps,
		AvgResponseTime:   avgRecentDuration,
		TotalAlerts:       int64(len(c.alerts)),
		CurrentTimeoutMs:  c.thresholds["current_timeout_ms"].(float64),
		RetryCount:        c.thresholds["retry_count"].(int),
		Backend:           c.thresholds["backend"].(string),
		UnresolvedTasks:   int64(len(c.unresolvedTasks)),
		Methods:           make(map[string]MethodStats),
		Alerts:            make([]AlertInfo, len(c.alerts)),
		ServerCommands:    make([]CommandInfo, len(c.serverCommands)),
	}

	for method, s := range c.methodStats {
		s.mu.RLock()
		avgDuration := 0.0
		if s.Total > 0 {
			avgDuration = float64(s.TotalDuration.Milliseconds()) / float64(s.Total)
		}
		stats.Methods[method] = MethodStats{
			Total:         s.Total,
			Success:       s.Success,
			Failed:        s.Failed,
			Alerts:        0,
			AvgDurationMs: avgDuration,
			MinDurationMs: float64(s.MinDuration.Milliseconds()),
			MaxDurationMs: float64(s.MaxDuration.Milliseconds()),
		}
		totalRequests += s.Total
		totalSuccess += s.Success
		totalFailed += s.Failed
		s.mu.RUnlock()
	}

	stats.TotalRequests = totalRequests
	stats.SuccessfulReqs = totalSuccess
	stats.FailedReqs = totalFailed
	if totalRequests > 0 {
		stats.SuccessRate = float64(totalSuccess) / float64(totalRequests)
		stats.ErrorRate = float64(totalFailed) / float64(totalRequests)
	}

	for i, a := range c.alerts {
		stats.Alerts[i] = AlertInfo{
			Severity:  string(a.Severity),
			Message:   a.Message,
			Timestamp: a.Timestamp,
		}
	}

	for i, cmd := range c.serverCommands {
		stats.ServerCommands[i] = CommandInfo{
			Command:   string(cmd.Command),
			Params:    cmd.Params,
			Timestamp: cmd.Timestamp,
		}
	}

	return stats
}

// GetRecentRequests возвращает последние запросы
func (c *MetricsCollector) GetRecentRequests(limit int) []ClientRequestMetrics {
	c.mu.RLock()
	defer c.mu.RUnlock()

	if limit <= 0 || limit > len(c.requests) {
		limit = len(c.requests)
	}

	if limit == 0 {
		return []ClientRequestMetrics{}
	}

	recent := make([]ClientRequestMetrics, limit)
	copy(recent, c.requests[len(c.requests)-limit:])
	return recent
}

// GetHistogram возвращает гистограмму
func (c *MetricsCollector) GetHistogram(name string, buckets []float64) map[string]interface{} {
	c.mu.RLock()
	defer c.mu.RUnlock()

	values, exists := c.histograms[name]
	if !exists || len(values) == 0 {
		return nil
	}

	if buckets == nil {
		buckets = []float64{1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000}
	}

	histogram := make(map[string]interface{})
	histogram["count"] = len(values)

	// Сортируем значения
	sorted := make([]float64, len(values))
	copy(sorted, values)
	for i := 0; i < len(sorted)-1; i++ {
		for j := i + 1; j < len(sorted); j++ {
			if sorted[i] > sorted[j] {
				sorted[i], sorted[j] = sorted[j], sorted[i]
			}
		}
	}

	// Вычисляем процентили
	percentiles := []float64{50, 75, 90, 95, 99, 99.9}
	for _, p := range percentiles {
		idx := int(float64(len(sorted)) * p / 100)
		if idx >= len(sorted) {
			idx = len(sorted) - 1
		}
		if idx >= 0 {
			histogram[fmt.Sprintf("p%.0f", p)] = sorted[idx]
		}
	}

	// Вычисляем бакеты
	bucketCounts := make(map[string]int)
	for _, bound := range buckets {
		count := 0
		for _, v := range sorted {
			if v <= bound {
				count++
			}
		}
		bucketCounts[fmt.Sprintf("le_%d", int(bound))] = count
	}
	histogram["buckets"] = bucketCounts

	return histogram
}

// ========== Управление ==========

// Reset сбрасывает все метрики
func (c *MetricsCollector) Reset() {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.requests = make([]ClientRequestMetrics, 0, c.maxHistorySize)
	c.methodStats = make(map[string]*ClientMethodStats)
	c.counters = make(map[string]int64)
	c.gauges = make(map[string]int64)
	c.histograms = make(map[string][]float64)
	c.startTime = time.Now()
	c.poolStats = &ClientPoolStats{}
	c.alerts = make([]ClientAlert, 0, 100)
	c.serverCommands = make([]ServerCommand, 0, 100)
	c.unresolvedTasks = make(map[string]*UnresolvedTask)
}

// SetThreshold — установка порога
func (c *MetricsCollector) SetThreshold(name string, value float64) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.thresholds[name] = value
	log.Printf("Alert threshold %s set to %.2f", name, value)
}

// Shutdown — остановка сборщика
func (c *MetricsCollector) Shutdown() {
	c.running = false
	log.Printf("Client metrics collector stopped")
}

// ========== Экспорт ==========

// ToJSON возвращает метрики в JSON
func (c *MetricsCollector) ToJSON() ([]byte, error) {
	stats := c.GetStats()
	return json.MarshalIndent(stats, "", "  ")
}

// ToPrometheus возвращает метрики в формате Prometheus
func (c *MetricsCollector) ToPrometheus() string {
	stats := c.GetStats()

	var output string

	// Uptime
	output += fmt.Sprintf("# HELP client_uptime_seconds Client uptime in seconds\n")
	output += fmt.Sprintf("# TYPE client_uptime_seconds gauge\n")
	output += fmt.Sprintf("client_uptime_seconds %f\n", stats.UptimeSeconds)

	// Requests
	output += fmt.Sprintf("# HELP client_requests_total Total requests\n")
	output += fmt.Sprintf("# TYPE client_requests_total counter\n")
	output += fmt.Sprintf("client_requests_total %d\n", stats.TotalRequests)

	output += fmt.Sprintf("# HELP client_requests_successful Successful requests\n")
	output += fmt.Sprintf("# TYPE client_requests_successful counter\n")
	output += fmt.Sprintf("client_requests_successful %d\n", stats.SuccessfulReqs)

	output += fmt.Sprintf("# HELP client_requests_failed Failed requests\n")
	output += fmt.Sprintf("# TYPE client_requests_failed counter\n")
	output += fmt.Sprintf("client_requests_failed %d\n", stats.FailedReqs)

	output += fmt.Sprintf("# HELP client_success_rate Success rate percentage\n")
	output += fmt.Sprintf("# TYPE client_success_rate gauge\n")
	output += fmt.Sprintf("client_success_rate %f\n", stats.SuccessRate*100)

	output += fmt.Sprintf("# HELP client_error_rate Error rate percentage\n")
	output += fmt.Sprintf("# TYPE client_error_rate gauge\n")
	output += fmt.Sprintf("client_error_rate %f\n", stats.ErrorRate*100)

	output += fmt.Sprintf("# HELP client_avg_response_time_ms Average response time\n")
	output += fmt.Sprintf("# TYPE client_avg_response_time_ms gauge\n")
	output += fmt.Sprintf("client_avg_response_time_ms %f\n", stats.AvgResponseTime)

	output += fmt.Sprintf("# HELP client_current_timeout_ms Current timeout\n")
	output += fmt.Sprintf("# TYPE client_current_timeout_ms gauge\n")
	output += fmt.Sprintf("client_current_timeout_ms %f\n", stats.CurrentTimeoutMs)

	output += fmt.Sprintf("# HELP client_retry_count Current retry count\n")
	output += fmt.Sprintf("# TYPE client_retry_count gauge\n")
	output += fmt.Sprintf("client_retry_count %d\n", stats.RetryCount)

	output += fmt.Sprintf("# HELP client_unresolved_tasks Unresolved tasks\n")
	output += fmt.Sprintf("# TYPE client_unresolved_tasks gauge\n")
	output += fmt.Sprintf("client_unresolved_tasks %d\n", stats.UnresolvedTasks)

	for method, s := range stats.Methods {
		methodSafe := sanitizeMetricName(method)
		output += fmt.Sprintf("# HELP client_method_%s_total Total calls to %s\n", methodSafe, method)
		output += fmt.Sprintf("# TYPE client_method_%s_total counter\n", methodSafe)
		output += fmt.Sprintf("client_method_%s_total %d\n", methodSafe, s.Total)

		output += fmt.Sprintf("# HELP client_method_%s_avg_duration_ms Average duration for %s\n", methodSafe, method)
		output += fmt.Sprintf("# TYPE client_method_%s_avg_duration_ms gauge\n", methodSafe)
		output += fmt.Sprintf("client_method_%s_avg_duration_ms %f\n", methodSafe, s.AvgDurationMs)
	}

	return output
}

// sanitizeMetricName очищает имя метрики для Prometheus
func sanitizeMetricName(name string) string {
	result := ""
	for _, c := range name {
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' {
			result += string(c)
		} else {
			result += "_"
		}
	}
	return result
}

// ========== Глобальный сборщик ==========

var (
	globalMetricsCollector     *MetricsCollector
	globalMetricsCollectorOnce sync.Once
)

// GetGlobalMetricsCollector возвращает глобальный сборщик метрик
func GetGlobalMetricsCollector() *MetricsCollector {
	globalMetricsCollectorOnce.Do(func() {
		globalMetricsCollector = NewMetricsCollector(nil)
	})
	return globalMetricsCollector
}

// RecordClientRequest глобальная запись метрики
func RecordClientRequest(service, method string, duration time.Duration, success bool, errorMsg string) {
	GetGlobalMetricsCollector().RecordRequest(ClientRequestMetrics{
		Method:    method,
		Service:   service,
		Duration:  duration,
		Success:   success,
		Error:     errorMsg,
		Timestamp: time.Now(),
	})
}

// minInt возвращает меньшее из двух целых чисел
func minInt(a, b int) int {
    if a < b {
        return a
    }
    return b
}

// maxInt возвращает большее из двух целых чисел
func maxInt(a, b int) int {
    if a > b {
        return a
    }
    return b
}

// minFloat возвращает меньшее из двух чисел с плавающей точкой
func minFloat(a, b float64) float64 {
    if a < b {
        return a
    }
    return b
}

// maxFloat возвращает большее из двух чисел с плавающей точкой
func maxFloat(a, b float64) float64 {
    if a > b {
        return a
    }
    return b
}

func contains(s, substr string) bool {
    return strings.Contains(s, substr)
}
