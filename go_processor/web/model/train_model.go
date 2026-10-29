package model

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math"
	"math/rand"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	ort "github.com/yalue/onnxruntime_go"
	"google.golang.org/protobuf/proto"
	"gorgonia.org/gorgonia"
	"gorgonia.org/tensor"
	pb "onnx"
)

// ========== Конфигурация ==========

type TrainConfig struct {
	DataPath        string
	Epochs          int
	BatchSize       int
	LearningRate    float64
	HiddenDim       int
	EmbedDim        int
	ModelPath       string
	EarlyStopping   int
	ValSplit        float64
	InputSize       int
	InputChannels   int
	CheckpointEpoch int
}

func DefaultConfig() *TrainConfig {
	return &TrainConfig{
		Epochs:          100,
		BatchSize:       1,
		LearningRate:    0.001,
		HiddenDim:       288,
		EmbedDim:        288,
		ModelPath:       "web/model/model.onnx",
		EarlyStopping:   10,
		ValSplit:        0.1,
		InputSize:       3,  // ← 3x3 изображение
		InputChannels:   32, // ← 32 канала (ваши 288 / 3 / 3 = 32)
		CheckpointEpoch: 10,
	}
}

// ========== DataLoader ==========

type DataLoader struct {
	inputs       [][]float32
	outputs      [][]float32
	batch        int
	idx          int
	shuffle      bool
	totalBatches int
}

func NewDataLoader(dataPath string, batchSize int, shuffle bool) (*DataLoader, error) {
	file, err := os.Open(dataPath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	bytes, err := io.ReadAll(file)
	if err != nil {
		return nil, err
	}

	var dataset []struct {
		Input  []float32 `json:"input"`
		Output []float32 `json:"output"`
	}
	if err := json.Unmarshal(bytes, &dataset); err != nil {
		return nil, err
	}

	if len(dataset) == 0 {
		return nil, fmt.Errorf("empty dataset")
	}

	inputs := make([][]float32, len(dataset))
	outputs := make([][]float32, len(dataset))
	for i, d := range dataset {
		if len(d.Input) == 0 {
			return nil, fmt.Errorf("empty input at index %d", i)
		}
		if len(d.Output) == 0 {
			return nil, fmt.Errorf("empty output at index %d", i)
		}
		inputs[i] = d.Input
		outputs[i] = d.Output
	}

	totalBatches := (len(dataset) + batchSize - 1) / batchSize

	return &DataLoader{
		inputs:       inputs,
		outputs:      outputs,
		batch:        batchSize,
		shuffle:      shuffle,
		totalBatches: totalBatches,
	}, nil
}

func (dl *DataLoader) Validate() error {
	if len(dl.inputs) == 0 {
		return fmt.Errorf("no input data")
	}
	if len(dl.inputs) != len(dl.outputs) {
		return fmt.Errorf("inputs/outputs mismatch: %d vs %d", len(dl.inputs), len(dl.outputs))
	}
	if len(dl.inputs[0]) == 0 {
		return fmt.Errorf("empty input vector")
	}
	if len(dl.outputs[0]) == 0 {
		return fmt.Errorf("empty output vector")
	}
	return nil
}

func (dl *DataLoader) Next() (inputs, outputs []float32, ok bool) {
	if dl.idx >= len(dl.inputs) {
		return nil, nil, false
	}

	inputData := dl.inputs[dl.idx]
	outputData := dl.outputs[dl.idx]
	dl.idx++
	reshapedInput := make([]float32, 32*3*3)
	copy(reshapedInput, inputData)

	return reshapedInput, outputData, true
}

func (dl *DataLoader) Reset() {
	dl.idx = 0
	if dl.shuffle {
		rand.Shuffle(len(dl.inputs), func(i, j int) {
			dl.inputs[i], dl.inputs[j] = dl.inputs[j], dl.inputs[i]
			dl.outputs[i], dl.outputs[j] = dl.outputs[j], dl.outputs[i]
		})
	}
}

func (dl *DataLoader) Len() int {
	return len(dl.inputs)
}

func (dl *DataLoader) Batches() int {
	return dl.totalBatches
}

// ========== Модель ==========

type Model struct {
	g       *gorgonia.ExprGraph
	input   *gorgonia.Node
	target  *gorgonia.Node
	pred    *gorgonia.Node
	loss    *gorgonia.Node
	weights []*gorgonia.Node
	config  *TrainConfig
}

func NewModel(g *gorgonia.ExprGraph, config *TrainConfig) *Model {
	return &Model{g: g, config: config}
}

func (m *Model) Build() error {
	// Вход как 4D тензор [batch, channels, height, width]
	m.input = gorgonia.NewTensor(
		m.g,
		tensor.Float32,
		4,
		gorgonia.WithShape(m.config.BatchSize, m.config.InputChannels, m.config.InputSize, m.config.InputSize),
		gorgonia.WithName("input"),
	)

	// Flatten: [batch, 32, 3, 3] -> [batch, 288]
	flatShape := []int{m.config.BatchSize, m.config.InputChannels * m.config.InputSize * m.config.InputSize}
	flat := gorgonia.Must(gorgonia.Reshape(m.input, flatShape))

	// Скрытый слой 1: 288 -> 256
	w1 := gorgonia.NewMatrix(m.g, tensor.Float32,
		gorgonia.WithShape(288, m.config.HiddenDim),
		gorgonia.WithName("w1"),
		gorgonia.WithInit(gorgonia.GlorotU(1.0)))
	b1 := gorgonia.NewVector(m.g, tensor.Float32,
		gorgonia.WithShape(m.config.HiddenDim),
		gorgonia.WithName("b1"),
		gorgonia.WithInit(gorgonia.Zeroes()))

	l1 := gorgonia.Must(gorgonia.Mul(flat, w1))
	l1 = gorgonia.Must(gorgonia.Add(l1, b1))
	r1 := gorgonia.Must(gorgonia.Rectify(l1))

	// Скрытый слой 2: 256 -> 256
	w2 := gorgonia.NewMatrix(m.g, tensor.Float32,
		gorgonia.WithShape(m.config.HiddenDim, m.config.HiddenDim),
		gorgonia.WithName("w2"),
		gorgonia.WithInit(gorgonia.GlorotU(1.0)))
	b2 := gorgonia.NewVector(m.g, tensor.Float32,
		gorgonia.WithShape(m.config.HiddenDim),
		gorgonia.WithName("b2"),
		gorgonia.WithInit(gorgonia.Zeroes()))

	l2 := gorgonia.Must(gorgonia.Mul(r1, w2))
	l2 = gorgonia.Must(gorgonia.Add(l2, b2))
	r2 := gorgonia.Must(gorgonia.Rectify(l2))

	// Выходной слой: 256 -> 288
	w3 := gorgonia.NewMatrix(m.g, tensor.Float32,
		gorgonia.WithShape(m.config.HiddenDim, 288),
		gorgonia.WithName("w3"),
		gorgonia.WithInit(gorgonia.GlorotU(1.0)))
	b3 := gorgonia.NewVector(m.g, tensor.Float32,
		gorgonia.WithShape(288),
		gorgonia.WithName("b3"),
		gorgonia.WithInit(gorgonia.Zeroes()))

	l3 := gorgonia.Must(gorgonia.Mul(r2, w3))
	l3 = gorgonia.Must(gorgonia.Add(l3, b3))

	// Reshape обратно в 4D [batch, 32, 3, 3]
	m.pred = gorgonia.Must(gorgonia.Reshape(l3, []int{
		m.config.BatchSize,
		m.config.InputChannels,
		m.config.InputSize,
		m.config.InputSize,
	}))

	// Target тоже 4D
	m.target = gorgonia.NewTensor(
		m.g,
		tensor.Float32,
		4,
		gorgonia.WithShape(m.config.BatchSize, m.config.InputChannels, m.config.InputSize, m.config.InputSize),
		gorgonia.WithName("target"),
	)

	// Loss (MSE между 4D тензорами)
	diff := gorgonia.Must(gorgonia.Sub(m.pred, m.target))
	sq := gorgonia.Must(gorgonia.Square(diff))
	m.loss = gorgonia.Must(gorgonia.Mean(sq))

	// Weights
	m.weights = []*gorgonia.Node{w1, b1, w2, b2, w3, b3}

	// Gradients
	if _, err := gorgonia.Grad(m.loss, m.weights...); err != nil {
		return fmt.Errorf("failed to compute gradients: %v", err)
	}

	return nil
}

// ========== Метрики ==========

func (m *Metrics) Summary() string {
	return fmt.Sprintf("Epochs: %d, Best Loss: %.6f, Last Train: %.6f, Last Val: %.6f, Duration: %v",
		m.TotalEpochs, m.BestLoss, m.LastTrainLoss, m.LastValLoss, m.EndTime.Sub(m.StartTime))
}

// ========== Прогресс-бар ==========

func printProgress(current, total int, prefix string) {
	if total == 0 {
		return
	}
	percent := float64(current) / float64(total) * 100
	barLength := 40
	filled := int(percent / 100 * float64(barLength))
	if filled > barLength {
		filled = barLength
	}
	bar := ""
	for i := 0; i < barLength; i++ {
		if i < filled {
			bar += "█"
		} else {
			bar += "░"
		}
	}
	fmt.Printf("\r%s: [%s] %.1f%% (%d/%d)", prefix, bar, percent, current, total)
	if current == total {
		fmt.Println()
	}
}

// ========== Тренировочный процесс ==========

type Trainer struct {
	model       *Model
	solver      gorgonia.Solver
	trainLoader *DataLoader
	valLoader   *DataLoader
	config      *TrainConfig
	bestLoss    float64
	noImprove   int
	metrics     *Metrics
}

func NewTrainer(model *Model, trainLoader, valLoader *DataLoader, config *TrainConfig) *Trainer {
	solver := gorgonia.NewAdamSolver(
		gorgonia.WithLearnRate(config.LearningRate),
		gorgonia.WithBatchSize(float64(config.BatchSize)),
	)

	// Добавьте эти строки:
	if trainLoader == nil {
		trainLoader = &DataLoader{
			inputs:  [][]float32{},
			outputs: [][]float32{},
			batch:   config.BatchSize,
		}
	}
	if valLoader == nil {
		valLoader = &DataLoader{
			inputs:  [][]float32{},
			outputs: [][]float32{},
			batch:   config.BatchSize,
		}
	}

	return &Trainer{
		model:       model,
		solver:      solver,
		trainLoader: trainLoader,
		valLoader:   valLoader,
		config:      config,
		bestLoss:    1e9,
		metrics:     &Metrics{StartTime: time.Now(), BestLoss: 1e9},
	}
}

func (t *Trainer) trainEpoch() float64 {
	t.trainLoader.Reset()
	var totalLoss float64
	batches := 0
	totalBatches := t.trainLoader.Batches()

	for {
		inputData, targetData, ok := t.trainLoader.Next()
		if !ok {
			break
		}

		// Обработка батча с защитой от panic
		loss, err := t.processBatch(inputData, targetData)
		if err != nil {
			log.Printf("Batch error: %v", err)
			continue
		}

		totalLoss += loss
		batches++
		printProgress(batches, totalBatches, "Training")
	}

	if batches == 0 {
		return 0
	}
	return totalLoss / float64(batches)
}

// Выносим обработку батча в отдельную функцию с защитой от panic
func (t *Trainer) processBatch(inputData, targetData []float32) (float64, error) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("Recovered from panic: %v", r)
		}
	}()

	// Проверяем размеры данных
	expectedInputSize := t.config.BatchSize * t.config.InputChannels * t.config.InputSize * t.config.InputSize
	expectedTargetSize := t.config.BatchSize * t.config.EmbedDim

	if len(inputData) != expectedInputSize {
		return 0, fmt.Errorf("input size mismatch: got %d, expected %d", len(inputData), expectedInputSize)
	}
	if len(targetData) != expectedTargetSize {
		return 0, fmt.Errorf("target size mismatch: got %d, expected %d", len(targetData), expectedTargetSize)
	}

	// Создаем тензоры
	inputTensor := tensor.New(
		tensor.WithShape(t.config.BatchSize, t.config.InputChannels, t.config.InputSize, t.config.InputSize),
		tensor.WithBacking(inputData),
		tensor.Of(tensor.Float32),
	)

	targetTensor := tensor.New(
		tensor.WithShape(t.config.BatchSize, t.config.InputChannels, t.config.InputSize, t.config.InputSize),
		tensor.WithBacking(targetData),
		tensor.Of(tensor.Float32),
	)

	// Устанавливаем значения в граф
	if err := gorgonia.Let(t.model.input, inputTensor); err != nil {
		return 0, fmt.Errorf("let input: %w", err)
	}
	if err := gorgonia.Let(t.model.target, targetTensor); err != nil {
		return 0, fmt.Errorf("let target: %w", err)
	}

	// Создаем VM с градиентами
	vm := gorgonia.NewTapeMachine(t.model.g,
		gorgonia.BindDualValues(t.model.weights...),
	)
	defer vm.Close()

	// Запускаем forward и backward
	if err := vm.RunAll(); err != nil {
		return 0, fmt.Errorf("vm run: %w", err)
	}

	// Конвертируем веса в ValueGrad
	gradValues := make([]gorgonia.ValueGrad, len(t.model.weights))
	for i, w := range t.model.weights {
		gradValues[i] = w
	}

	// Обновляем веса
	if err := t.solver.Step(gradValues); err != nil {
		return 0, fmt.Errorf("solver step: %w", err)
	}

	// Получаем значение loss
	if t.model.loss.Value() == nil {
		return 0, fmt.Errorf("loss value is nil")
	}

	var lossVal float64
	switch v := t.model.loss.Value().Data().(type) {
	case float32:
		lossVal = float64(v)
	case float64:
		lossVal = v
	default:
		lossVal = 0
	}

	return lossVal, nil
}

func (t *Trainer) validate() float64 {
	t.valLoader.Reset()
	var totalLoss float64
	batches := 0
	totalBatches := t.valLoader.Batches()

	for {
		inputData, targetData, ok := t.valLoader.Next()
		if !ok {
			break
		}

		// Проверяем размеры данных
		expectedInputSize := t.config.BatchSize * t.config.InputChannels * t.config.InputSize * t.config.InputSize
		expectedTargetSize := t.config.BatchSize * t.config.EmbedDim

		if len(inputData) != expectedInputSize {
			log.Printf("Validation input size mismatch: got %d, expected %d", len(inputData), expectedInputSize)
			continue
		}
		if len(targetData) != expectedTargetSize {
			log.Printf("Validation target size mismatch: got %d, expected %d", len(targetData), expectedTargetSize)
			continue
		}

		// Создаем тензоры
		inputTensor := tensor.New(
			tensor.WithShape(t.config.BatchSize, t.config.InputChannels, t.config.InputSize, t.config.InputSize),
			tensor.WithBacking(inputData),
			tensor.Of(tensor.Float32),
		)

		targetTensor := tensor.New(
			tensor.WithShape(t.config.BatchSize, t.config.InputChannels, t.config.InputSize, t.config.InputSize),
			tensor.WithBacking(targetData),
			tensor.Of(tensor.Float32),
		)

		// Устанавливаем значения в граф
		if err := gorgonia.Let(t.model.input, inputTensor); err != nil {
			log.Printf("Validation Let input error: %v", err)
			continue
		}
		if err := gorgonia.Let(t.model.target, targetTensor); err != nil {
			log.Printf("Validation Let target error: %v", err)
			continue
		}

		// Для валидации используем VM без градиентов (не обновляем веса)
		vm := gorgonia.NewTapeMachine(t.model.g)

		// Запускаем forward pass
		if err := vm.RunAll(); err != nil {
			log.Printf("Validation VM Run error: %v", err)
			vm.Close()
			continue
		}
		vm.Close()

		// Получаем значение loss
		if t.model.loss.Value() != nil {
			var lossVal float64
			switch v := t.model.loss.Value().Data().(type) {
			case float32:
				lossVal = float64(v)
			case float64:
				lossVal = v
			default:
				lossVal = 0
			}
			totalLoss += lossVal
		}
		batches++
		printProgress(batches, totalBatches, "Validation")
	}

	if batches == 0 {
		return 0
	}
	return totalLoss / float64(batches)
}

func (t *Trainer) saveCheckpoint(epoch int) error {
	checkpointPath := filepath.Join(filepath.Dir(t.config.ModelPath))
	checkpointFile, err := os.Create(checkpointPath)
	if err != nil {
		return err
	}
	defer checkpointFile.Close()

	// Сохраняем веса
	for _, w := range t.model.weights {
		if w.Value() != nil {
			if data, ok := w.Value().Data().([]float32); ok {
				name := []byte(w.Name())
				size := int32(len(data))
				checkpointFile.Write(name)
				binary.Write(checkpointFile, binary.LittleEndian, size)
				binary.Write(checkpointFile, binary.LittleEndian, data)
			}
		}
	}

	return nil
}

func (t *Trainer) saveModel() error {
	// Проверяем, что модель действительно обучилась
	if t.bestLoss == 1e9 || t.bestLoss == 0 {
		log.Printf("⚠️  Model not trained yet (loss: %f), skipping save", t.bestLoss)
		return nil
	}

	log.Printf("Saving model: %s", t.config.ModelPath)

	// Создаём директорию
	dir := filepath.Dir(t.config.ModelPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create directory: %w", err)
	}

	// Сохраняем веса в бинарный файл
	weightsFile, err := os.Create(t.config.ModelPath)
	if err != nil {
		return fmt.Errorf("failed to create file: %w", err)
	}
	defer weightsFile.Close()

	// Сохраняем конфигурацию
	configBytes, _ := json.Marshal(t.config)
	if err := binary.Write(weightsFile, binary.LittleEndian, uint32(len(configBytes))); err != nil {
		return err
	}
	if _, err := weightsFile.Write(configBytes); err != nil {
		return err
	}

	// Сохраняем веса
	for _, w := range t.model.weights {
		if w.Value() != nil {
			data := w.Value().Data()

			var floatData []float32
			switch v := data.(type) {
			case []float32:
				floatData = v
			case []float64:
				floatData = make([]float32, len(v))
				for i, val := range v {
					floatData[i] = float32(val)
				}
			default:
				continue
			}

			// Записываем имя веса
			nameBytes := []byte(w.Name())
			if err := binary.Write(weightsFile, binary.LittleEndian, uint32(len(nameBytes))); err != nil {
				return err
			}
			if _, err := weightsFile.Write(nameBytes); err != nil {
				return err
			}

			// Записываем размер и данные
			if err := binary.Write(weightsFile, binary.LittleEndian, uint32(len(floatData))); err != nil {
				return err
			}
			if err := binary.Write(weightsFile, binary.LittleEndian, floatData); err != nil {
				return err
			}
		}
	}

	log.Printf("✅ Model saved to: %s", t.config.ModelPath)
	return nil
}

func (t *Trainer) Train(ctx context.Context) error {
	for epoch := 1; epoch <= t.config.Epochs; epoch++ {
		// Проверяем контекст (Ctrl+C)
		select {
		case <-ctx.Done():
			log.Println("Training interrupted, saving checkpoint...")
			t.saveCheckpoint(epoch)
			t.metrics.EndTime = time.Now()
			return ctx.Err()
		default:
		}

		start := time.Now()

		trainLoss := t.trainEpoch()
		valLoss := t.validate()

		t.metrics.LastTrainLoss = trainLoss
		t.metrics.LastValLoss = valLoss
		t.metrics.TotalEpochs = epoch

		log.Printf("\nEpoch %d/%d | Train Loss: %.6f | Val Loss: %.6f | Time: %v",
			epoch, t.config.Epochs, trainLoss, valLoss,
			time.Since(start).Round(time.Millisecond))

		if valLoss < t.bestLoss {
			t.bestLoss = valLoss
			t.metrics.BestLoss = valLoss
			t.noImprove = 0
			if err := t.saveModel(); err != nil {
				log.Printf("Warning: failed to save model: %v", err)
			}
		} else {
			t.noImprove++
			if t.noImprove >= t.config.EarlyStopping {
				log.Printf("Early stopping triggered")
				break
			}
		}

		// Периодический checkpoint
		if t.config.CheckpointEpoch > 0 && epoch%t.config.CheckpointEpoch == 0 {
			t.saveCheckpoint(epoch)
		}
	}

	t.metrics.EndTime = time.Now()
	log.Printf("Training complete! %s", t.metrics.Summary())
	return nil
}

// ========== Domain Search ==========

type DomainConfig struct {
	Name        string   `json:"name"`
	BaseURL     string   `json:"base_url"`
	SearchTypes []string `json:"search_types"` // news, blog, ecommerce, etc.
	Priority    int      `json:"priority"`
}

type SearchResult struct {
	URL         string    `json:"url"`
	Title       string    `json:"title"`
	Snippet     string    `json:"snippet"`
	ContentType string    `json:"content_type"`
	Source      string    `json:"source"` // domain name
	Score       float32   `json:"score"`
	Timestamp   time.Time `json:"timestamp"`
}

type DomainSearchEngine struct {
	domains      []DomainConfig
	index        *SearchIndex
	mu           sync.RWMutex
	resultsCache map[string][]SearchResult
	cacheTTL     time.Duration
    session      *ort.AdvancedSession
    inputTensor  *ort.Tensor[float32]
    outputTensor *ort.Tensor[float32]
}

type IndexedDocument struct {
	ID      string    `json:"id"`
	Title   string    `json:"title"`
	Content string    `json:"content"`
	Score   float32   `json:"score"`
	Source  string    `json:"source"`
	Tokens  []int64   `json:"tokens"`
	Mask    []float32 `json:"mask"`
}

func NewDomainSearchEngine(index *SearchIndex, cacheTTL time.Duration) *DomainSearchEngine {
	if cacheTTL == 0 {
		cacheTTL = 1 * time.Hour
	}
	return &DomainSearchEngine{
		index:        index,
		resultsCache: make(map[string][]SearchResult),
		cacheTTL:     cacheTTL,
	}
}

func (dse *DomainSearchEngine) AddDomain(domain DomainConfig) {
	dse.mu.Lock()
	defer dse.mu.Unlock()
	dse.domains = append(dse.domains, domain)
}

// Search выполняет поиск по запросу
func (dse *DomainSearchEngine) Search(ctx context.Context, query string, topK int) ([]SearchResult, error) {
	// Проверяем кэш
	cacheKey := fmt.Sprintf("%s:%d", query, topK)
	dse.mu.RLock()
	if cached, ok := dse.resultsCache[cacheKey]; ok {
		if time.Since(cached[0].Timestamp) < dse.cacheTTL {
			dse.mu.RUnlock()
			return cached, nil
		}
	}
	dse.mu.RUnlock()

	// Получаем эмбеддинг запроса через ONNX модель
	var queryEmbedding []float32
	if dse.index != nil && dse.index.model != nil {
		var err error
		queryEmbedding, err = dse.getQueryEmbedding(query)
		if err != nil {
			log.Printf("Failed to get query embedding: %v, falling back to token search", err)
		}
	}

	var results []IndexedDocument

	if len(queryEmbedding) > 0 {
		// Семантический поиск по эмбеддингам
		results = dse.index.SemanticSearch(queryEmbedding, topK*2)
	} else {
		// Fallback на токенизированный поиск
		tokens := tokenizeQuery(query)
		mask := BuildMask(tokens, 128) // используем фиксированное значение вместо dse.index.model.cfg.MaxSeqLen

		// Получаем результаты поиска
		rawResults, err := dse.index.Search(tokens, mask, topK*2)
		if err != nil {
			return nil, fmt.Errorf("token search failed: %w", err)
		}

		// Конвертируем в IndexedDocument
		results = make([]IndexedDocument, len(rawResults))
		for i, r := range rawResults {
			results[i] = IndexedDocument{
				ID:      r.ID,
				Title:   truncateString(r.Content, 100),
				Content: r.Content,
				Score:   r.Score,
				Source:  extractDomain(r.ID),
			}
		}
	}

	// Конвертируем в SearchResult с улучшенной метаинформацией
	searchResults := make([]SearchResult, 0, len(results))
	for _, r := range results {
		// Извлекаем релевантный сниппет
		snippet := extractRelevantSnippet(r.Content, query)

		searchResults = append(searchResults, SearchResult{
			URL:         r.ID,
			Title:       truncateString(r.Title, 100),
			Snippet:     truncateString(snippet, 200),
			ContentType: detectContentType(r.Title, r.Content),
			Source:      r.Source,
			Score:       r.Score,
			Timestamp:   time.Now(),
		})
	}

	// Пост-обработка результатов
	searchResults = rerankResults(searchResults, query)

	// Сортируем по Score
	sort.Slice(searchResults, func(i, j int) bool {
		return searchResults[i].Score > searchResults[j].Score
	})

	if len(searchResults) > topK {
		searchResults = searchResults[:topK]
	}

	// Сохраняем в кэш
	dse.mu.Lock()
	dse.resultsCache[cacheKey] = searchResults
	dse.mu.Unlock()

	return searchResults, nil
}

// SemanticSearch ищет по эмбеддингам (косинусное сходство)
func (idx *SearchIndex) SemanticSearch(queryEmbedding []float32, topK int) []IndexedDocument {
	idx.mu.RLock()
	defer idx.mu.RUnlock()

	type scored struct {
		id    string
		score float32
	}

	scores := make([]scored, 0, len(idx.vectors))

	for id, emb := range idx.vectors {
		similarity := cosineSimilarity(queryEmbedding, emb)
		scores = append(scores, scored{id, similarity})
	}

	// Сортируем по убыванию
	sort.Slice(scores, func(i, j int) bool {
		return scores[i].score > scores[j].score
	})

	// Берем topK
	if len(scores) > topK {
		scores = scores[:topK]
	}

	// Конвертируем в IndexedDocument
	results := make([]IndexedDocument, 0, len(scores))
	for _, s := range scores {
		if content, ok := idx.metadata[s.id]; ok {
			results = append(results, IndexedDocument{
				ID:      s.id,
				Title:   truncateString(content, 100),
				Content: content,
				Score:   s.score,
				Source:  extractDomain(s.id),
			})
		}
	}

	return results
}

// AddWithEmbedding добавляет документ с эмбеддингом
func (idx *SearchIndex) AddWithEmbedding(id, content string, embedding []float32) error {
	idx.mu.Lock()
	defer idx.mu.Unlock()

	// Сохраняем эмбеддинг
	idx.vectors[id] = embedding

	// Сохраняем метаданные (содержимое)
	title := content
	if len(content) > 100 {
		title = content[:100]
	}
	idx.metadata[id] = title + "\n" + content

	return nil
}

// Уже есть поля в DomainSearchEngine, просто убедитесь что метод привязан к правильному receiver
func (dse *DomainSearchEngine) InitSession(modelPath string, maxLen int) error {
    dse.mu.Lock()
    defer dse.mu.Unlock()
    
    var err error
    dse.inputTensor, err = ort.NewEmptyTensor[float32](ort.NewShape(1, int64(maxLen)))
    if err != nil {
        return fmt.Errorf("failed to create input tensor: %w", err)
    }
    
    dse.outputTensor, err = ort.NewEmptyTensor[float32](ort.NewShape(1, 288))
    if err != nil {
        return fmt.Errorf("failed to create output tensor: %w", err)
    }
    
    // Используем AdvancedSession
    advSession, err := ort.NewAdvancedSession(
        modelPath,
        []string{"input"},
        []string{"output"},
        []ort.Value{dse.inputTensor},
        []ort.Value{dse.outputTensor},
        nil,
    )
    if err != nil {
        return fmt.Errorf("failed to create session: %w", err)
    }
    
    dse.session = advSession
    return nil
}

// getQueryEmbedding получает эмбеддинг для текста запроса (метод DomainSearchEngine)
func (dse *DomainSearchEngine) getQueryEmbedding(query string) ([]float32, error) {
    if dse.session == nil {
        return nil, fmt.Errorf("session not initialized")
    }
    
    // Токенизируем
    tokenizer := NewTokenizer(10000, 128)
    tokens := tokenizer.tokenizeQuery(query)
    
    // Обновляем данные входного тензора
    inputData := make([]float32, len(tokens))
    for i, t := range tokens {
        inputData[i] = float32(t)
    }
    copy(dse.inputTensor.GetData(), inputData)
    
    // Запускаем инференс
    if err := dse.session.Run(); err != nil {
        return nil, fmt.Errorf("failed to run inference: %w", err)
    }
    
    // Получаем результат
    embedding := make([]float32, 288)
    copy(embedding, dse.outputTensor.GetData())
    
    return embedding, nil
}

// extractRelevantSnippet извлекает релевантный фрагмент текста
func extractRelevantSnippet(content, query string) string {
	// Приводим запрос к нижнему регистру
	queryLower := strings.ToLower(query)

	// Разбиваем на предложения
	sentences := strings.Split(content, ".")

	// Ищем предложение с максимальным совпадением
	bestScore := 0
	bestIndex := 0

	for i, sentence := range sentences {
		sentenceLower := strings.ToLower(sentence)
		score := 0

		// Считаем совпадения слов
		for _, word := range strings.Fields(queryLower) {
			if strings.Contains(sentenceLower, word) {
				score++
			}
		}

		if score > bestScore {
			bestScore = score
			bestIndex = i
		}
	}

	if bestScore > 0 && bestIndex < len(sentences) {
		snippet := strings.TrimSpace(sentences[bestIndex])
		if len(snippet) > 200 {
			snippet = snippet[:200] + "..."
		}
		return snippet
	}

	// Fallback: первые 200 символов
	if len(content) > 200 {
		return content[:200] + "..."
	}
	return content
}

// truncateString обрезает строку до максимальной длины
func truncateString(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "..."
}

// extractDomain извлекает домен из URL
func extractDomain(urlStr string) string {
	parsed, err := url.Parse(urlStr)
	if err != nil {
		return ""
	}
	return parsed.Hostname()
}

// rerankResults переранжирует результаты на основе дополнительных факторов
func rerankResults(results []SearchResult, query string) []SearchResult {
	queryLower := strings.ToLower(query)

	for i := range results {
		// Бустим результаты, где заголовок точно совпадает с запросом
		if strings.Contains(strings.ToLower(results[i].Title), queryLower) {
			results[i].Score *= 1.5
		}

		// Бустим результаты в зависимости от типа контента
		switch results[i].ContentType {
		case "artist_search":
			results[i].Score *= 1.3
		case "album_search":
			results[i].Score *= 1.2
		case "playlist_search":
			results[i].Score *= 1.1
		}

		// Штраф за старые результаты
		hoursSince := time.Since(results[i].Timestamp).Hours()
		if hoursSince > 24 {
			results[i].Score *= 0.9
		}
	}

	return results
}

// Вспомогательная функция для токенизации запроса
func tokenizeQuery(query string) []int64 {
	tokenizer := NewTokenizer(10000, 128)
	return tokenizer.tokenizeQuery(query)
}

// Tokenizer для работы с ONNX моделью
type Tokenizer struct {
	vocab    map[string]int64 // слово -> токен ID
	maxLen   int              // максимальная длина последовательности
	padToken int64            // токен для паддинга
	unkToken int64            // токен для неизвестных слов
}

// NewTokenizer создает новый токенизатор
func NewTokenizer(vocabSize int, maxLen int) *Tokenizer {
	// Создаем базовый словарь (в реальности загружаете из файла)
	vocab := make(map[string]int64)

	// Специальные токены
	vocab["[PAD]"] = 0
	vocab["[UNK]"] = 1
	vocab["[CLS]"] = 2
	vocab["[SEP]"] = 3

	// Добавляем частотные слова (пример)
	commonWords := []string{"музыка", "песня", "исполнитель", "альбом", "трек",
		"рок", "поп", "хип", "хоп", "джаз", "классика", "металл", "электроника"}

	for i, word := range commonWords {
		vocab[word] = int64(i + 4) // +4 чтобы не затереть спецтокены
	}

	return &Tokenizer{
		vocab:    vocab,
		maxLen:   maxLen,
		padToken: 0,
		unkToken: 1,
	}
}

// tokenizeQuery токенизирует строку запроса
func (t *Tokenizer) tokenizeQuery(query string) []int64 {
	// Приводим к нижнему регистру
	query = strings.ToLower(query)

	// Разбиваем на слова (с учетом русских букв)
	words := splitWordsRussian(query)

	tokens := make([]int64, 0, len(words)+2)

	// Добавляем [CLS] токен в начало
	tokens = append(tokens, t.vocab["[CLS]"])

	// Токенизируем слова
	for _, word := range words {
		if token, exists := t.vocab[word]; exists {
			tokens = append(tokens, token)
		} else {
			// Пробуем найти слово без окончаний (stemming)
			stemmed := simpleStem(word)
			if token, exists := t.vocab[stemmed]; exists {
				tokens = append(tokens, token)
			} else {
				tokens = append(tokens, t.unkToken)
			}
		}
	}

	// Добавляем [SEP] токен в конец
	tokens = append(tokens, t.vocab["[SEP]"])

	// Обрезаем или паддим до maxLen
	if len(tokens) > t.maxLen {
		tokens = tokens[:t.maxLen]
	} else {
		// Паддинг
		for len(tokens) < t.maxLen {
			tokens = append(tokens, t.padToken)
		}
	}

	return tokens
}

// splitWordsRussian разделяет текст на слова с учетом русского языка
func splitWordsRussian(text string) []string {
	// Регулярка для слов (буквы, цифры, апострофы)
	re := regexp.MustCompile(`[а-яА-Яa-zA-Z0-9']+`)
	words := re.FindAllString(text, -1)

	// Приводим к нижнему регистру и фильтруем короткие слова
	result := make([]string, 0, len(words))
	for _, w := range words {
		w = strings.ToLower(w)
		if len(w) > 1 { // игнорируем однобуквенные
			result = append(result, w)
		}
	}
	return result
}

// simpleStem - простое удаление окончаний для русского языка
func simpleStem(word string) string {
	// Основные русские окончания
	suffixes := []string{"ый", "ий", "ой", "ая", "яя", "ое", "ее", "ые", "ие",
		"ого", "его", "ому", "ему", "ым", "им", "ом", "ем",
		"а", "я", "о", "е", "у", "ю", "ы", "и",
		"ть", "ти", "чь", "тся", "ться"}

	for _, suffix := range suffixes {
		if strings.HasSuffix(word, suffix) {
			return word[:len(word)-len(suffix)]
		}
	}
	return word
}

// GetEmbedding получает эмбеддинг для запроса через ONNX модель
func (t *Tokenizer) GetEmbedding(session *ort.Session[float32], query string) ([]float32, error) {
	// Токенизируем
	tokens := t.tokenizeQuery(query)

	// Преобразуем в float32 для модели
	input := make([]float32, len(tokens))
	for i, tok := range tokens {
		input[i] = float32(tok)
	}

	// Создаем входной тензор
	shape := ort.NewShape(1, int64(len(tokens)))
	inputTensor, err := ort.NewTensor(shape, input)
	if err != nil {
		return nil, fmt.Errorf("failed to create input tensor: %w", err)
	}
	defer inputTensor.Destroy()

	// Создаем выходной тензор (пустой)
	outputShape := ort.NewShape(1, 288)
	outputTensor, err := ort.NewEmptyTensor[float32](outputShape)
	if err != nil {
		return nil, fmt.Errorf("failed to create output tensor: %w", err)
	}
	defer outputTensor.Destroy()

	// Создаем сессию с привязанными тензорами
	// ВАЖНО: используем NewSession, а не NewAdvancedSession для Session[T]
	inferSession, err := ort.NewSession(
		"web/model/model.onnx", // путь к модели
		[]string{"input"},      // имена входов
		[]string{"output"},     // имена выходов
		[]*ort.Tensor[float32]{inputTensor},
		[]*ort.Tensor[float32]{outputTensor},
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create session: %w", err)
	}
	defer inferSession.Destroy()

	// Запускаем инференс
	if err := inferSession.Run(); err != nil {
		return nil, fmt.Errorf("failed to run inference: %w", err)
	}

	// Получаем эмбеддинг из выходного тензора
	embedding := outputTensor.GetData()

	return embedding, nil
}

// SearchResultWithEmbedding расширяет SearchResult эмбеддингом
type SearchResultWithEmbedding struct {
	SearchResult
	Embedding []float32 `json:"embedding"`
}

// SemanticSearch семантический поиск по эмбеддингам
func SemanticSearch(queryEmbedding []float32, index []SearchResultWithEmbedding, topK int) []SearchResult {
	type scored struct {
		result SearchResult
		score  float32
	}

	scores := make([]scored, 0, len(index))

	for _, item := range index {
		// Косинусное сходство
		similarity := cosineSimilarity(queryEmbedding, item.Embedding)
		scores = append(scores, scored{item.SearchResult, similarity})
	}

	// Сортируем по убыванию
	sort.Slice(scores, func(i, j int) bool {
		return scores[i].score > scores[j].score
	})

	// Берем topK
	results := make([]SearchResult, 0, topK)
	for i := 0; i < topK && i < len(scores); i++ {
		results = append(results, scores[i].result)
	}

	return results
}

// cosineSimilarity вычисляет косинусное сходство
func cosineSimilarity(a, b []float32) float32 {
	if len(a) != len(b) {
		return 0
	}

	var dot, normA, normB float32
	for i := 0; i < len(a); i++ {
		dot += a[i] * b[i]
		normA += a[i] * a[i]
		normB += b[i] * b[i]
	}

	if normA == 0 || normB == 0 {
		return 0
	}

	return dot / (float32(math.Sqrt(float64(normA))) * float32(math.Sqrt(float64(normB))))
}

func splitWords(s string) []string {
	// Простое разбиение по пробелам и знакам препинания
	var words []string
	var current []rune
	for _, r := range s {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r > 127 {
			current = append(current, r)
		} else if len(current) > 0 {
			words = append(words, string(current))
			current = nil
		}
	}
	if len(current) > 0 {
		words = append(words, string(current))
	}
	return words
}

func hashString(s string) int {
	h := 0
	for _, c := range s {
		h = 31*h + int(c)
	}
	if h < 0 {
		h = -h
	}
	return h
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// ========== Domain Crawler ==========

type CrawledPage struct {
	URL         string
	Title       string
	Content     string
	ContentType string
	Source      string
}

func CrawlDomain(ctx context.Context, domain DomainConfig, maxPages int, index *SearchIndex) error {
	log.Printf("Starting crawl of %s (max pages: %d)", domain.Name, maxPages)

	// Очередь URL для обхода
	queue := []string{domain.BaseURL}
	visited := make(map[string]bool)
	crawled := 0

	for len(queue) > 0 && crawled < maxPages {
		// Проверяем контекст
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		// Берём следующий URL
		url := queue[0]
		queue = queue[1:]

		if visited[url] {
			continue
		}
		visited[url] = true

		// Загружаем страницу
		page, err := fetchPage(ctx, url)
		if err != nil {
			log.Printf("Failed to fetch %s: %v", url, err)
			continue
		}

		// Определяем тип контента
		contentType := detectContentType(page.Title, page.Content)

		// Токенизируем контент
		tokens := tokenizeQuery(page.Title + " " + page.Content)
		mask := BuildMask(tokens, index.model.cfg.MaxSeqLen)

		// Добавляем в индекс
		err = index.Add(url, page.Title+"\n"+page.Content, tokens, mask)
		if err != nil {
			log.Printf("Failed to index %s: %v", url, err)
			continue
		}

		crawled++
		log.Printf("Crawled %d/%d: %s (%s)", crawled, maxPages, url, contentType)

		// Добавляем ссылки в очередь (упрощённо)
		for _, link := range page.Links {
			if !visited[link] && !isExternalLink(link, domain.BaseURL) {
				queue = append(queue, link)
			}
		}
	}

	log.Printf("Finished crawling %s: %d pages indexed", domain.Name, crawled)
	return nil
}

func detectContentType(title, content string) string {
	text := strings.ToLower(title + " " + content)

	// Русский рок / поп / шансон
	if strings.Contains(text, "рок") || strings.Contains(text, "рок-музыка") ||
		strings.Contains(text, "поп") || strings.Contains(text, "попса") ||
		strings.Contains(text, "шансон") {
		return "russian_music"
	}

	// Зарубежная музыка
	if strings.Contains(text, "rock") || strings.Contains(text, "pop") ||
		strings.Contains(text, "hip-hop") || strings.Contains(text, "rap") ||
		strings.Contains(text, "electronic") || strings.Contains(text, "edm") ||
		strings.Contains(text, "jazz") || strings.Contains(text, "classical") {
		return "foreign_music"
	}

	// Поиск по исполнителю
	if strings.Contains(text, "исполнител") || strings.Contains(text, "певец") || strings.Contains(text, "artist") || strings.Contains(text, "singer") {
		return "artist_search"
	}

	// Поиск по альбому
	if strings.Contains(text, "альбом") || strings.Contains(text, "album") {
		return "album_search"
	}

	// Поиск по плейлисту
	if strings.Contains(text, "плейлист") || strings.Contains(text, "playlist") || strings.Contains(text, "микст") || strings.Contains(text, "mix") {
		return "playlist_search"
	}

	// Ремиксы / каверы
	if strings.Contains(text, "ремикс") || strings.Contains(text, "remix") || strings.Contains(text, "кавер") || strings.Contains(text, "cover") {
		return "remix_search"
	}

	// Живые выступления
	if strings.Contains(text, "live") || strings.Contains(text, "концерт") || strings.Contains(text, "акустика") || strings.Contains(text, "acoustic") {
		return "live_performance"
	}

	// Инструментал
	if strings.Contains(text, "инструментал") || strings.Contains(text, "instrumental") || strings.Contains(text, "минус") || strings.Contains(text, "beat") {
		return "instrumental"
	}

	// По умолчанию — общий поиск музыки
	return "general_music"
}

type Page struct {
	URL     string
	Title   string
	Content string
	Links   []string
}

func fetchPage(ctx context.Context, url string) (*Page, error) {
	// Создаём HTTP клиент
	client := &http.Client{
		Timeout: 10 * time.Second,
	}

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "MikuBot/1.0 (+https://miku.com/bot)")

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("status code: %d", resp.StatusCode)
	}

	// Читаем HTML
	htmlBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	htmlContent := string(htmlBytes)

	// Извлекаем title
	title := extractTitle(htmlContent)

	// Извлекаем текст (упрощённо — удаляем теги)
	text := extractText(htmlContent)

	// Извлекаем ссылки
	links := extractLinks(htmlContent, url)

	return &Page{
		URL:     url,
		Title:   title,
		Content: text,
		Links:   links,
	}, nil
}

func extractTitle(html string) string {
	// Простое извлечение title (для продакшена используй goquery)
	start := strings.Index(html, "<title>")
	if start == -1 {
		return ""
	}
	start += 7
	end := strings.Index(html[start:], "</title>")
	if end == -1 {
		return ""
	}
	return html[start : start+end]
}

func extractText(html string) string {
	// Упрощённое удаление HTML тегов
	text := html
	// Удаляем скрипты и стили
	scriptRe := regexp.MustCompile(`(?s)<script.*?>.*?</script>`)
	text = scriptRe.ReplaceAllString(text, "")
	styleRe := regexp.MustCompile(`(?s)<style.*?>.*?</style>`)
	text = styleRe.ReplaceAllString(text, "")
	// Удаляем теги
	tagRe := regexp.MustCompile(`<[^>]+>`)
	text = tagRe.ReplaceAllString(text, " ")
	// Нормализуем пробелы
	spaceRe := regexp.MustCompile(`\s+`)
	text = spaceRe.ReplaceAllString(text, " ")
	return strings.TrimSpace(text)
}

func extractLinks(html, baseURL string) []string {
	// Простое извлечение ссылок (для продакшена используй goquery)
	links := make([]string, 0)
	linkRe := regexp.MustCompile(`<a\s+(?:[^>]*?\s+)?href="([^"]+)"`)
	matches := linkRe.FindAllStringSubmatch(html, -1)

	base, _ := url.Parse(baseURL)
	for _, match := range matches {
		if len(match) < 2 {
			continue
		}
		link, err := url.Parse(match[1])
		if err != nil {
			continue
		}
		resolved := base.ResolveReference(link)
		links = append(links, resolved.String())
	}
	return links
}

func isExternalLink(link, baseURL string) bool {
	base, _ := url.Parse(baseURL)
	parsed, _ := url.Parse(link)
	if parsed == nil {
		return true
	}
	return parsed.Host != base.Host
}

// ExportToONNX экспортирует обученную модель в формат ONNX
func (m *Model) ExportToONNX(outputPath string) error {
	if len(m.weights) == 0 {
		return fmt.Errorf("model not trained, no weights found")
	}

	dir := filepath.Dir(outputPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create directory: %w", err)
	}

	// Создаем ONNX модель
	onnxModel := &pb.ModelProto{
		IrVersion:       proto.Int64(10),
		ProducerName:    proto.String("gorgonia"),
		ProducerVersion: proto.String("0.9.0"),
		Domain:          proto.String("ai.onnx"),
		ModelVersion:    proto.Int64(1),
		Graph: &pb.GraphProto{
			Name:        proto.String("embedding_model"),
			Initializer: []*pb.TensorProto{},
			Node:        []*pb.NodeProto{},
			Input:       []*pb.ValueInfoProto{},
			Output:      []*pb.ValueInfoProto{},
			ValueInfo:   []*pb.ValueInfoProto{},
		},
	}

	onnxModel.OpsetImport = []*pb.OperatorSetIdProto{
		{
			Domain:  proto.String(""),
			Version: proto.Int64(13),
		},
	}

	// Входной узел
	inputValue := &pb.ValueInfoProto{
		Name: proto.String("input"),
		Type: &pb.TypeProto{
			Value: &pb.TypeProto_TensorType{
				TensorType: &pb.TypeProto_Tensor{
					ElemType: proto.Int32(int32(pb.TensorProto_FLOAT)),
					Shape: &pb.TensorShapeProto{
						Dim: []*pb.TensorShapeProto_Dimension{
							{Value: &pb.TensorShapeProto_Dimension_DimValue{DimValue: -1}},
							{Value: &pb.TensorShapeProto_Dimension_DimValue{DimValue: 288}},
						},
					},
				},
			},
		},
	}
	onnxModel.Graph.Input = append(onnxModel.Graph.Input, inputValue)

	// Выходной узел
	outputValue := &pb.ValueInfoProto{
		Name: proto.String("output"),
		Type: &pb.TypeProto{
			Value: &pb.TypeProto_TensorType{
				TensorType: &pb.TypeProto_Tensor{
					ElemType: proto.Int32(int32(pb.TensorProto_FLOAT)),
					Shape: &pb.TensorShapeProto{
						Dim: []*pb.TensorShapeProto_Dimension{
							{Value: &pb.TensorShapeProto_Dimension_DimValue{DimValue: -1}},
							{Value: &pb.TensorShapeProto_Dimension_DimValue{DimValue: 288}},
						},
					},
				},
			},
		},
	}
	onnxModel.Graph.Output = append(onnxModel.Graph.Output, outputValue)

	// Конвертируем веса
	weightTensors, err := convertWeightsToONNX(m.weights)
	if err != nil {
		return fmt.Errorf("failed to convert weights: %w", err)
	}
	onnxModel.Graph.Initializer = append(onnxModel.Graph.Initializer, weightTensors...)

	// Строим граф операций
	nodes, err := buildOperationNodes()
	if err != nil {
		return fmt.Errorf("failed to build operation nodes: %w", err)
	}
	onnxModel.Graph.Node = append(onnxModel.Graph.Node, nodes...)

	// Сериализуем
	data, err := proto.Marshal(onnxModel)
	if err != nil {
		return fmt.Errorf("failed to marshal protobuf: %w", err)
	}

	if err := os.WriteFile(outputPath, data, 0644); err != nil {
		return fmt.Errorf("failed to write file: %w", err)
	}

	log.Printf("✅ Model exported to ONNX: %s", outputPath)
	return nil
}

// convertWeightsToONNX конвертирует Gorgonia веса в ONNX TensorProto
func convertWeightsToONNX(weights []*gorgonia.Node) ([]*pb.TensorProto, error) {
	tensors := make([]*pb.TensorProto, 0, len(weights))

	for _, w := range weights {
		if w.Value() == nil {
			continue
		}

		// Получаем данные весов
		data := w.Value().Data()
		floatData, err := toFloat32Slice(data)
		if err != nil {
			return nil, fmt.Errorf("weight %s: %w", w.Name(), err)
		}

		// Получаем форму тензора
		shape := w.Shape()
		dims := make([]int64, shape.Dims())
		for i, s := range shape {
			dims[i] = int64(s)
		}

		// Создаем TensorProto
		tensor := &pb.TensorProto{
			Name:     proto.String(w.Name()),
			DataType: proto.Int32(int32(pb.TensorProto_FLOAT)),
			Dims:     dims,
			RawData:  float32ToBytes(floatData),
		}

		tensors = append(tensors, tensor)
	}

	return tensors, nil
}

// buildOperationNodes строит узлы операций для ONNX графа
func buildOperationNodes() ([]*pb.NodeProto, error) {
	nodes := []*pb.NodeProto{}

	// Слой 1: Gemm (input * w1 + b1)
	node1 := &pb.NodeProto{
		Name:   proto.String("gemm_1"),
		OpType: proto.String("Gemm"),
		Domain: proto.String(""),
		Input:  []string{"input", "w1", "b1"},
		Output: []string{"gemm_1_out"},
		Attribute: []*pb.AttributeProto{
			{
				Name: proto.String("alpha"),
				Type: pb.AttributeProto_AttributeType(pb.AttributeProto_FLOAT).Enum(),
				F:    proto.Float32(1.0),
			},
			{
				Name: proto.String("beta"),
				Type: pb.AttributeProto_AttributeType(pb.AttributeProto_FLOAT).Enum(),
				F:    proto.Float32(1.0),
			},
			{
				Name: proto.String("transB"),
				Type: pb.AttributeProto_AttributeType(pb.AttributeProto_INT).Enum(),
				I:    proto.Int64(1),
			},
		},
	}
	nodes = append(nodes, node1)

	// ReLU 1
	relu1 := &pb.NodeProto{
		Name:   proto.String("relu_1"),
		OpType: proto.String("Relu"),
		Input:  []string{"gemm_1_out"},
		Output: []string{"relu_1_out"},
	}
	nodes = append(nodes, relu1)

	// Слой 2: Gemm (relu1 * w2 + b2)
	node2 := &pb.NodeProto{
		Name:   proto.String("gemm_2"),
		OpType: proto.String("Gemm"),
		Input:  []string{"relu_1_out", "w2", "b2"},
		Output: []string{"gemm_2_out"},
		Attribute: []*pb.AttributeProto{
			{Name: proto.String("alpha"), Type: pb.AttributeProto_AttributeType(pb.AttributeProto_FLOAT).Enum(), F: proto.Float32(1.0)},
			{Name: proto.String("beta"), Type: pb.AttributeProto_AttributeType(pb.AttributeProto_FLOAT).Enum(), F: proto.Float32(1.0)},
			{Name: proto.String("transB"), Type: pb.AttributeProto_AttributeType(pb.AttributeProto_INT).Enum(), I: proto.Int64(1)},
		},
	}
	nodes = append(nodes, node2)

	// ReLU 2
	relu2 := &pb.NodeProto{
		Name:   proto.String("relu_2"),
		OpType: proto.String("Relu"),
		Input:  []string{"gemm_2_out"},
		Output: []string{"relu_2_out"},
	}
	nodes = append(nodes, relu2)

	// Слой 3: Gemm (relu2 * w3 + b3) -> output
	node3 := &pb.NodeProto{
		Name:   proto.String("gemm_3"),
		OpType: proto.String("Gemm"),
		Input:  []string{"relu_2_out", "w3", "b3"},
		Output: []string{"output"},
		Attribute: []*pb.AttributeProto{
			{Name: proto.String("alpha"), Type: pb.AttributeProto_AttributeType(pb.AttributeProto_FLOAT).Enum(), F: proto.Float32(1.0)},
			{Name: proto.String("beta"), Type: pb.AttributeProto_AttributeType(pb.AttributeProto_FLOAT).Enum(), F: proto.Float32(1.0)},
			{Name: proto.String("transB"), Type: pb.AttributeProto_AttributeType(pb.AttributeProto_INT).Enum(), I: proto.Int64(1)},
		},
	}
	nodes = append(nodes, node3)

	return nodes, nil
}

// Вспомогательные функции

func toFloat32Slice(data interface{}) ([]float32, error) {
	switch v := data.(type) {
		case []float32:
			return v, nil
		case []float64:
			result := make([]float32, len(v))
			for i, val := range v {
				result[i] = float32(val)
			}
			return result, nil
		default:
			return nil, fmt.Errorf("unsupported data type: %T", data)
	}
}

func float32ToBytes(data []float32) []byte {
	buf := new(bytes.Buffer)
	for _, f := range data {
		// Используем little-endian как в ONNX по умолчанию
		if err := binary.Write(buf, binary.LittleEndian, f); err != nil {
			// fallback на последовательную запись
			b := make([]byte, 4)
			binary.LittleEndian.PutUint32(b, math.Float32bits(f))
			buf.Write(b)
		}
	}
	return buf.Bytes()
}
