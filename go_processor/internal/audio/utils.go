package audio

import "math"

func bytesToF32(data []byte) []float32 {
	samples := make([]float32, len(data)/2)
	for i := 0; i < len(samples); i++ {
		val := int16(data[2*i]) | int16(data[2*i+1])<<8
		samples[i] = float32(val) / 32768.0
	}
	return samples
}

func f32ToBytes(samples []float32) []byte {
    data := make([]byte, len(samples)*2)
    for i, s := range samples {
        clamped := s
        if clamped > 1.0 {
            clamped = 1.0
        } else if clamped < -1.0 {
            clamped = -1.0
        }
        val := int16(clamped * 32767.0)
        data[2*i] = byte(val)
        data[2*i+1] = byte(val >> 8)
    }
    return data
}

func maxAbs(samples []float32) float64 {
	var peak float32 = 0.0
	for _, s := range samples {
		if abs := float32(math.Abs(float64(s))); abs > peak {
			peak = abs
		}
	}
	return float64(peak)
}