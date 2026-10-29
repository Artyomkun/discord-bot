#include "../include/dsp.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>

#ifndef M_PI
    #define M_PI 3.14159265358979323846
#endif

#ifdef CUDA_SUPPORT
    #include <cuda_runtime.h>

    /**
     * @brief Check if GPU is available
     * @return 1 if GPU is available, 0 otherwise
     */
    int is_gpu_available() {
        int count;
        cudaError_t err = cudaGetDeviceCount(&count);
        if (err != cudaSuccess || count == 0) {
            printf("GPU not available: %s (count=%d)\n", cudaGetErrorString(err), count);
            return 0;
        }
        cudaDeviceProp prop;
        err = cudaGetDeviceProperties(&prop, 0);
        if (err != cudaSuccess) {
            printf("Failed to get device properties: %s\n", cudaGetErrorString(err));
            return 0;
        }
        printf("GPU available: %s, Compute capability %d.%d\n", prop.name, prop.major, prop.minor);
        return 1;
    }
#endif

// FFI interface for Rust
#ifdef __cplusplus
    extern "C" {
#endif

        // ============================================================
        // DELAY EFFECT
        // ============================================================

        void delay_init(DelayBuffer *delay, size_t size, float feedback, float wet, float dry) {
            if (delay == NULL || size == 0) {
                fprintf(stderr, "delay_init: Invalid parameters\n");
                return;
            }

            delay->buffer = (float *)malloc(size * sizeof(float));
            if (delay->buffer == NULL) {
                fprintf(stderr, "delay_init: Failed to allocate memory\n");
                return;
            }

            memset(delay->buffer, 0, size * sizeof(float));
            delay->size = size;
            delay->write_pos = 0;
            delay->feedback = feedback;
            delay->wet = wet;
            delay->dry = dry;
        }

        void delay_free(DelayBuffer *delay) {
            if (delay == NULL) return;

            if (delay->buffer != NULL) {
                free(delay->buffer);
                delay->buffer = NULL;
            }
            delay->size = 0;
            delay->write_pos = 0;
        }

        float delay_process(DelayBuffer *delay, float input) {
            if (delay == NULL || delay->buffer == NULL || delay->size == 0) {
                return input;
            }

            // Исправлено: читаем текущую позицию
            size_t read_pos = delay->write_pos;
            float delayed = delay->buffer[read_pos];
            
            float feedback_sample = input + delayed * delay->feedback;
            delay->buffer[delay->write_pos] = feedback_sample;
            delay->write_pos = (delay->write_pos + 1) % delay->size;

            return input * delay->dry + delayed * delay->wet;
        }

        // ============================================================
        // LOW-PASS FILTER
        // ============================================================

        void lpf_init(LowPassFilter *filter, float cutoff_freq, float sample_rate) {
            if (filter == NULL || cutoff_freq <= 0.0f || sample_rate <= 0.0f) {
                fprintf(stderr, "lpf_init: Invalid parameters\n");
                return;
            }

            float rc = 1.0f / (cutoff_freq * 2.0f * M_PI);
            float dt = 1.0f / sample_rate;
            float alpha = dt / (rc + dt);

            filter->b0 = alpha;
            filter->a1 = 1.0f - alpha;
            filter->prev_out = 0.0f;
        }

        float lpf_process(LowPassFilter *filter, float input) {
            if (filter == NULL) return input;
            
            float output = filter->b0 * input + filter->a1 * filter->prev_out;
            filter->prev_out = output;
            return output;
        }

        void lpf_reset(LowPassFilter *filter) {
            if (filter != NULL) {
                filter->prev_out = 0.0f;
            }
        }

        // ============================================================
        // DISTORTION EFFECT
        // ============================================================

        void distortion_init(Distortion *dist, float drive, float threshold, float gain) {
            if (dist == NULL) return;
            
            dist->drive = drive;
            dist->threshold = threshold;
            dist->gain = gain;
        }

        float distortion_process(Distortion *dist, float input) {
            if (dist == NULL) return input;
            
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

            output = output * dist->gain;
            
            // Защита от переполнения
            if (output > 1.0f) output = 1.0f;
            if (output < -1.0f) output = -1.0f;
            
            return output;
        }

        // ============================================================
        // REVERB EFFECT
        // ============================================================

        void reverb_init(Reverb *rev, float sample_rate, float decay, float wet, float dry) {
            if (rev == NULL || sample_rate <= 0.0f) {
                fprintf(stderr, "reverb_init: Invalid parameters\n");
                return;
            }

            // Обнуляем всю структуру
            memset(rev, 0, sizeof(Reverb));

            size_t comb_sizes[4] = {
                (size_t)(0.0297f * sample_rate),
                (size_t)(0.0371f * sample_rate),
                (size_t)(0.0411f * sample_rate),
                (size_t)(0.0437f * sample_rate)
            };

            float feedback = decay;

            delay_init(&rev->comb1, comb_sizes[0], feedback, 1.0f, 0.0f);
            if (rev->comb1.buffer == NULL) return;

            delay_init(&rev->comb2, comb_sizes[1], feedback, 1.0f, 0.0f);
            if (rev->comb2.buffer == NULL) {
                delay_free(&rev->comb1);
                return;
            }

            delay_init(&rev->comb3, comb_sizes[2], feedback, 1.0f, 0.0f);
            if (rev->comb3.buffer == NULL) {
                delay_free(&rev->comb1);
                delay_free(&rev->comb2);
                return;
            }

            delay_init(&rev->comb4, comb_sizes[3], feedback, 1.0f, 0.0f);
            if (rev->comb4.buffer == NULL) {
                delay_free(&rev->comb1);
                delay_free(&rev->comb2);
                delay_free(&rev->comb3);
                return;
            }

            lpf_init(&rev->lpf, 1000.0f, sample_rate);

            rev->wet = wet;
            rev->dry = dry;
        }

        void reverb_free(Reverb *rev) {
            if (rev == NULL) return;
            
            delay_free(&rev->comb1);
            delay_free(&rev->comb2);
            delay_free(&rev->comb3);
            delay_free(&rev->comb4);
            
            memset(rev, 0, sizeof(Reverb));
        }

        float reverb_process(Reverb *rev, float input) {
            if (rev == NULL) return input;
            
            float comb_out = delay_process(&rev->comb1, input) +
                            delay_process(&rev->comb2, input) +
                            delay_process(&rev->comb3, input) +
                            delay_process(&rev->comb4, input);

            comb_out *= 0.25f;
            comb_out = lpf_process(&rev->lpf, comb_out);

            return input * rev->dry + comb_out * rev->wet;
        }

        // ============================================================
        // CHORUS EFFECT
        // ============================================================

        void chorus_init(Chorus *chor, float sample_rate, float rate, float depth, float wet, float dry) {
            if (chor == NULL || sample_rate <= 0.0f) {
                fprintf(stderr, "chorus_init: Invalid parameters\n");
                return;
            }

            memset(chor, 0, sizeof(Chorus));

            size_t base_delay = (size_t)(0.02f * sample_rate);
            if (base_delay == 0) base_delay = 1;

            delay_init(&chor->delay1, base_delay * 2, 0.0f, 1.0f, 0.0f);
            if (chor->delay1.buffer == NULL) return;

            delay_init(&chor->delay2, base_delay * 2, 0.0f, 1.0f, 0.0f);
            if (chor->delay2.buffer == NULL) {
                delay_free(&chor->delay1);
                return;
            }
        
            lpf_init(&chor->lpf, 2000.0f, sample_rate);

            chor->rate = rate;
            chor->depth = depth;
            chor->phase = 0.0f;
            chor->wet = wet;
            chor->dry = dry;
            chor->sample_rate = sample_rate;
        }

        void chorus_free(Chorus *chor) {
            if (chor == NULL) return;
            
            delay_free(&chor->delay1);
            delay_free(&chor->delay2);
            
            memset(chor, 0, sizeof(Chorus));
        }

        float chorus_process(Chorus *chor, float input) {
            if (chor == NULL) return input;
            
            chor->phase += chor->rate / chor->sample_rate;
            if (chor->phase >= 1.0f) chor->phase -= 1.0f;
            
            float delay_out1 = delay_process(&chor->delay1, input);
            float delay_out2 = delay_process(&chor->delay2, input);
            float chorus_out = (delay_out1 + delay_out2) * 0.5f;
            chorus_out = lpf_process(&chor->lpf, chorus_out);

            return input * chor->dry + chorus_out * chor->wet;
        }

        // ============================================================
        // BATCH PROCESSING (CPU)
        // ============================================================

        float *distortion_process_batch_cpu(float *input, int n, float drive, float threshold, float gain) {
            if (input == NULL || n <= 0) {
                fprintf(stderr, "distortion_process_batch_cpu: Invalid parameters\n");
                return NULL;
            }

            float *output = (float *)malloc(n * sizeof(float));
            if (output == NULL) {
                fprintf(stderr, "distortion_process_batch_cpu: Failed to allocate memory\n");
                return NULL;
            }

            Distortion dist;
            distortion_init(&dist, drive, threshold, gain);

            for (int i = 0; i < n; i++) {
                output[i] = distortion_process(&dist, input[i]);
            }

            return output;
        }

        float *lpf_process_batch_cpu(float *input, int n, float cutoff_freq, float sample_rate) {
            if (input == NULL || n <= 0 || sample_rate <= 0.0f) {
                fprintf(stderr, "lpf_process_batch_cpu: Invalid parameters\n");
                return NULL;
            }

            float *output = (float *)malloc(n * sizeof(float));
            if (output == NULL) {
                fprintf(stderr, "lpf_process_batch_cpu: Failed to allocate memory\n");
                return NULL;
            }

            LowPassFilter filter;
            lpf_init(&filter, cutoff_freq, sample_rate);

            for (int i = 0; i < n; i++) {
                output[i] = lpf_process(&filter, input[i]);
            }
            return output;
        }

        float *reverb_process_batch_cpu(float *input, int n, float *ir, int ir_len, float wet, float dry) {
            if (input == NULL || n <= 0 || ir == NULL || ir_len <= 0) {
                fprintf(stderr, "reverb_process_batch_cpu: Invalid parameters\n");
                return NULL;
            }

            float *output = (float *)malloc(n * sizeof(float));
            if (output == NULL) {
                fprintf(stderr, "reverb_process_batch_cpu: Failed to allocate memory\n");
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

        float *chorus_process_batch_cpu(float *input, int n, float sample_rate, float rate, float depth, float wet, float dry) {
            if (input == NULL || n <= 0) {
                fprintf(stderr, "chorus_process_batch_cpu: Invalid parameters\n");
                return NULL;
            }

            float *output = (float *)malloc(n * sizeof(float));
            if (output == NULL) {
                fprintf(stderr, "chorus_process_batch_cpu: Failed to allocate memory\n");
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

        // ============================================================
        // UTILITIES FOR Rust FFI
        // ============================================================

        void dsp_free_buffer(float *buffer) {
            if (buffer != NULL) {
                free(buffer);
            }
        }

        // ============================================================
        // CUDA SUPPORT
        // ============================================================

        #ifdef CUDA_SUPPORT

        float *distortion_process_batch_gpu(float *input, int n, float drive, float threshold, float gain) {
            if (!is_gpu_available()) {
                printf("GPU not available, using CPU fallback for distortion\n");
                return distortion_process_batch_cpu(input, n, drive, threshold, gain);
            }
            if (input == NULL || n <= 0) return NULL;
            
            float *output = (float *)malloc(n * sizeof(float));
            if (output == NULL) return NULL;
            
            cudaError_t err = process_distortion_gpu(input, output, n, drive, threshold, gain);
            if (err != cudaSuccess) {
                fprintf(stderr, "CUDA error in distortion: %s, using CPU fallback\n", cudaGetErrorString(err));
                free(output);
                return distortion_process_batch_cpu(input, n, drive, threshold, gain);
            }
            return output;
        }

        float *lpf_process_batch_gpu(float *input, int n, float cutoff_freq, float sample_rate) {
            if (!is_gpu_available()) {
                printf("GPU not available, using CPU fallback for LPF\n");
                return lpf_process_batch_cpu(input, n, cutoff_freq, sample_rate);
            }
            if (input == NULL || n <= 0) return NULL;
            
            float *output = (float *)malloc(n * sizeof(float));
            if (output == NULL) return NULL;
            
            cudaError_t err = process_lpf_gpu(input, output, n, cutoff_freq, sample_rate);
            if (err != cudaSuccess) {
                fprintf(stderr, "CUDA error in LPF: %s, using CPU fallback\n", cudaGetErrorString(err));
                free(output);
                return lpf_process_batch_cpu(input, n, cutoff_freq, sample_rate);
            }
            return output;
        }

        float *reverb_process_batch_gpu(float *input, int n, float *ir, int ir_len, float wet, float dry) {
            if (!is_gpu_available()) {
                printf("GPU not available, using CPU fallback for reverb\n");
                return reverb_process_batch_cpu(input, n, ir, ir_len, wet, dry);
            }
            if (input == NULL || n <= 0 || ir == NULL) return NULL;
            
            float *output = (float *)malloc(n * sizeof(float));
            if (output == NULL) return NULL;
            
            cudaError_t err = process_reverb_gpu(input, output, n, ir, ir_len, wet, dry);
            if (err != cudaSuccess) {
                fprintf(stderr, "CUDA error in reverb: %s, using CPU fallback\n", cudaGetErrorString(err));
                free(output);
                return reverb_process_batch_cpu(input, n, ir, ir_len, wet, dry);
            }
            return output;
        }

        float *chorus_process_batch_gpu(float *input, int n, float sample_rate, float rate, float depth, float wet, float dry) {
            if (!is_gpu_available()) {
                printf("GPU not available, using CPU fallback for chorus\n");
                return chorus_process_batch_cpu(input, n, sample_rate, rate, depth, wet, dry);
            }
            if (input == NULL || n <= 0) return NULL;
            
            float *output = (float *)malloc(n * sizeof(float));
            if (output == NULL) return NULL;
            
            cudaError_t err = process_chorus_gpu(input, output, n, sample_rate, rate, depth, wet, dry);
            if (err != cudaSuccess) {
                fprintf(stderr, "CUDA error in chorus: %s, using CPU fallback\n", cudaGetErrorString(err));
                free(output);
                return chorus_process_batch_cpu(input, n, sample_rate, rate, depth, wet, dry);
            }
            return output;
        }

        #endif // CUDA_SUPPORT

#ifdef __cplusplus
    }
#endif