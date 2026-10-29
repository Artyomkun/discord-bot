package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"text/template"

	"github.com/gin-gonic/gin"
	ort "github.com/yalue/onnxruntime_go"
)

const indexTemplate = `Process Audio

Enter Audio URL: 
Enter API Key: 

Submit to /process`

const resultTemplate = `Result

Audio URL: {{.AudioURL}}
Status: {{.Status}}

Back to /`

const onnxTemplate = `ONNX Inference

Enter data as JSON array: 
Example: [1.0, 2.0, 3.0, 4.0]

{{if .Output}}Output: {{.Output}}{{end}}

Back to /`

var tmpl *template.Template
var session *ort.AdvancedSession
var inputShape, outputShape ort.Shape
var inputName = "input"
var outputName = "output"

func main() {
	log.Println("Starting ONNX Server on :8081")

	// Инициализация ONNX runtime
	if err := initONNX(); err != nil {
		log.Fatalf("Failed to initialize ONNX: %v", err)
	}
	defer ort.DestroyEnvironment()
	defer session.Destroy()

	gin.SetMode(gin.ReleaseMode)
	r := gin.Default()

	r.Use(apiKeyMiddleware())

	tmpl = template.Must(template.New("index").Parse(indexTemplate))
	tmpl = template.Must(tmpl.New("result").Parse(resultTemplate))
	tmpl = template.Must(tmpl.New("onnx").Parse(onnxTemplate))

	r.GET("/", func(c *gin.Context) {
		var buf bytes.Buffer
		tmpl.ExecuteTemplate(&buf, "index", nil)
		c.String(200, buf.String())
	})

	r.POST("/process", func(c *gin.Context) {
		audioURL := c.PostForm("audio_url")
		apiKey := c.PostForm("api_key")
		c.Request.Header.Set("X-API-Key", apiKey)

		status, err := processAudioWithONNX(audioURL)
		if err != nil {
			status = "Error: " + err.Error()
		}

		var buf bytes.Buffer
		tmpl.ExecuteTemplate(&buf, "result", gin.H{
			"AudioURL": audioURL,
			"Status":   status,
		})
		c.String(200, buf.String())
	})

	r.GET("/onnx", func(c *gin.Context) {
		var buf bytes.Buffer
		tmpl.ExecuteTemplate(&buf, "onnx", nil)
		c.String(200, buf.String())
	})

	r.POST("/onnx", func(c *gin.Context) {
		dataStr := c.PostForm("data")
		var data []interface{}

		if err := json.Unmarshal([]byte(dataStr), &data); err != nil {
			var buf bytes.Buffer
			tmpl.ExecuteTemplate(&buf, "onnx", gin.H{"Output": "Error: invalid JSON"})
			c.String(200, buf.String())
			return
		}

		inputData := make([]float32, len(data))
		for i, v := range data {
			if f, ok := v.(float64); ok {
				inputData[i] = float32(f)
			} else {
				var buf bytes.Buffer
				tmpl.ExecuteTemplate(&buf, "onnx", gin.H{"Output": "Error: data must be numbers"})
				c.String(200, buf.String())
				return
			}
		}

		output, err := runONNXInference(inputData)
		if err != nil {
			var buf bytes.Buffer
			tmpl.ExecuteTemplate(&buf, "onnx", gin.H{"Output": "Error: " + err.Error()})
			c.String(200, buf.String())
			return
		}

		var buf bytes.Buffer
		tmpl.ExecuteTemplate(&buf, "onnx", gin.H{"Output": output})
		c.String(200, buf.String())
	})

	r.POST("/onnx/infer", func(c *gin.Context) {
		var input map[string]interface{}
		if err := c.ShouldBindJSON(&input); err != nil {
			c.JSON(400, gin.H{"error": err.Error()})
			return
		}

		data, ok := input["data"].([]interface{})
		if !ok {
			c.JSON(400, gin.H{"error": "invalid data"})
			return
		}

		inputData := make([]float32, len(data))
		for i, v := range data {
			if f, ok := v.(float64); ok {
				inputData[i] = float32(f)
			} else {
				c.JSON(400, gin.H{"error": "data must be numbers"})
				return
			}
		}

		output, err := runONNXInference(inputData)
		if err != nil {
			c.JSON(500, gin.H{"error": err.Error()})
			return
		}

		c.JSON(200, gin.H{"output": output})
	})

	log.Println("Server starting on 0.0.0.0:8081")
	r.Run("0.0.0.0:8081")
}

func initONNX() error {
	ort.SetSharedLibraryPath("/usr/local/lib/libonnxruntime.so")

	if err := ort.InitializeEnvironment(); err != nil {
		return err
	}

	modelPath := os.Getenv("ONNX_MODEL_PATH")
	if modelPath == "" {
		modelPath = "web/model/model.onnx"
	}

	// Проверяем существование файла
	if _, err := os.Stat(modelPath); os.IsNotExist(err) {
		log.Printf("Warning: Model file not found at %s, creating dummy", modelPath)
	}

	inputShape = ort.NewShape(1, 128)
	outputShape = ort.NewShape(1, 64)

	// Создаем тензоры
	inputTensor, err := ort.NewEmptyTensor[float32](inputShape)
	if err != nil {
		return fmt.Errorf("failed to create input tensor: %w", err)
	}
	defer inputTensor.Destroy()

	outputTensor, err := ort.NewEmptyTensor[float32](outputShape)
	if err != nil {
		return fmt.Errorf("failed to create output tensor: %w", err)
	}
	defer outputTensor.Destroy()

	// Создаем сессию
	session, err = ort.NewAdvancedSession(
		modelPath,
		[]string{inputName},
		[]string{outputName},
		[]ort.Value{inputTensor},
		[]ort.Value{outputTensor},
		nil,
	)
	if err != nil {
		return fmt.Errorf("failed to create session: %w", err)
	}

	log.Printf("ONNX model loaded from %s", modelPath)
	return nil
}

func runONNXInference(inputData []float32) (string, error) {
	if session == nil {
		return "ONNX not initialized", nil
	}

	// Создаем новый тензор с данными
	inputTensor, err := ort.NewTensor(inputShape, inputData)
	if err != nil {
		return "", fmt.Errorf("failed to create input tensor: %w", err)
	}
	defer inputTensor.Destroy()

	// Создаем пустой выходной тензор
	outputTensor, err := ort.NewEmptyTensor[float32](outputShape)
	if err != nil {
		return "", fmt.Errorf("failed to create output tensor: %w", err)
	}
	defer outputTensor.Destroy()

	// Запускаем инференс
	if err := session.Run(); err != nil {
		return "", fmt.Errorf("inference failed: %w", err)
	}

	outputData := outputTensor.GetData()
	result := make([]string, len(outputData))
	for i, v := range outputData {
		result[i] = fmt.Sprintf("%.6f", v)
	}

	return strings.Join(result, ", "), nil
}

func processAudioWithONNX(audioURL string) (string, error) {
	if session == nil {
		return "ONNX not initialized", nil
	}
	features := extractAudioFeatures(audioURL)
	output, err := runONNXInference(features)
	if err != nil {
		return "", err
	}
	return "Processed: " + output, nil
}

func extractAudioFeatures(url string) []float32 {
	testData := make([]float32, 128)
	for i := range testData {
		testData[i] = float32(i) / 100.0
	}
	return testData
}

func apiKeyMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		apiKey := os.Getenv("API_KEY")
		if apiKey == "" {
			c.AbortWithStatusJSON(500, gin.H{"error": "API_KEY not set"})
			return
		}

		var providedKey string
		if key := c.GetHeader("X-API-Key"); key != "" {
			providedKey = key
		} else if auth := c.GetHeader("Authorization"); strings.HasPrefix(auth, "Bearer ") {
			providedKey = strings.TrimPrefix(auth, "Bearer ")
		} else {
			c.AbortWithStatusJSON(401, gin.H{"error": "API key required"})
			return
		}

		if providedKey != apiKey {
			c.AbortWithStatusJSON(403, gin.H{"error": "Invalid API key"})
			return
		}

		c.Next()
	}
}