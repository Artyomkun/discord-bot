package main

import (
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "sync"
    "time"
    "strings"
)

// ========== Типы ошибок ==========

type ErrorType string

const (
    ErrorTypeServer   ErrorType = "server"
    ErrorTypeClient   ErrorType = "client"
    ErrorTypeNetwork  ErrorType = "network"
    ErrorTypeDatabase ErrorType = "database"
    ErrorTypeGRPC     ErrorType = "grpc"
    ErrorTypeUnresolved ErrorType = "unresolved"
)

type Resolution string

const (
    ResolutionIgnore         Resolution = "ignore"
    ResolutionRetry          Resolution = "retry"
    ResolutionFallback       Resolution = "fallback"
    ResolutionAlert          Resolution = "alert"
    ResolutionRestart        Resolution = "restart"
    ResolutionShutdown       Resolution = "shutdown"
    ResolutionNotifyClient   Resolution = "notify_client"
    ResolutionIncreaseTimeout Resolution = "increase_timeout"
    ResolutionDecreaseTimeout Resolution = "decrease_timeout"
    ResolutionSwitchBackend  Resolution = "switch_backend"
    ResolutionEscalate       Resolution = "escalate"
)

// ========== Структуры данных ==========

type ErrorRecord struct {
    Timestamp   float64     `json:"timestamp"`
    ErrorType   ErrorType   `json:"error_type"`
    Method      string      `json:"method"`
    Error       string      `json:"error"`
    ClientID    string      `json:"client_id,omitempty"`
    Resolution  Resolution  `json:"resolution,omitempty"`
    Resolved    bool        `json:"resolved"`
    ResolvedAt  *float64    `json:"resolved_at,omitempty"`
    Notes       string      `json:"notes,omitempty"`
    Source      string      `json:"source"` // server или client
}

type UnresolvedTask struct {
    TaskID      string `json:"task_id"`
    ErrorType   string `json:"error_type"`
    Error       string `json:"error"`
    Method      string `json:"method"`
    ClientID    string `json:"client_id"`
    Timestamp   int64  `json:"timestamp"`
    RetryCount  int    `json:"retry_count"`
    ReceivedAt  int64  `json:"received_at"`
    Status      string `json:"status"` // pending, processing, resolved
}

type ServerCommand struct {
    Command   string                 `json:"command"`
    Params    map[string]interface{} `json:"params"`
    Timestamp int64                  `json:"timestamp"`
    Source    string                 `json:"source"`
}

// ========== MetricsCollector (СЕРВЕРНЫЙ) ==========

type MetricsCollector struct {
    mu                  sync.RWMutex
    errorRecords        []ErrorRecord
    unresolvedTasks     map[string]*UnresolvedTask
    thresholds          map[string]interface{}
    resolutionHandlers  map[Resolution][]func(ErrorRecord)
    clientCommands      chan ServerCommand
    apiPort             int
    httpServer          *http.Server
    running             bool
}

type MetricsConfig struct {
    APIEPort            int
    DashboardDir        string
    ErrorWindowSeconds  int
    ErrorRateWarning    float64
    ErrorRateCritical   float64
    ConsecutiveErrors   int
}

func DefaultMetricsConfig() *MetricsConfig {
    return &MetricsConfig{
        APIEPort:          8080,
        DashboardDir:      "/tmp/grpc_dashboard",
        ErrorWindowSeconds: 60,
        ErrorRateWarning:   0.05,
        ErrorRateCritical:  0.1,
        ConsecutiveErrors:  5,
    }
}

func NewMetricsCollector(config *MetricsConfig) *MetricsCollector {
    if config == nil {
        config = DefaultMetricsConfig()
    }
    
    c := &MetricsCollector{
        errorRecords:       make([]ErrorRecord, 0),
        unresolvedTasks:    make(map[string]*UnresolvedTask),
        resolutionHandlers: make(map[Resolution][]func(ErrorRecord)),
        clientCommands:     make(chan ServerCommand, 100),
        apiPort:            config.APIEPort,
        running:            true,
        thresholds: map[string]interface{}{
            "error_rate_warning":     config.ErrorRateWarning,
            "error_rate_critical":    config.ErrorRateCritical,
            "time_window_seconds":    config.ErrorWindowSeconds,
            "consecutive_errors":     config.ConsecutiveErrors,
            "unresolved_alert_threshold": 3,
        },
    }
    
    // Запускаем API сервер
    c.startAPIServer()
    
    return c
}

// ========== API для приёма данных от клиента ==========

func (c *MetricsCollector) startAPIServer() {
    mux := http.NewServeMux()
    
    // Эндпоинт для приёма нерешённых задач от клиента
    mux.HandleFunc("/api/unresolved_task", c.handleUnresolvedTask)
    
    // Эндпоинт для приёма критических алертов от клиента
    mux.HandleFunc("/api/critical_alert", c.handleCriticalAlert)
    
    // Эндпоинт для получения статистики
    mux.HandleFunc("/api/stats", c.handleStats)
    
    // Эндпоинт для получения дашборда ошибок
    mux.HandleFunc("/api/dashboard", c.handleDashboard)
    
    // Prometheus эндпоинт
    mux.HandleFunc("/metrics", c.handlePrometheus)
    
    c.httpServer = &http.Server{
        Addr:    fmt.Sprintf(":%d", c.apiPort),
        Handler: mux,
    }
    
    go func() {
        log.Printf("🚀 Server metrics API listening on port %d", c.apiPort)
        if err := c.httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Printf("❌ Metrics API server error: %v", err)
        }
    }()
}

func (c *MetricsCollector) handleUnresolvedTask(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }
    
    var req struct {
        TaskID     string `json:"task_id"`
        ErrorType  string `json:"error_type"`
        Error      string `json:"error"`
        Method     string `json:"method"`
        ClientID   string `json:"client_id"`
        Timestamp  int64  `json:"timestamp"`
        RetryCount int    `json:"retry_count"`
    }
    
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    
    task := &UnresolvedTask{
        TaskID:     req.TaskID,
        ErrorType:  req.ErrorType,
        Error:      req.Error,
        Method:     req.Method,
        ClientID:   req.ClientID,
        Timestamp:  req.Timestamp,
        RetryCount: req.RetryCount,
        ReceivedAt: time.Now().Unix(),
        Status:     "pending",
    }
    
    c.mu.Lock()
    c.unresolvedTasks[task.TaskID] = task
    c.mu.Unlock()
    
    log.Printf("📥 Received unresolved task from client %s: %s", task.ClientID, task.Error[:minInt(100, len(task.Error))])
    
    // Создаём запись об ошибке
    errorRecord := ErrorRecord{
        Timestamp: float64(time.Now().Unix()),
        ErrorType: ErrorTypeUnresolved,
        Method:    task.Method,
        Error:     fmt.Sprintf("Unresolved from client: %s", task.Error),
        ClientID:  task.ClientID,
        Resolved:  false,
        Source:    "client",
    }
    c.addErrorRecord(errorRecord)
    
    // Принимаем решение по задаче
    resolution := c.decideResolution(errorRecord)
    
    // Если требуется эскалация
    if resolution == ResolutionEscalate || task.RetryCount >= 3 {
        c.escalateUnresolvedTask(task)
    }
    
    // Отправляем команду клиенту
    c.sendCommandToClient(task.ClientID, resolution, task.TaskID)
    
    // Отмечаем задачу как обработанную
    c.mu.Lock()
    if task, ok := c.unresolvedTasks[task.TaskID]; ok {
        task.Status = "resolved"
    }
    c.mu.Unlock()
    
    w.WriteHeader(http.StatusOK)
    json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func (c *MetricsCollector) handleCriticalAlert(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }
    
    var data map[string]interface{}
    if err := json.NewDecoder(r.Body).Decode(&data); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    
    log.Printf("🔴 Critical alert from client: %v", data)
    
    // Создаём запись об ошибке
    errorRecord := ErrorRecord{
        Timestamp: float64(time.Now().Unix()),
        ErrorType: ErrorTypeClient,
        Method:    "critical_alert",
        Error:     fmt.Sprintf("Critical alert from client: %v errors", data["error_count"]),
        ClientID:  data["client_id"].(string),
        Resolved:  false,
        Source:    "client",
    }
    c.addErrorRecord(errorRecord)
    
    // Эскалируем
    c.triggerResolution(ResolutionEscalate, errorRecord)
    
    w.WriteHeader(http.StatusOK)
    json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func (c *MetricsCollector) handleStats(w http.ResponseWriter, r *http.Request) {
    stats := c.GetStats()
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(stats)
}

func (c *MetricsCollector) handleDashboard(w http.ResponseWriter, r *http.Request) {
    dashboard := c.GetDashboard()
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(dashboard)
}

func (c *MetricsCollector) handlePrometheus(w http.ResponseWriter, r *http.Request) {
    prometheus := c.ToPrometheus()
    w.Header().Set("Content-Type", "text/plain")
    w.Write([]byte(prometheus))
}

// ========== Принятие решений ==========

func (c *MetricsCollector) decideResolution(errorRecord ErrorRecord) Resolution {
    c.mu.RLock()
    defer c.mu.RUnlock()
    
    errorMsg := strings.ToLower(errorRecord.Error)
    
    // Для нерешённых задач от клиента
    if errorRecord.Source == "client" || errorRecord.ErrorType == ErrorTypeUnresolved {
        return ResolutionEscalate
    }
    
    // По типу ошибки
    switch errorRecord.ErrorType {
    case ErrorTypeClient:
        return ResolutionNotifyClient
        
    case ErrorTypeNetwork:
        if strings.Contains(errorMsg, "timeout") {
            return ResolutionIncreaseTimeout
        }
        return ResolutionRetry
        
    case ErrorTypeDatabase:
        return ResolutionFallback
        
    case ErrorTypeGRPC:
        return ResolutionRestart
        
    case ErrorTypeServer:
        // Проверяем последовательные ошибки
        key := fmt.Sprintf("%s_%s", errorRecord.Method, errorRecord.Error[:minInt(50, len(errorRecord.Error))])
        consecutive := c.getConsecutiveErrors(key)
        if consecutive > c.thresholds["consecutive_errors"].(int) {
            return ResolutionRestart
        }
        return ResolutionRetry
    }
    
    // По содержимому ошибки
    if strings.Contains(errorMsg, "memory") || strings.Contains(errorMsg, "out of memory") {
        return ResolutionRestart
    }
    if strings.Contains(errorMsg, "connection refused") || strings.Contains(errorMsg, "connection reset") {
        return ResolutionRetry
    }
    if strings.Contains(errorMsg, "rate limit") || strings.Contains(errorMsg, "too many requests") {
        return ResolutionAlert
    }
    
    return ResolutionIgnore
}

func (c *MetricsCollector) getConsecutiveErrors(key string) int {
    count := 0
    now := time.Now().Unix()
    windowStart := now - int64(c.thresholds["time_window_seconds"].(int))
    
    for i := len(c.errorRecords) - 1; i >= 0; i-- {
        e := c.errorRecords[i]
        if int64(e.Timestamp) < windowStart {
            break
        }
        key2 := fmt.Sprintf("%s_%s", e.Method, e.Error[:minInt(50, len(e.Error))])
        if key2 == key {
            count++
        }
    }
    return count
}

func (c *MetricsCollector) escalateUnresolvedTask(task *UnresolvedTask) {
    log.Printf("🚨 ESCALATION: Unresolved task %s from client %s", task.TaskID, task.ClientID)
    
    errorRecord := ErrorRecord{
        Timestamp:  float64(time.Now().Unix()),
        ErrorType:  ErrorTypeClient,
        Method:     task.Method,
        Error:      fmt.Sprintf("ESCALATED: %s", task.Error),
        ClientID:   task.ClientID,
        Resolution: ResolutionEscalate,
        Resolved:   false,
        Source:     "client",
    }
    c.addErrorRecord(errorRecord)
    c.triggerResolution(ResolutionEscalate, errorRecord)
}

func (c *MetricsCollector) sendCommandToClient(clientID string, resolution Resolution, taskID string) {
    commandMap := map[Resolution]string{
        ResolutionRetry:           "increase_retry",
        ResolutionIncreaseTimeout: "increase_timeout",
        ResolutionDecreaseTimeout: "decrease_timeout",
        ResolutionSwitchBackend:   "switch_backend",
        ResolutionRestart:         "reconnect",
    }
    
    command, ok := commandMap[resolution]
    if !ok {
        command = "report_status"
    }
    
    cmd := ServerCommand{
        Command:   command,
        Params: map[string]interface{}{
            "task_id":    taskID,
            "resolution": string(resolution),
            "reason":     "unresolved_task",
        },
        Timestamp: time.Now().Unix(),
        Source:    "server_metrics",
    }
    
    // Отправляем команду в канал для обработки
    select {
    case c.clientCommands <- cmd:
        log.Printf("📤 Command %s queued for client %s", command, clientID)
    default:
        log.Printf("⚠️ Command queue full, dropping command for client %s", clientID)
    }
}

// ========== Получение команд для клиента ==========

func (c *MetricsCollector) GetNextCommand() (*ServerCommand, bool) {
    select {
    case cmd := <-c.clientCommands:
        return &cmd, true
    default:
        return nil, false
    }
}

// ========== Внутренние методы ==========

func (c *MetricsCollector) addErrorRecord(record ErrorRecord) {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.errorRecords = append(c.errorRecords, record)
    if len(c.errorRecords) > 10000 {
        c.errorRecords = c.errorRecords[1:]
    }
}

func (c *MetricsCollector) triggerResolution(resolution Resolution, errorRecord ErrorRecord) {
    c.mu.RLock()
    handlers := c.resolutionHandlers[resolution]
    c.mu.RUnlock()
    
    for _, handler := range handlers {
        go handler(errorRecord)
    }
}

func (c *MetricsCollector) RegisterResolutionHandler(resolution Resolution, handler func(ErrorRecord)) {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.resolutionHandlers[resolution] = append(c.resolutionHandlers[resolution], handler)
}

// ========== Получение статистики ==========

func (c *MetricsCollector) GetStats() map[string]interface{} {
    c.mu.RLock()
    defer c.mu.RUnlock()
    
    stats := map[string]interface{}{
        "total_errors":        len(c.errorRecords),
        "unresolved_errors":   c.countUnresolvedErrors(),
        "unresolved_tasks":    len(c.unresolvedTasks),
        "errors_by_type":      c.countErrorsByType(),
        "errors_by_source":    c.countErrorsBySource(),
        "errors_by_method":    c.countErrorsByMethod(),
        "unresolved_tasks_list": c.getUnresolvedTasksList(),
    }
    
    return stats
}

func (c *MetricsCollector) GetDashboard() map[string]interface{} {
    return c.GetStats()
}

func (c *MetricsCollector) countUnresolvedErrors() int {
    count := 0
    for _, e := range c.errorRecords {
        if !e.Resolved {
            count++
        }
    }
    return count
}

func (c *MetricsCollector) countErrorsByType() map[string]int {
    result := make(map[string]int)
    for _, e := range c.errorRecords {
        result[string(e.ErrorType)]++
    }
    return result
}

func (c *MetricsCollector) countErrorsBySource() map[string]int {
    result := make(map[string]int)
    for _, e := range c.errorRecords {
        result[e.Source]++
    }
    return result
}

func (c *MetricsCollector) countErrorsByMethod() map[string]int {
    result := make(map[string]int)
    for _, e := range c.errorRecords {
        result[e.Method]++
    }
    return result
}

func (c *MetricsCollector) getUnresolvedTasksList() []map[string]interface{} {
    result := make([]map[string]interface{}, 0, len(c.unresolvedTasks))
    for _, task := range c.unresolvedTasks {
        result = append(result, map[string]interface{}{
            "task_id":     task.TaskID,
            "error_type":  task.ErrorType,
            "error":       task.Error,
            "method":      task.Method,
            "client_id":   task.ClientID,
            "retry_count": task.RetryCount,
            "status":      task.Status,
        })
    }
    return result
}

// ========== Экспорт в Prometheus ==========

func (c *MetricsCollector) ToPrometheus() string {
    stats := c.GetStats()
    var output string
    
    output += fmt.Sprintf("# HELP server_total_errors Total errors recorded\n")
    output += fmt.Sprintf("# TYPE server_total_errors counter\n")
    output += fmt.Sprintf("server_total_errors %d\n", stats["total_errors"])
    
    output += fmt.Sprintf("# HELP server_unresolved_errors Unresolved errors\n")
    output += fmt.Sprintf("# TYPE server_unresolved_errors gauge\n")
    output += fmt.Sprintf("server_unresolved_errors %d\n", stats["unresolved_errors"])
    
    output += fmt.Sprintf("# HELP server_unresolved_tasks Unresolved tasks from clients\n")
    output += fmt.Sprintf("# TYPE server_unresolved_tasks gauge\n")
    output += fmt.Sprintf("server_unresolved_tasks %d\n", stats["unresolved_tasks"])
    
    if errorsByType, ok := stats["errors_by_type"].(map[string]int); ok {
        for errorType, count := range errorsByType {
            output += fmt.Sprintf("server_errors_by_type{type=\"%s\"} %d\n", errorType, count)
        }
    }
    
    if errorsBySource, ok := stats["errors_by_source"].(map[string]int); ok {
        for source, count := range errorsBySource {
            output += fmt.Sprintf("server_errors_by_source{source=\"%s\"} %d\n", source, count)
        }
    }
    
    return output
}

// ========== Управление ==========

func (c *MetricsCollector) Shutdown() {
    c.running = false
    if c.httpServer != nil {
        c.httpServer.Close()
    }
    log.Printf("Server metrics collector stopped")
}

// ========== Вспомогательные функции ==========

func minInt(a, b int) int {
    if a < b {
        return a
    }
    return b
}

// ========== Глобальные функции ==========

var (
    globalMetrics *MetricsCollector
    once          sync.Once
)

func GetGlobalMetrics() *MetricsCollector {
    once.Do(func() {
        globalMetrics = NewMetricsCollector(nil)
    })
    return globalMetrics
}

func GetNextCommand() (*ServerCommand, bool) {
    return GetGlobalMetrics().GetNextCommand()
}