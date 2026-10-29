package audio

import (
	"errors"
	"fmt"
	"log"
	"os/exec"
)

// Decoder обрабатывает различные аудиоформаты
type Decoder struct {
	InputPath  string
	OutputPath string
	Format     string
}

// NewDecoder создаёт новый декодер
func NewDecoder(inputPath, format string) *Decoder {
	return &Decoder{
		InputPath:  inputPath,
		OutputPath: "temp/output.pcm",
		Format:     format,
	}
}

// DecodeToPCM конвертирует аудио в PCM
func (d *Decoder) DecodeToPCM() (string, error) {
	var cmd *exec.Cmd
	
	switch d.Format {
	case "mp3", "mpeg":
		cmd = exec.Command("ffmpeg", "-i", d.InputPath, 
			"-f", "s16le", "-acodec", "pcm_s16le", 
			"-ar", "48000", "-ac", "2", d.OutputPath)
	case "wav":
		cmd = exec.Command("ffmpeg", "-i", d.InputPath, 
			"-f", "s16le", "-acodec", "pcm_s16le", d.OutputPath)
	case "webm", "opus":
		cmd = exec.Command("ffmpeg", "-i", d.InputPath, 
			"-acodec", "pcm_s16le", d.OutputPath)
	default:
		return "", errors.New("unsupported format: " + d.Format)
	}
	
	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("ffmpeg error: %v\n%s", err, output)
	}
	
	return d.OutputPath, nil
}

// GetAudioInfo возвращает информацию об аудиофайле
func GetAudioInfo(path string) (map[string]string, error) {
	cmd := exec.Command("ffprobe", 
		"-v", "quiet",
		"-print_format", "json",
		"-show_format",
		"-show_streams",
		path)
	
	output, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("FFmpeg failed: %s", string(output))
		return nil, err  // Два значения: string и nil error
	}
		// Используем output в логах
	log.Printf("FFmpeg output: %s", string(output))
	
	// Парсим JSON (упрощённо)
	info := map[string]string{
		"path": path,
		"type": "audio",
	}
	
	return info, nil
}