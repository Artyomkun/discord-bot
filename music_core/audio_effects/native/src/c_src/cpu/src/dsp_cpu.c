#include "../../include/dsp.h"
#include "../../common/include/dsp_config.h"
#include "../../common/include/dsp_logging.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

#ifndef M_PI
    #define M_PI 3.14159265358979323846
#endif

// ============================================================================
// DELAY EFFECT
// ============================================================================

/**
 * @brief Initialize delay buffer
 * @param delay Pointer to delay buffer structure
 * @param size Size of the delay buffer
 * @param feedback Feedback amount (0.0 to 1.0)
 * @param wet Wet mix amount (0.0 to 1.0)
 * @param dry Dry mix amount (0.0 to 1.0)
 */
void delay_init(DelayBuffer *delay, size_t size, float feedback, float wet, float dry) {
    if (delay == NULL || size == 0) {
        DSP_LOG_ERROR("Invalid parameters for delay_init");
        return;
    }
    
    delay->buffer = (float *)malloc(size * sizeof(float));
    if (delay->buffer == NULL) {
        DSP_LOG_ERROR("Failed to allocate memory for delay buffer");
        return;
    }
    
    memset(delay->buffer, 0, size * sizeof(float));
    delay->size = size;
    delay->write_pos = 0;
    delay->feedback = feedback;
    delay->wet = wet;
    delay->dry = dry;
    DSP_LOG_DEBUG("Delay buffer initialized with size %zu", size);
}

/**
 * @brief Free delay buffer
 * @param delay Pointer to delay buffer structure
 */
void delay_free(DelayBuffer *delay) {
    if (delay == NULL) {
        return;
    }

    if (delay->buffer != NULL) {
        free(delay->buffer);
        delay->buffer = NULL;
    }
    delay->size = 0;
    delay->write_pos = 0;

    DSP_LOG_DEBUG("Delay buffer freed");
}

/**
 * @brief Process audio through delay buffer
 * @param delay Pointer to delay buffer structure
 * @param input Input audio sample
 * @return Processed audio sample
 */
float delay_process(DelayBuffer *delay, float input) {
    if (delay == NULL) {
        DSP_LOG_ERROR("Invalid parameters for delay_process");
        return input;
    }

    if (delay->buffer == NULL || delay->size == 0) {
        return input;
    }

    // Исправлено: читаем текущую позицию (где был предыдущий сэмпл)
    size_t read_pos = delay->write_pos;
    float delayed = delay->buffer[read_pos];
    float feedback_sample = input + delayed * delay->feedback;

    delay->buffer[delay->write_pos] = feedback_sample;
    delay->write_pos = (delay->write_pos + 1) % delay->size;

    return input * delay->dry + delayed * delay->wet;
}

// ============================================================================
// LOW-PASS FILTER
// ============================================================================

/**
 * @brief Initialize low-pass filter
 * @param filter Pointer to low-pass filter structure
 * @param cutoff_freq Cutoff frequency in Hz
 * @param sample_rate Sample rate in Hz
 */
void lpf_init(LowPassFilter *filter, float cutoff_freq, float sample_rate) {
    if (filter == NULL || cutoff_freq <= 0 || sample_rate <= 0) {
        DSP_LOG_ERROR("Invalid parameters for lpf_init");
        return;
    }

    float rc = 1.0f / (cutoff_freq * 2.0f * M_PI);
    float dt = 1.0f / sample_rate;
    float alpha = dt / (rc + dt);

    filter->b0 = alpha;
    filter->a1 = 1.0f - alpha;
    filter->prev_out = 0.0f;
    DSP_LOG_DEBUG("LPF initialized with cutoff %.2f Hz", cutoff_freq);
}

/**
 * @brief Process audio through low-pass filter
 * @param filter Pointer to low-pass filter structure
 * @param input Input audio sample
 * @return Filtered audio sample
 */
float lpf_process(LowPassFilter *filter, float input) {
    if (filter == NULL) {
        DSP_LOG_ERROR("Invalid parameters for lpf_process");
        return input;
    }

    float output = filter->b0 * input + filter->a1 * filter->prev_out;
    filter->prev_out = output;
    return output;
}

/**
 * @brief Reset low-pass filter state
 * @param filter Pointer to low-pass filter structure
 */
void lpf_reset(LowPassFilter *filter) {
    if (filter == NULL) {
        return;
    }
    filter->prev_out = 0.0f;
    DSP_LOG_DEBUG("LPF reset");
}

// ============================================================================
// DISTORTION EFFECT
// ============================================================================

/**
 * @brief Initialize distortion effect
 * @param dist Pointer to distortion structure
 * @param drive Drive amount
 * @param threshold Threshold for soft clipping
 * @param gain Output gain
 */
void distortion_init(Distortion *dist, float drive, float threshold, float gain) {
    if (dist == NULL || drive < 0 || threshold < 0 || gain < 0) {
        DSP_LOG_ERROR("Invalid parameters for distortion_init");
        return;
    }

    dist->drive = drive;
    dist->threshold = threshold;
    dist->gain = gain;
    DSP_LOG_DEBUG("Distortion initialized with drive %.2f, threshold %.2f, gain %.2f", drive, threshold, gain);
}

/**
 * @brief Process audio through distortion effect
 * @param dist Pointer to distortion structure
 * @param input Input audio sample
 * @return Distorted audio sample
 */
float distortion_process(Distortion *dist, float input) {
    if (dist == NULL) {
        DSP_LOG_ERROR("Invalid parameters for distortion_process");
        return input;
    }

    float driven = input * dist->drive;
    float sign = (driven > 0.0f) ? 1.0f : -1.0f;
    float abs_input = fabsf(driven);
    float output;

    if (abs_input < dist->threshold) {
        output = driven;
    } else {
        float overshoot = abs_input - dist->threshold;
        float clipped = dist->threshold + (1.0f - dist->threshold) * tanhf(overshoot / (1.0f - dist->threshold));
        output = sign * clipped;
    }

    float result = output * dist->gain;
    
    // Защита от переполнения
    if (result > 1.0f) result = 1.0f;
    if (result < -1.0f) result = -1.0f;
    
    return result;
}

// ============================================================================
// REVERB EFFECT
// ============================================================================

/**
 * @brief Initialize reverb effect
 * @param rev Pointer to reverb structure
 * @param sample_rate Sample rate in Hz
 * @param decay Decay time
 * @param wet Wet mix amount
 * @param dry Dry mix amount
 */
void reverb_init(Reverb *rev, float sample_rate, float decay, float wet, float dry) {
    if (rev == NULL || sample_rate <= 0 || decay < 0 || wet < 0 || dry < 0) {
        DSP_LOG_ERROR("Invalid parameters for reverb_init");
        return;
    }

    // Обнуляем структуру перед инициализацией
    memset(rev, 0, sizeof(Reverb));

    size_t comb_sizes[4] = {
        (size_t)(DSP_REVERB_COMB1_DELAY * sample_rate),
        (size_t)(DSP_REVERB_COMB2_DELAY * sample_rate),
        (size_t)(DSP_REVERB_COMB3_DELAY * sample_rate),
        (size_t)(DSP_REVERB_COMB4_DELAY * sample_rate)
    };

    float feedback = decay;

    delay_init(&rev->comb1, comb_sizes[0], feedback, 1.0f, 0.0f);
    if (rev->comb1.buffer == NULL) {
        DSP_LOG_ERROR("Failed to initialize comb1 for reverb");
        return;
    }

    delay_init(&rev->comb2, comb_sizes[1], feedback, 1.0f, 0.0f);
    if (rev->comb2.buffer == NULL) {
        DSP_LOG_ERROR("Failed to initialize comb2 for reverb");
        delay_free(&rev->comb1);
        return;
    }

    delay_init(&rev->comb3, comb_sizes[2], feedback, 1.0f, 0.0f);
    if (rev->comb3.buffer == NULL) {
        DSP_LOG_ERROR("Failed to initialize comb3 for reverb");
        delay_free(&rev->comb1);
        delay_free(&rev->comb2);
        return;
    }

    delay_init(&rev->comb4, comb_sizes[3], feedback, 1.0f, 0.0f);
    if (rev->comb4.buffer == NULL) {
        DSP_LOG_ERROR("Failed to initialize comb4 for reverb");
        delay_free(&rev->comb1);
        delay_free(&rev->comb2);
        delay_free(&rev->comb3);
        return;
    }

    lpf_init(&rev->lpf, DSP_REVERB_LPF_CUTOFF, sample_rate);

    rev->wet = wet;
    rev->dry = dry;
    DSP_LOG_DEBUG("Reverb initialized with sample_rate %.2f, decay %.2f", sample_rate, decay);
}

/**
 * @brief Free reverb effect resources
 * @param rev Pointer to reverb structure
 */
void reverb_free(Reverb *rev) {
    if (rev == NULL) {
        return;
    }

    delay_free(&rev->comb1);
    delay_free(&rev->comb2);
    delay_free(&rev->comb3);
    delay_free(&rev->comb4);
    
    memset(rev, 0, sizeof(Reverb));
    DSP_LOG_DEBUG("Reverb freed");
}

/**
 * @brief Process audio through reverb effect
 * @param rev Pointer to reverb structure
 * @param input Input audio sample
 * @return Reverberated audio sample
 */
float reverb_process(Reverb *rev, float input) {
    if (rev == NULL) {
        DSP_LOG_ERROR("Invalid parameters for reverb_process");
        return input;
    }

    float comb_out1 = delay_process(&rev->comb1, input);
    float comb_out2 = delay_process(&rev->comb2, input);
    float comb_out3 = delay_process(&rev->comb3, input);
    float comb_out4 = delay_process(&rev->comb4, input);

    float comb_out = (comb_out1 + comb_out2 + comb_out3 + comb_out4) * 0.25f;
    comb_out = lpf_process(&rev->lpf, comb_out);

    float result = input * rev->dry + comb_out * rev->wet;
    
    // Защита от переполнения
    if (result > 1.0f) result = 1.0f;
    if (result < -1.0f) result = -1.0f;
    
    return result;
}

// ============================================================================
// CHORUS EFFECT
// ============================================================================

/**
 * @brief Initialize chorus effect
 * @param chor Pointer to chorus structure
 * @param sample_rate Sample rate in Hz
 * @param rate Modulation rate in Hz
 * @param depth Modulation depth
 * @param wet Wet mix amount
 * @param dry Dry mix amount
 */
void chorus_init(Chorus *chor, float sample_rate, float rate, float depth, float wet, float dry) {
    if (chor == NULL || sample_rate <= 0 || rate < 0 || depth < 0 || wet < 0 || dry < 0) {
        DSP_LOG_ERROR("Invalid parameters for chorus_init");
        return;
    }

    // Обнуляем структуру перед инициализацией
    memset(chor, 0, sizeof(Chorus));

    size_t base_delay = (size_t)(DSP_CHORUS_BASE_DELAY * sample_rate);
    if (base_delay == 0) base_delay = 1;

    delay_init(&chor->delay1, base_delay * 2, 0.0f, 1.0f, 0.0f);
    if (chor->delay1.buffer == NULL) {
        DSP_LOG_ERROR("Failed to initialize delay1 for chorus");
        return;
    }

    delay_init(&chor->delay2, base_delay * 2, 0.0f, 1.0f, 0.0f);
    if (chor->delay2.buffer == NULL) {
        DSP_LOG_ERROR("Failed to initialize delay2 for chorus");
        delay_free(&chor->delay1);
        return;
    }

    lpf_init(&chor->lpf, DSP_CHORUS_LPF_CUTOFF, sample_rate);

    chor->rate = rate;
    chor->depth = depth;
    chor->phase = 0.0f;
    chor->wet = wet;
    chor->dry = dry;
    chor->sample_rate = sample_rate;
    DSP_LOG_DEBUG("Chorus initialized with sample_rate %.2f, rate %.2f, depth %.2f", sample_rate, rate, depth);
}

/**
 * @brief Free chorus effect resources
 * @param chor Pointer to chorus structure
 */
void chorus_free(Chorus *chor) {
    if (chor == NULL) {
        return;
    }

    delay_free(&chor->delay1);
    delay_free(&chor->delay2);
    
    memset(chor, 0, sizeof(Chorus));
    DSP_LOG_DEBUG("Chorus freed");
}

/**
 * @brief Process audio through chorus effect
 * @param chor Pointer to chorus structure
 * @param input Input audio sample
 * @return Chorus processed audio sample
 */
float chorus_process(Chorus *chor, float input) {
    if (chor == NULL) {
        DSP_LOG_ERROR("Invalid parameters for chorus_process");
        return input;
    }

    chor->phase += chor->rate / chor->sample_rate;
    if (chor->phase >= 1.0f) chor->phase -= 1.0f;

    float delay_out1 = delay_process(&chor->delay1, input);
    float delay_out2 = delay_process(&chor->delay2, input);

    float chorus_out = (delay_out1 + delay_out2) * 0.5f;
    chorus_out = lpf_process(&chor->lpf, chorus_out);

    float result = input * chor->dry + chorus_out * chor->wet;
    
    // Защита от переполнения
    if (result > 1.0f) result = 1.0f;
    if (result < -1.0f) result = -1.0f;
    
    return result;
}

// ============================================================================
// BATCH PROCESSING (CPU)
// ============================================================================

/**
 * @brief Process batch of audio through distortion effect on CPU
 * @param input Input audio buffer
 * @param n Number of samples
 * @param drive Drive amount
 * @param threshold Threshold for soft clipping
 * @param gain Output gain
 * @return Processed audio buffer (must be freed by caller)
 */
float *distortion_process_batch_cpu(float *input, int n, float drive, float threshold, float gain) {
    if (input == NULL || n <= 0) {
        DSP_LOG_ERROR("Invalid parameters for distortion_process_batch_cpu");
        return NULL;
    }

    float *output = (float *)malloc(n * sizeof(float));
    if (output == NULL) {
        DSP_LOG_ERROR("Failed to allocate memory for output");
        return NULL;
    }

    Distortion dist;
    distortion_init(&dist, drive, threshold, gain);

    for (int i = 0; i < n; i++) {
        output[i] = distortion_process(&dist, input[i]);
    }

    return output;
}

/**
 * @brief Process batch of audio through low-pass filter on CPU
 * @param input Input audio buffer
 * @param n Number of samples
 * @param cutoff_freq Cutoff frequency in Hz
 * @param sample_rate Sample rate in Hz
 * @return Processed audio buffer (must be freed by caller)
 */
float *lpf_process_batch_cpu(float *input, int n, float cutoff_freq, float sample_rate) {
    if (input == NULL || n <= 0) {
        DSP_LOG_ERROR("Invalid parameters for lpf_process_batch_cpu");
        return NULL;
    }

    float *output = (float *)malloc(n * sizeof(float));
    if (output == NULL) {
        DSP_LOG_ERROR("Failed to allocate memory for output");
        return NULL;
    }

    LowPassFilter filter;
    lpf_init(&filter, cutoff_freq, sample_rate);

    for (int i = 0; i < n; i++) {
        output[i] = lpf_process(&filter, input[i]);
    }

    return output;
}

/**
 * @brief Process batch of audio through reverb effect on CPU
 * @param input Input audio buffer
 * @param n Number of samples
 * @param ir Impulse response buffer
 * @param ir_len Length of impulse response
 * @param wet Wet mix amount
 * @param dry Dry mix amount
 * @return Processed audio buffer (must be freed by caller)
 */
float *reverb_process_batch_cpu(float *input, int n, float *ir, int ir_len, float wet, float dry) {
    if (input == NULL || n <= 0 || ir == NULL || ir_len <= 0) {
        DSP_LOG_ERROR("Invalid parameters for reverb_process_batch_cpu");
        return NULL;
    }

    float *output = (float *)malloc(n * sizeof(float));
    if (output == NULL) {
        DSP_LOG_ERROR("Failed to allocate memory for output");
        return NULL;
    }

    for (int i = 0; i < n; i++) {
        float sum = 0.0f;
        int start = (i - ir_len + 1 > 0) ? i - ir_len + 1 : 0;
        for (int j = start; j <= i; j++) {
            sum += input[j] * ir[i - j];
        }
        output[i] = input[i] * dry + sum * wet;
    }

    return output;
}

/**
 * @brief Process batch of audio through chorus effect on CPU
 * @param input Input audio buffer
 * @param n Number of samples
 * @param sample_rate Sample rate in Hz
 * @param rate Modulation rate in Hz
 * @param depth Modulation depth
 * @param wet Wet mix amount
 * @param dry Dry mix amount
 * @return Processed audio buffer (must be freed by caller)
 */
float *chorus_process_batch_cpu(float *input, int n, float sample_rate, float rate, float depth, float wet, float dry) {
    if (input == NULL || n <= 0) {
        DSP_LOG_ERROR("Invalid parameters for chorus_process_batch_cpu");
        return NULL;
    }

    float *output = (float *)malloc(n * sizeof(float));
    if (output == NULL) {
        DSP_LOG_ERROR("Failed to allocate memory for output");
        return NULL;
    }

    Chorus chor;
    chorus_init(&chor, sample_rate, rate, depth, wet, dry);

    for (int i = 0; i < n; i++) {
        output[i] = chorus_process(&chor, input[i]);
    }

    chorus_free(&chor);
    return output;
}

// ============================================================================
// UTILITIES FOR Rust FFI
// ============================================================================

/**
 * @brief Free audio buffer allocated by DSP functions
 * @param buffer Pointer to buffer to free
 */
void dsp_free_buffer(float *buffer) {
    if (buffer != NULL) {
        free(buffer);
    }
}