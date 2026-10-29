/**
 * @file dsp.h
 * @brief Main DSP library header file
 *
 * This header provides the public API for DSP audio effects processing,
 * including CPU and GPU implementations with error handling.
 */

#ifndef DSP_H
#define DSP_H

#include <stdint.h>
#include <stddef.h>
#include "dsp_errors.h"
#include "dsp_config.h"

#ifdef __cplusplus
    extern "C" {
#endif

    // ============================================================================
    // DATA STRUCTURES
    // ============================================================================

    /**
     * @brief Simple delay buffer structure
     *
     * Implements a circular buffer for delay effects with feedback.
     */
    typedef struct {
        float *buffer;      /**< Delay buffer data */
        size_t size;        /**< Buffer size in samples */
        size_t write_pos;   /**< Current write position */
        float feedback;     /**< Feedback amount (0.0 to 1.0) */
        float wet;          /**< Wet signal mix (0.0 to 1.0) */
        float dry;          /**< Dry signal mix (0.0 to 1.0) */
    } DelayBuffer;

    /**
     * @brief Low-pass filter structure
     */
    typedef struct {
        float a1;           /**< Feedback coefficient */
        float b0;           /**< Feedforward coefficient */
        float prev_out;     /**< Previous output sample */
    } LowPassFilter;

    /**
     * @brief Distortion effect structure
     */
    typedef struct {
        float drive;        /**< Drive amount */
        float threshold;    /**< Clipping threshold */
        float gain;         /**< Output gain */
    } Distortion;

    /**
     * @brief Reverb effect structure
     */
    typedef struct {
        DelayBuffer comb1, comb2, comb3, comb4; /**< Comb filters */
        LowPassFilter lpf;                      /**< Low-pass filter */
        float wet;          /**< Wet mix */
        float dry;          /**< Dry mix */
    } Reverb;

    /**
     * @brief Chorus effect structure
     */
    typedef struct {
        DelayBuffer delay1, delay2; /**< Delay lines */
        LowPassFilter lpf;          /**< Low-pass filter */
        float rate;         /**< Modulation rate (Hz) */
        float depth;        /**< Modulation depth */
        float phase;        /**< Current LFO phase */
        float wet;          /**< Wet mix */
        float dry;          /**< Dry mix */
        float sample_rate;  /**< Sample rate (Hz) */
    } Chorus;

    // ============================================================================
    // DELAY API
    // ============================================================================

    /**
     * @brief Initialize delay buffer
     * @param delay Pointer to delay buffer structure
     * @param size Buffer size in samples
     * @param feedback Feedback amount (0.0 to 1.0)
     * @param wet Wet signal mix (0.0 to 1.0)
     * @param dry Dry signal mix (0.0 to 1.0)
     */
    void delay_init(DelayBuffer *delay, size_t size, float feedback, float wet, float dry);

    /**
     * @brief Free delay buffer resources
     * @param delay Pointer to delay buffer structure
     */
    void delay_free(DelayBuffer *delay);

    /**
     * @brief Process single sample through delay effect
     * @param delay Pointer to delay buffer structure
     * @param input Input sample
     * @return Output sample
     */
    float delay_process(DelayBuffer *delay, float input);

    // ============================================================================
    // LOW-PASS FILTER API
    // ============================================================================

    /**
     * @brief Initialize low-pass filter
     * @param filter Pointer to filter structure
     * @param cutoff_freq Cutoff frequency in Hz
     * @param sample_rate Sample rate in Hz
     */
    void lpf_init(LowPassFilter *filter, float cutoff_freq, float sample_rate);

    /**
     * @brief Process single sample through low-pass filter
     * @param filter Pointer to filter structure
     * @param input Input sample
     * @return Filtered output sample
     */
    float lpf_process(LowPassFilter *filter, float input);

    /**
     * @brief Reset low-pass filter state
     * @param filter Pointer to filter structure
     */
    void lpf_reset(LowPassFilter *filter);

    // ============================================================================
    // DISTORTION API
    // ============================================================================

    /**
     * @brief Initialize distortion effect
     * @param dist Pointer to distortion structure
     * @param drive Drive amount
     * @param threshold Clipping threshold
     * @param gain Output gain
     */
    void distortion_init(Distortion *dist, float drive, float threshold, float gain);

    /**
     * @brief Process single sample through distortion
     * @param dist Pointer to distortion structure
     * @param input Input sample
     * @return Distorted output sample
     */
    float distortion_process(Distortion *dist, float input);

    // ============================================================================
    // REVERB API
    // ============================================================================

    /**
     * @brief Initialize reverb effect
     * @param rev Pointer to reverb structure
     * @param sample_rate Sample rate in Hz
     * @param decay Decay time in seconds
     * @param wet Wet mix (0.0 to 1.0)
     * @param dry Dry mix (0.0 to 1.0)
     */
    void reverb_init(Reverb *rev, float sample_rate, float decay, float wet, float dry);

    /**
     * @brief Free reverb effect resources
     * @param rev Pointer to reverb structure
     */
    void reverb_free(Reverb *rev);

    /**
     * @brief Process single sample through reverb
     * @param rev Pointer to reverb structure
     * @param input Input sample
     * @return Reverberated output sample
     */
    float reverb_process(Reverb *rev, float input);

    // ============================================================================
    // CHORUS API
    // ============================================================================

    /**
     * @brief Initialize chorus effect
     * @param chor Pointer to chorus structure
     * @param sample_rate Sample rate in Hz
     * @param rate Modulation rate in Hz
     * @param depth Modulation depth
     * @param wet Wet mix (0.0 to 1.0)
     * @param dry Dry mix (0.0 to 1.0)
     */
    void chorus_init(Chorus *chor, float sample_rate, float rate, float depth, float wet, float dry);

    /**
     * @brief Free chorus effect resources
     * @param chor Pointer to chorus structure
     */
    void chorus_free(Chorus *chor);

    /**
     * @brief Process single sample through chorus
     * @param chor Pointer to chorus structure
     * @param input Input sample
     * @return Chorus output sample
     */
    float chorus_process(Chorus *chor, float input);

    // ============================================================================
    // BATCH PROCESSING API (CPU)
    // ============================================================================

    /**
     * @brief Process batch of audio through distortion effect on CPU
     * @param input Input audio buffer (must be freed by caller)
     * @param n Number of samples
     * @param drive Drive amount
     * @param threshold Clipping threshold
     * @param gain Output gain
     * @return Processed audio buffer (must be freed with dsp_free_buffer)
     */
    float *distortion_process_batch_cpu(float *input, int n, float drive, float threshold, float gain);

    /**
     * @brief Process batch of audio through low-pass filter on CPU
     * @param input Input audio buffer
     * @param n Number of samples
     * @param cutoff_freq Cutoff frequency in Hz
     * @param sample_rate Sample rate in Hz
     * @return Processed audio buffer (must be freed with dsp_free_buffer)
     */
    float *lpf_process_batch_cpu(float *input, int n, float cutoff_freq, float sample_rate);

    /**
     * @brief Process batch of audio through reverb effect on CPU
     * @param input Input audio buffer
     * @param n Number of samples
     * @param ir Impulse response buffer
     * @param ir_len Length of impulse response
     * @param wet Wet mix
     * @param dry Dry mix
     * @return Processed audio buffer (must be freed with dsp_free_buffer)
     */
    float *reverb_process_batch_cpu(float *input, int n, float *ir, int ir_len, float wet, float dry);

    /**
     * @brief Process batch of audio through chorus effect on CPU
     * @param input Input audio buffer
     * @param n Number of samples
     * @param sample_rate Sample rate in Hz
     * @param rate Modulation rate in Hz
     * @param depth Modulation depth
     * @param wet Wet mix
     * @param dry Dry mix
     * @return Processed audio buffer (must be freed with dsp_free_buffer)
     */
    float *chorus_process_batch_cpu(float *input, int n, float sample_rate, float rate, float depth, float wet, float dry);

    /**
     * @brief Free buffer allocated by batch processing functions
     * @param buffer Pointer to buffer to free
     */
    void dsp_free_buffer(float *buffer);

    // ============================================================================
    // BATCH PROCESSING API (GPU) - Optional
    // ============================================================================

    #ifdef CUDA_SUPPORT
        /**
         * @brief Process batch of audio through distortion effect on GPU
         * @param input Input audio buffer
         * @param n Number of samples
         * @param drive Drive amount
         * @param threshold Clipping threshold
         * @param gain Output gain
         * @return Processed audio buffer (must be freed with dsp_free_buffer)
         */
        float *distortion_process_batch_gpu(float *input, int n, float drive, float threshold, float gain);

        /**
         * @brief Process batch of audio through low-pass filter on GPU
         * @param input Input audio buffer
         * @param n Number of samples
         * @param cutoff_freq Cutoff frequency in Hz
         * @param sample_rate Sample rate in Hz
         * @return Processed audio buffer (must be freed with dsp_free_buffer)
         */
        float *lpf_process_batch_gpu(float *input, int n, float cutoff_freq, float sample_rate);

        /**
         * @brief Process batch of audio through reverb effect on GPU
         * @param input Input audio buffer
         * @param n Number of samples
         * @param ir Impulse response buffer
         * @param ir_len Length of impulse response
         * @param wet Wet mix
         * @param dry Dry mix
         * @return Processed audio buffer (must be freed with dsp_free_buffer)
         */
        float *reverb_process_batch_gpu(float *input, int n, float *ir, int ir_len, float wet, float dry);

        /**
         * @brief Process batch of audio through chorus effect on GPU
         * @param input Input audio buffer
         * @param n Number of samples
         * @param sample_rate Sample rate in Hz
         * @param rate Modulation rate in Hz
         * @param depth Modulation depth
         * @param wet Wet mix
         * @param dry Dry mix
         * @return Processed audio buffer (must be freed with dsp_free_buffer)
         */
        float *chorus_process_batch_gpu(float *input, int n, float sample_rate, float rate, float depth, float wet, float dry);

    #endif // CUDA_SUPPORT

#ifdef __cplusplus
    }
#endif

#endif // DSP_H