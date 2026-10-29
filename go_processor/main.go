package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	_ "github.com/lib/pq"
	ort "github.com/yalue/onnxruntime_go"
	"gorgonia.org/gorgonia"

	"go_processor/internal/audio"
	"go_processor/internal/bridge"
	"model"
)

func main() {
	log.Println("🎵 Miku Music запущен")

	fmt.Println("========================================")
	fmt.Println("   Miku Music Server")
	fmt.Println("========================================")

	// Подключаемся к базе данных
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://postgres:password@localhost:5432/music_bot?sslmode=disable"
	}

	db, err := sql.Open("postgres", dbURL)
	if err != nil {
		log.Fatalf("❌ Failed to connect to database: %v", err)
	}
	defer db.Close()

	if err = db.Ping(); err != nil {
		log.Fatalf("❌ Failed to ping database: %v", err)
	}
	fmt.Println("✅ Database connected")

	// Создаём процессор аудио
	processor := audio.NewProcessor()

	// Настройка graceful shutdown
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// Настройка логирования
	logFile := model.SetupLogging()
	if logFile != nil {
		defer logFile.Close()
	}

	config := model.DefaultConfig()

	log.Println("Starting training...")
	log.Printf("Config: Epochs=%d, BatchSize=%d, LR=%.4f, HiddenDim=%d, EmbedDim=%d",
		config.Epochs, config.BatchSize, config.LearningRate, config.HiddenDim, config.EmbedDim)

	// Создаем граф
	g := gorgonia.NewGraph()

	// Создаем модель
	myModel := model.NewModel(g, config)

	// Строим модель
	if err := myModel.Build(); err != nil {
		log.Fatalf("Failed to build model: %v", err)
	}

	log.Println("Model built successfully")

	// Загружаем данные
	trainLoader, err := model.NewDataLoader("web/model/train_data.json", config.BatchSize, true)
	if err != nil {
		log.Fatalf("Failed to load data: %v", err)
	}

	// Обучаем
	trainer := model.NewTrainer(myModel, trainLoader, trainLoader, config)
	if err := trainer.Train(ctx); err != nil {
		if err == context.Canceled {
			log.Println("Training cancelled by user")
		} else {
			log.Fatalf("Training failed: %v", err)
		}
	}

	log.Println("✅ Training complete!")

	// После обучения, сохраняем модель в ONNX
	log.Println("Exporting model to ONNX...")
	if err := myModel.ExportToONNX(config.ModelPath); err != nil {
		log.Printf("Warning: failed to export to ONNX: %v", err)
	} else {
		log.Printf("✅ Model exported to %s", config.ModelPath)
	}

	// ========== Инициализация поиска ==========
	log.Println("Initializing search engine...")

	ort.SetSharedLibraryPath("/usr/local/lib/libonnxruntime.so")

	// Создаём embedding модель для поиска
	embedCfg := model.Config{
		ModelPath:     config.ModelPath,
		MaxSeqLen:     128,
		EmbeddingDim:  config.EmbedDim,
		PoolSize:      5,
		BatchSize:     8,
	}

	embedModel, err := model.NewEmbeddingModel(embedCfg)
	if err != nil {
		log.Fatalf("Failed to create embedding model: %v", err)
	}
	defer embedModel.Close()

	// Создаём поисковый индекс
	searchIndex := model.NewSearchIndex(embedModel)

	// Создаём поисковый движок
	searchEngine := model.NewDomainSearchEngine(searchIndex, 1*time.Hour)

	// Список доменов для поиска
	domains := []model.DomainConfig{
		{
			Name:        "youtube",
			BaseURL:     "https://youtube.com",
			SearchTypes: []string{"video", "music"},
			Priority:    10,
		},
		{
			Name:        "google",
			BaseURL:     "https://google.com",
			SearchTypes: []string{"general", "search"},
			Priority:    10,
		},
		{
			Name:        "spotify",
			BaseURL:     "https://spotify.com",
			SearchTypes: []string{"music", "podcast"},
			Priority:    9,
		},
	}

	// Добавляем все домены
	for _, domain := range domains {
		searchEngine.AddDomain(domain)
		log.Printf("Added domain: %s (%s)", domain.Name, domain.BaseURL)
	}

	// Запускаем краулеры для доменов (в отдельной горутине)
	go func() {
		for _, domain := range domains {
			select {
			case <-ctx.Done():
				log.Println("Crawling cancelled")
				return
			default:
				log.Printf("Crawling domain: %s", domain.Name)
				if err := model.CrawlDomain(ctx, domain, 100, searchIndex); err != nil {
					log.Printf("Error crawling %s: %v", domain.Name, err)
				}
			}
		}
		log.Println("Initial crawling completed!")
	}()

	// Создаём мосты
	javaGatewayURL := os.Getenv("JAVA_GATEWAY_URL")
	if javaGatewayURL == "" {
		javaGatewayURL = "http://localhost:8080"
	}
	elixirCoreURL := os.Getenv("ELIXIR_CORE_URL")
	if elixirCoreURL == "" {
		elixirCoreURL = "http://localhost:4000"
	}
	bridgeManager := bridge.NewBridgeManager(
		javaGatewayURL, // Java Gateway
		elixirCoreURL,  // Elixir Core
	)

	// Проверяем подключения (исправлено: используем ctx из graceful shutdown)
	healthCtx, healthCancel := context.WithTimeout(ctx, 5*time.Second)
	defer healthCancel()
	healthy := bridgeManager.CheckBridgesHealth(healthCtx)
	fmt.Printf("✅ Java Gateway: %v\n", healthy["java"])
	fmt.Printf("✅ Elixir Core: %v\n", healthy["elixir"])

	// ========== Единый HTTP роутер ==========
	mux := http.NewServeMux()

	// Search API
	mux.HandleFunc("/search", func(w http.ResponseWriter, r *http.Request) {
		query := r.URL.Query().Get("q")
		if query == "" {
			http.Error(w, "missing 'q' parameter", http.StatusBadRequest)
			return
		}
		topK := 10
		if tk := r.URL.Query().Get("top_k"); tk != "" {
			fmt.Sscanf(tk, "%d", &topK)
		}
		results, err := searchEngine.Search(r.Context(), query, topK)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(results)
	})

	// Audio Processor API
	mux.HandleFunc("/api/audio/process", func(w http.ResponseWriter, r *http.Request) {
		fmt.Printf("📥 Request from: %s\n", r.RemoteAddr)

		if r.Method != "POST" {
			http.Error(w, "Только POST", http.StatusMethodNotAllowed)
			return
		}

		var req struct {
			URL    string  `json:"url"`
			Format string  `json:"format"`
			Volume float64 `json:"volume"`
		}

		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			fmt.Printf("❌ JSON decode error: %v\n", err)
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		fmt.Printf("🎵 Processing audio: %s\n", req.URL)

		outputPath, err := processor.ProcessWithEffects(
			req.URL,
			req.Volume,
			0.0,
			1.0,
		)

		if err != nil {
			fmt.Printf("❌ Processing failed: %v\n", err)
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		fmt.Printf("✅ Processing complete: %s\n", outputPath)

		response := map[string]string{
			"status":      "processed",
			"output_path": outputPath,
			"format":      "opus",
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(response)
	})

	// Health check
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		fmt.Printf("🏥 Health check from: %s\n", r.RemoteAddr)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"healthy","services":["search","audio","bridge"]}`))
	})

	// Статистика
	mux.HandleFunc("/stats", func(w http.ResponseWriter, r *http.Request) {
		stats := bridgeManager.GetStats()
		// Добавляем метрики модели
		response := map[string]interface{}{
			"bridge":          stats,
			"embedding_model": embedModel.GetMetrics(),
		}
		json.NewEncoder(w).Encode(response)
	})

	// Информационный endpoint
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Printf("🌐 Root request from: %s\n", r.RemoteAddr)
		info := map[string]interface{}{
			"service": "Miku AI Platform",
			"version": "1.0.0",
			"endpoints": []string{
				"GET  /search?q=...",
				"POST /api/audio/process",
				"GET  /health",
				"GET  /stats",
			},
			"status": "running",
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(info)
	})

	// ========== Запуск единого сервера ==========
	server := &http.Server{
		Addr:    ":8080",
		Handler: mux,
	}

	go func() {
		fmt.Println("========================================")
		fmt.Println("🚀 Unified server started on :8080")
		fmt.Println("📡 Endpoints:")
		fmt.Println("  GET  http://localhost:8080/search?q=...")
		fmt.Println("  POST http://localhost:8080/api/audio/process")
		fmt.Println("  GET  http://localhost:8080/health")
		fmt.Println("  GET  http://localhost:8080/stats")
		fmt.Println("========================================")

		if err := server.ListenAndServe(); err != http.ErrServerClosed {
			log.Fatalf("Server error: %v", err)
		}
	}()

	// Ждём сигнала остановки
	<-ctx.Done()
	log.Println("Shutting down gracefully...")

	// Даём время на завершение
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()

	if err := server.Shutdown(shutdownCtx); err != nil {
		log.Printf("Server shutdown error: %v", err)
	}

	log.Println("Server stopped")
}