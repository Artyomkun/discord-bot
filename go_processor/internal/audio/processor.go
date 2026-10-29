package audio

import (
	"fmt"
	"log"
	"net/http"
	"os/exec"
	"encoding/json"
	"encoding/base64"
)

// Processor главный обработчик аудио
type Processor struct {
	decoder *Decoder
	encoder *Encoder
	effects *AudioEffects
}

// NewProcessor создаёт новый процессор
func NewProcessor() *Processor {
	return &Processor{
		decoder: &Decoder{},
		encoder: NewEncoder(),
		effects: NewAudioEffects(),
	}
}

// AudioEffects структура для эффектов
type AudioEffects struct {
	Volume      float64
	BassBoost   float64
	TrebleBoost float64
	Speed       float64
	Pitch       float64
	Echo        bool
	EchoDelay   float64
	EchoDecay   float64
	Reverb      bool
	ReverbRoom  float64
	ReverbDamp  float64
	Chorus      bool
	ChorusDelay float64
	ChorusDepth float64
	Flanger     bool
	FlangerDelay float64
	FlangerDepth float64
	Phaser      bool
	PhaserRate  float64
	PhaserDepth float64
	Distortion  bool
	DistortionGain float64
	Compressor  bool
	CompressorRatio float64
	CompressorThreshold float64
	Equalizer   map[string]float64 // Частота -> Усиление
}

// NewAudioEffects создаёт AudioEffects
func NewAudioEffects() *AudioEffects {
	return &AudioEffects{
		Volume:      1.0,
		BassBoost:   0.0,
		TrebleBoost: 0.0,
		Speed:       1.0,
		Pitch:       1.0,
		Echo:        false,
		EchoDelay:   0.3,
		EchoDecay:   0.5,
		Reverb:      false,
		ReverbRoom:  0.5,
		ReverbDamp:  0.5,
		Chorus:      false,
		ChorusDelay: 0.02,
		ChorusDepth: 0.3,
		Flanger:     false,
		FlangerDelay: 0.005,
		FlangerDepth: 0.5,
		Phaser:      false,
		PhaserRate:  0.5,
		PhaserDepth: 0.5,
		Distortion:  false,
		DistortionGain: 2.0,
		Compressor:  false,
		CompressorRatio: 4.0,
		CompressorThreshold: -20.0,
		Equalizer:   make(map[string]float64),
	}
}

// ApplyEffects применяет эффекты к аудио
func (ae *AudioEffects) ApplyEffects(inputPath, outputPath string) error {
	log.Printf("Применение эффектов к %s -> %s", inputPath, outputPath)

	// Используем FFmpeg для применения эффектов
	args := []string{"-i", inputPath}

	// Строим фильтр эффектов
	var filters []string

	// Громкость
	if ae.Volume != 1.0 {
		filters = append(filters, fmt.Sprintf("volume=%.2f", ae.Volume))
	}

	// Bass boost
	if ae.BassBoost != 0.0 {
		filters = append(filters, fmt.Sprintf("bass=g=%.1f", ae.BassBoost))
	}

	// Treble boost
	if ae.TrebleBoost != 0.0 {
		filters = append(filters, fmt.Sprintf("treble=g=%.1f", ae.TrebleBoost))
	}

	// Скорость и тон
	if ae.Speed != 1.0 || ae.Pitch != 1.0 {
		if ae.Speed == ae.Pitch {
			filters = append(filters, fmt.Sprintf("atempo=%.2f", ae.Speed))
		} else {
			// Раздельное управление скоростью и тоном
			filters = append(filters, fmt.Sprintf("asetrate=44100*%.2f,atempo=%.2f", ae.Pitch, ae.Speed/ae.Pitch))
		}
	}

	// Эхо
	if ae.Echo {
		filters = append(filters, fmt.Sprintf("aecho=%.2f:%.2f:%d:%.0f",
			ae.EchoDelay*1000, ae.EchoDelay*1000, 1, ae.EchoDecay*1000))
	}

	// Реверберация
	if ae.Reverb {
		filters = append(filters, fmt.Sprintf("reverb=reverberance=%.0f:hf_damping=%.0f:room_scale=%d",
			ae.ReverbRoom*100, ae.ReverbDamp*100, 100))
	}

	// Хорус
	if ae.Chorus {
		filters = append(filters, "chorus=0.5:0.9:50:0.4:0.25:2")
	}

	// Флэнджер
	if ae.Flanger {
		filters = append(filters, "flanger")
	}

	// Фэйзер
	if ae.Phaser {
		filters = append(filters, "aphaser=in_gain=0.4")
	}

	// Дисторшн
	if ae.Distortion {
		filters = append(filters, fmt.Sprintf("distortion=%.1f", ae.DistortionGain))
	}

	// Компрессор
	if ae.Compressor {
		filters = append(filters, "compand=attacks=0.3:decays=0.8:points=-70/-60|-30/-10")
	}

	// Эквалайзер
	if len(ae.Equalizer) > 0 {
		for freq, gain := range ae.Equalizer {
			filters = append(filters, "equalizer=f="+freq+":width_type=o:width=1:g="+fmt.Sprintf("%.1f", gain))
		}
	}

	// Применяем фильтры
	if len(filters) > 0 {
		filterString := ""
		for i, f := range filters {
			if i > 0 {
				filterString += ","
			}
			filterString += f
		}
		args = append(args, "-af", filterString)
	}

	// Выходной файл
	args = append(args, "-c:a", "libopus", "-b:a", "128k", outputPath)

	// Выполняем FFmpeg
	cmd := exec.Command("ffmpeg", args...)
	cmd.Stdout = nil
	cmd.Stderr = nil

	err := cmd.Run()
	if err != nil {
		return fmt.Errorf("ошибка применения эффектов FFmpeg: %v", err)
	}

	log.Printf("Эффекты успешно применены")
	return nil
}

func normalizeHandler(w http.ResponseWriter, r *http.Request) {
    var req struct {
        Audio  string                 `json:"audio"`
        Params map[string]interface{} `json:"params"`
    }
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    
    audio, err := base64.StdEncoding.DecodeString(req.Audio)
    if err != nil {
        http.Error(w, "Invalid base64", http.StatusBadRequest)
        return
    }
    
    samples := bytesToF32(audio)
    
    targetPeak, ok := req.Params["target_peak"].(float64)
    if !ok {
        targetPeak = -1.0
    }
    
    peak := maxAbs(samples)
    if peak > 0 {
        gain := targetPeak / peak
        for i := range samples {
            samples[i] *= float32(gain)
        }
    }
    
    result := f32ToBytes(samples)
    
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]string{
        "audio": base64.StdEncoding.EncodeToString(result),
    })
}

// ProcessFile обрабатывает аудиофайл
func (p *Processor) ProcessFile(inputPath, outputFormat string) (string, error) {
	log.Printf("Обработка файла: %s", inputPath)
	
	// 1. Получаем информацию о файле
	info, err := GetAudioInfo(inputPath)
	if err != nil {
		return "", fmt.Errorf("ошибка получения информации: %v", err)
	}
	log.Printf("Информация: %v", info)
	
	// 2. Декодируем в PCM
	decoder := NewDecoder(inputPath, outputFormat)
	pcmPath, err := decoder.DecodeToPCM()
	if err != nil {
		return "", fmt.Errorf("ошибка декодирования: %v", err)
	}
	log.Printf("Декодировано в PCM: %s", pcmPath)
	
	// 3. Кодируем в нужный формат
	var outputPath string
	switch outputFormat {
	case "opus":
		outputPath, err = p.encoder.PCMToOpus(pcmPath)
		if err != nil {
			return "", fmt.Errorf("ошибка кодирования Opus: %v", err)
		}
		log.Printf("Закодировано в Opus: %s", outputPath)
	default:
		return "", fmt.Errorf("неподдерживаемый выходной формат: %s", outputFormat)
	}
	
	return outputPath, nil
}

// ProcessForDiscord готовит аудио для Discord
func (p *Processor) ProcessForDiscord(inputPath string) (string, error) {
	// Discord использует Opus 48kHz стерео
	return p.ProcessFile(inputPath, "opus")
}

// ProcessWithEffects обрабатывает с эффектами
func (p *Processor) ProcessWithEffects(inputPath string, volume, bassBoost, speed float64) (string, error) {
	// 1. Базовая обработка
	tempPath, err := p.ProcessForDiscord(inputPath)
	if err != nil {
		return "", err
	}
	
	// 2. Применяем эффекты
	outputPath := GetOutputPath(tempPath, "effects.opus")
	
	p.effects.Volume = volume
	p.effects.BassBoost = bassBoost
	p.effects.Speed = speed
	
	err = p.effects.ApplyEffects(tempPath, outputPath)
	if err != nil {
		return "", fmt.Errorf("ошибка применения эффектов: %v", err)
	}
	
	return outputPath, nil
}

// ProcessStream создаёт поток для стриминга
func (p *Processor) ProcessStream(inputPath string) (*exec.Cmd, error) {
	return p.encoder.StreamToOpus(inputPath)
}