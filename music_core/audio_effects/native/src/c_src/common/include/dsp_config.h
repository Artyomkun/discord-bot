#ifndef DSP_CONFIG_H
#define DSP_CONFIG_H

/**
 * @brief Configuration constants for DSP effects
 */

// ============================================================================
// REVERB CONFIGURATION
// ============================================================================

#define DSP_REVERB_COMB1_DELAY 0.0297f  /**< Comb filter 1 delay in seconds */
#define DSP_REVERB_COMB2_DELAY 0.0371f  /**< Comb filter 2 delay in seconds */
#define DSP_REVERB_COMB3_DELAY 0.0411f  /**< Comb filter 3 delay in seconds */
#define DSP_REVERB_COMB4_DELAY 0.0437f  /**< Comb filter 4 delay in seconds */
#define DSP_REVERB_LPF_CUTOFF 1000.0f   /**< Low-pass filter cutoff for reverb tail */

// ============================================================================
// CHORUS CONFIGURATION
// ============================================================================

#define DSP_CHORUS_BASE_DELAY 0.02f     /**< Base delay for chorus in seconds */
#define DSP_CHORUS_LPF_CUTOFF 2000.0f   /**< Low-pass filter cutoff for chorus */

// ============================================================================
// CUDA CONFIGURATION
// ============================================================================

#define DSP_CUDA_DEFAULT_BLOCK_SIZE 256 /**< Default CUDA block size */
#define DSP_CUDA_MAX_BLOCK_SIZE 1024    /**< Maximum CUDA block size */

// ============================================================================
// LOGGING CONFIGURATION
// ============================================================================

#define DSP_LOG_LEVEL_DEBUG 0
#define DSP_LOG_LEVEL_INFO  1
#define DSP_LOG_LEVEL_WARN  2
#define DSP_LOG_LEVEL_ERROR 3
#define DSP_LOG_LEVEL_NONE  4

#ifndef DSP_LOG_LEVEL
    #define DSP_LOG_LEVEL DSP_LOG_LEVEL_INFO /**< Default log level */
#endif

// ============================================================================
// HELPER MACROS
// ============================================================================

/**
 * @brief Convert milliseconds to samples
 * @param ms Milliseconds
 * @param sr Sample rate
 */
#define DSP_MS_TO_SAMPLES(ms, sr) ((size_t)((ms) * (sr) / 1000.0f))

/**
 * @brief Convert seconds to samples
 * @param s Seconds
 * @param sr Sample rate
 */
#define DSP_SEC_TO_SAMPLES(s, sr) ((size_t)((s) * (sr)))

/**
 * @brief Clamp value between min and max
 */
#define DSP_CLAMP(val, min, max) ((val) < (min) ? (min) : ((val) > (max) ? (max) : (val)))

/**
 * @brief Check if value is power of two
 */
#define DSP_IS_POWER_OF_TWO(x) (((x) & ((x) - 1)) == 0)

#endif // DSP_CONFIG_H