package audio

import (
	"os/exec"
	"path/filepath"
	"fmt"
	"log"
)

// Encoder кодирует PCM в Opus
type Encoder struct {
	SampleRate int
	Channels   int
	Bitrate    string
}

// NewEncoder создаёт новый энкодер
func NewEncoder() *Encoder {
	return &Encoder{
		SampleRate: 48000,
		Channels:   2,
		Bitrate:    "128k",
	}
}

// PCMToOpus конвертирует PCM в Opus
func (e *Encoder) PCMToOpus(inputPath string) (string, error) {
	outputPath := "temp/output.opus"
	
	cmd := exec.Command("ffmpeg",
		"-f", "s16le",
		"-ar", "48000",
		"-ac", "2",
		"-i", inputPath,
		"-c:a", "libopus",
		"-b:a", e.Bitrate,
		"-f", "opus",
		outputPath)
	
	output, err := cmd.CombinedOutput()
	if err != nil {
		// Используем output в ошибке
		return "", fmt.Errorf("ffmpeg error: %v, output: %s", err, string(output))
	}

	// Дополнительно можно залогировать output
	log.Printf("FFmpeg output: %s", string(output))
		
	return outputPath, nil
}

// StreamToOpus создаёт Opus поток (для реального времени)
func (e *Encoder) StreamToOpus(inputPath string) (*exec.Cmd, error) {
	cmd := exec.Command("ffmpeg",
		"-i", inputPath,
		"-c:a", "libopus",
		"-b:a", e.Bitrate,
		"-f", "opus",
		"pipe:1")
	
	return cmd, nil
}

// GetOutputPath возвращает путь для выходного файла
func GetOutputPath(inputPath, format string) string {
	ext := filepath.Ext(inputPath)
	base := inputPath[:len(inputPath)-len(ext)]
	return base + "." + format
}