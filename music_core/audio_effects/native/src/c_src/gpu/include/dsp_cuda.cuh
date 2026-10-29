#ifndef DSP_CUDA_H
#define DSP_CUDA_H

#include <cuda_runtime.h>

#ifdef __cplusplus
    extern "C" {
#endif
        /**
         * @brief Process audio through distortion effect on GPU
         * @param input Input buffer on GPU device
         * @param output Output buffer on GPU device
         * @param n Number of samples
         * @param drive Drive amount (0.1 to 10.0)
         * @param threshold Clipping threshold (0.01 to 1.0)
         * @param gain Output gain (0.0 to 2.0)
         * @return cudaSuccess on success, error code otherwise
         */
        cudaError_t process_distortion_gpu(
            const float *input,
            float *output,
            int n,
            float drive,
            float threshold,
            float gain
        );

        /**
         * @brief Process audio through low-pass filter on GPU
         * @note LPF is recursive and not efficient on GPU. Consider using CPU.
         * @param input Input buffer on GPU device
         * @param output Output buffer on GPU device
         * @param n Number of samples
         * @param cutoff_freq Cutoff frequency in Hz (20.0 to sample_rate/2)
         * @param sample_rate Sample rate in Hz
         * @return cudaSuccess on success, error code otherwise
         */
        cudaError_t process_lpf_gpu(
            const float *input,
            float *output,
            int n,
            float cutoff_freq,
            float sample_rate
        );

        /**
         * @brief Process audio through convolution reverb on GPU
         * @param input Input buffer on GPU device
         * @param output Output buffer on GPU device
         * @param n Number of samples
         * @param ir Impulse response buffer on GPU device
         * @param ir_len Length of impulse response in samples
         * @param wet Wet mix amount (0.0 to 1.0)
         * @param dry Dry mix amount (0.0 to 1.0)
         * @return cudaSuccess on success, error code otherwise
         * @note Complexity: O(n * ir_len). For large IR, use FFT-based convolution.
         */
        cudaError_t process_reverb_gpu(
            const float *input,
            float *output,
            int n,
            const float *ir,
            int ir_len,
            float wet,
            float dry
        );

        /**
         * @brief Process audio through chorus effect on GPU
         * @param input Input buffer on GPU device
         * @param output Output buffer on GPU device
         * @param n Number of samples
         * @param sample_rate Sample rate in Hz
         * @param rate Modulation rate in Hz (0.1 to 5.0)
         * @param depth Modulation depth (0.0 to 1.0)
         * @param wet Wet mix amount (0.0 to 1.0)
         * @param dry Dry mix amount (0.0 to 1.0)
         * @return cudaSuccess on success, error code otherwise
         */
        cudaError_t process_chorus_gpu(
            const float *input,
            float *output,
            int n,
            float sample_rate,
            float rate,
            float depth,
            float wet,
            float dry
        );

#ifdef __cplusplus
    }
#endif

#endif // DSP_CUDA_H