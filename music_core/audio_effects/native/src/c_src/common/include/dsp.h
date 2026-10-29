#ifndef DSP_H
#define DSP_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
    extern "C" {
#endif

        // ============================================================================
        // DEBUG LOGGING MACROS
        // ============================================================================

        #ifndef DSP_LOG_ERROR
            #define DSP_LOG_ERROR(msg, ...) fprintf(stderr, "[ERROR] " msg "\n", ##__VA_ARGS__)
        #endif

        #ifndef DSP_LOG_DEBUG
            #define DSP_LOG_DEBUG(msg, ...) 
        #endif

        // ============================================================================
        // CONFIGURATION CONSTANTS
        // ============================================================================

        #ifndef DSP_REVERB_COMB1_DELAY
            #define DSP_REVERB_COMB1_DELAY 0.0297f
        #endif

        #ifndef DSP_REVERB_COMB2_DELAY
            #define DSP_REVERB_COMB2_DELAY 0.0371f
        #endif

        #ifndef DSP_REVERB_COMB3_DELAY
            #define DSP_REVERB_COMB3_DELAY 0.0411f
        #endif

        #ifndef DSP_REVERB_COMB4_DELAY
            #define DSP_REVERB_COMB4_DELAY 0.0437f
        #endif

        #ifndef DSP_REVERB_LPF_CUTOFF
            #define DSP_REVERB_LPF_CUTOFF 1000.0f
        #endif

        #ifndef DSP_CHORUS_BASE_DELAY
            #define DSP_CHORUS_BASE_DELAY 0.02f
        #endif

        #ifndef DSP_CHORUS_LPF_CUTOFF
            #define DSP_CHORUS_LPF_CUTOFF 2000.0f
        #endif

        // ============================================================================
        // DELAY BUFFER STRUCTURE
        // ============================================================================

        typedef struct {
            float *buffer;      // Delay line buffer
            size_t size;        // Size of buffer
            size_t write_pos;   // Current write position
            float feedback;     // Feedback amount (0.0 to 1.0)
            float wet;          // Wet mix (0.0 to 1.0)
            float dry;          // Dry mix (0.0 to 1.0)
        } DelayBuffer;

        // ============================================================================
        // LOW-PASS FILTER STRUCTURE
        // ============================================================================

        typedef struct {
            float b0;           // Feedforward coefficient
            float a1;           // Feedback coefficient
            float prev_out;     // Previous output sample
        } LowPassFilter;

        // ============================================================================
        // DISTORTION STRUCTURE
        // ============================================================================

        typedef struct {
            float drive;        // Drive amount
            float threshold;    // Clipping threshold
            float gain;         // Output gain
        } Distortion;

        // ============================================================================
        // REVERB STRUCTURE
        // ============================================================================

        typedef struct {
            DelayBuffer comb1;      // Comb filter 1
            DelayBuffer comb2;      // Comb filter 2
            DelayBuffer comb3;      // Comb filter 3
            DelayBuffer comb4;      // Comb filter 4
            LowPassFilter lpf;      // Low-pass filter
            float wet;              // Wet mix
            float dry;              // Dry mix
        } Reverb;

        // ============================================================================
        // CHORUS STRUCTURE
        // ============================================================================

        typedef struct {
            DelayBuffer delay1;     // Delay line 1
            DelayBuffer delay2;     // Delay line 2
            LowPassFilter lpf;      // Low-pass filter
            float rate;             // Modulation rate (Hz)
            float depth;            // Modulation depth
            float phase;            // Current LFO phase
            float wet;              // Wet mix
            float dry;              // Dry mix
            float sample_rate;      // Sample rate (Hz)
        } Chorus;

        // ============================================================================
        // DELAY EFFECT API
        // ============================================================================

        /**
         * @brief Initialize delay buffer
         * @param delay Pointer to delay buffer structure
         * @param size Size of the delay buffer
         * @param feedback Feedback amount (0.0 to 1.0)
         * @param wet Wet mix amount (0.0 to 1.0)
         * @param dry Dry mix amount (0.0 to 1.0)
         */
        void delay_init(DelayBuffer *delay, size_t size, float feedback, float wet, float dry);

        /**
         * @brief Free delay buffer
         * @param delay Pointer to delay buffer structure
         */
        void delay_free(DelayBuffer *delay);

        /**
         * @brief Process audio through delay buffer
         * @param delay Pointer to delay buffer structure
         * @param input Input audio sample
         * @return Processed audio sample
         */
        float delay_process(DelayBuffer *delay, float input);

        // ============================================================================
        // LOW-PASS FILTER API
        // ============================================================================

        /**
         * @brief Initialize low-pass filter
         * @param filter Pointer to low-pass filter structure
         * @param cutoff_freq Cutoff frequency in Hz
         * @param sample_rate Sample rate in Hz
         */
        void lpf_init(LowPassFilter *filter, float cutoff_freq, float sample_rate);

        /**
         * @brief Process audio through low-pass filter
         * @param filter Pointer to low-pass filter structure
         * @param input Input audio sample
         * @return Filtered audio sample
         */
        float lpf_process(LowPassFilter *filter, float input);

        /**
         * @brief Reset low-pass filter state
         * @param filter Pointer to low-pass filter structure
         */
        void lpf_reset(LowPassFilter *filter);

        // ============================================================================
        // DISTORTION EFFECT API
        // ============================================================================

        /**
         * @brief Initialize distortion effect
         * @param dist Pointer to distortion structure
         * @param drive Drive amount
         * @param threshold Threshold for soft clipping
         * @param gain Output gain
         */
        void distortion_init(Distortion *dist, float drive, float threshold, float gain);

        /**
         * @brief Process audio through distortion effect
         * @param dist Pointer to distortion structure
         * @param input Input audio sample
         * @return Distorted audio sample
         */
        float distortion_process(Distortion *dist, float input);

        // ============================================================================
        // REVERB EFFECT API
        // ============================================================================

        /**
         * @brief Initialize reverb effect
         * @param rev Pointer to reverb structure
         * @param sample_rate Sample rate in Hz
         * @param decay Decay time
         * @param wet Wet mix amount
         * @param dry Dry mix amount
         */
        void reverb_init(Reverb *rev, float sample_rate, float decay, float wet, float dry);

        /**
         * @brief Free reverb effect resources
         * @param rev Pointer to reverb structure
         */
        void reverb_free(Reverb *rev);

        /**
         * @brief Process audio through reverb effect
         * @param rev Pointer to reverb structure
         * @param input Input audio sample
         * @return Reverberated audio sample
         */
        float reverb_process(Reverb *rev, float input);

        // ============================================================================
        // CHORUS EFFECT API
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
        void chorus_init(Chorus *chor, float sample_rate, float rate, float depth, float wet, float dry);

        /**
         * @brief Free chorus effect resources
         * @param chor Pointer to chorus structure
         */
        void chorus_free(Chorus *chor);

        /**
         * @brief Process audio through chorus effect
         * @param chor Pointer to chorus structure
         * @param input Input audio sample
         * @return Chorus processed audio sample
         */
        float chorus_process(Chorus *chor, float input);

        // ============================================================================
        // BATCH PROCESSING API
        // ============================================================================

        /**
         * @brief Process batch of audio through distortion effect on CPU
         * @param input Input audio buffer
         * @param n Number of samples
         * @param drive Drive amount
         * @param threshold Threshold for soft clipping
         * @param gain Output gain
         * @return Processed audio buffer (must be freed by dsp_free_buffer)
         */
        float *distortion_process_batch_cpu(float *input, int n, float drive, float threshold, float gain);

        /**
         * @brief Process batch of audio through low-pass filter on CPU
         * @param input Input audio buffer
         * @param n Number of samples
         * @param cutoff_freq Cutoff frequency in Hz
         * @param sample_rate Sample rate in Hz
         * @return Processed audio buffer (must be freed by dsp_free_buffer)
         */
        float *lpf_process_batch_cpu(float *input, int n, float cutoff_freq, float sample_rate);

        /**
         * @brief Process batch of audio through reverb effect on CPU
         * @param input Input audio buffer
         * @param n Number of samples
         * @param ir Impulse response buffer
         * @param ir_len Length of impulse response
         * @param wet Wet mix amount
         * @param dry Dry mix amount
         * @return Processed audio buffer (must be freed by dsp_free_buffer)
         */
        float *reverb_process_batch_cpu(float *input, int n, float *ir, int ir_len, float wet, float dry);

        /**
         * @brief Process batch of audio through chorus effect on CPU
         * @param input Input audio buffer
         * @param n Number of samples
         * @param sample_rate Sample rate in Hz
         * @param rate Modulation rate in Hz
         * @param depth Modulation depth
         * @param wet Wet mix amount
         * @param dry Dry mix amount
         * @return Processed audio buffer (must be freed by dsp_free_buffer)
         */
        float *chorus_process_batch_cpu(float *input, int n, float sample_rate, float rate, float depth, float wet, float dry);

        // ============================================================================
        // UTILITIES
        // ============================================================================

        /**
         * @brief Free audio buffer allocated by DSP functions
         * @param buffer Pointer to buffer to free
         */
        void dsp_free_buffer(float *buffer);

        // ============================================================================
        // CUDA SUPPORT (optional)
        // ============================================================================

        #ifdef CUDA_SUPPORT

            /**
             * @brief Check if GPU is available
             * @return 1 if GPU is available, 0 otherwise
             */
            int is_gpu_available(void);

            /**
             * @brief Process batch of audio through distortion effect on GPU
             * @param input Input audio buffer
             * @param n Number of samples
             * @param drive Drive amount
             * @param threshold Threshold for soft clipping
             * @param gain Output gain
             * @return Processed audio buffer (must be freed by dsp_free_buffer)
             */
            float *distortion_process_batch_gpu(float *input, int n, float drive, float threshold, float gain);

            /**
             * @brief Process batch of audio through low-pass filter on GPU
             * @param input Input audio buffer
             * @param n Number of samples
             * @param cutoff_freq Cutoff frequency in Hz
             * @param sample_rate Sample rate in Hz
             * @return Processed audio buffer (must be freed by dsp_free_buffer)
             */
            float *lpf_process_batch_gpu(float *input, int n, float cutoff_freq, float sample_rate);

            /**
             * @brief Process batch of audio through reverb effect on GPU
             * @param input Input audio buffer
             * @param n Number of samples
             * @param ir Impulse response buffer
             * @param ir_len Length of impulse response
             * @param wet Wet mix amount
             * @param dry Dry mix amount
             * @return Processed audio buffer (must be freed by dsp_free_buffer)
             */
            float *reverb_process_batch_gpu(float *input, int n, float *ir, int ir_len, float wet, float dry);

            /**
             * @brief Process batch of audio through chorus effect on GPU
             * @param input Input audio buffer
             * @param n Number of samples
             * @param sample_rate Sample rate in Hz
             * @param rate Modulation rate in Hz
             * @param depth Modulation depth
             * @param wet Wet mix amount
             * @param dry Dry mix amount
             * @return Processed audio buffer (must be freed by dsp_free_buffer)
             */
            float *chorus_process_batch_gpu(float *input, int n, float sample_rate, float rate, float depth, float wet, float dry);

        #endif // CUDA_SUPPORT

#ifdef __cplusplus
    }
#endif

#endif // DSP_H