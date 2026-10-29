#ifndef DSP_LOGGING_H
#define DSP_LOGGING_H

#include "dsp_config.h"
#include <stdio.h>

/**
 * @brief Logging macros for DSP library
 * 
 * Usage:
 *   DSP_LOG_DEBUG("Initialized buffer with size %zu", size);
 *   DSP_LOG_INFO("Processing started");
 *   DSP_LOG_WARN("Low memory condition");
 *   DSP_LOG_ERROR("Failed to allocate memory");
 */

#define DSP_LOG_DEBUG(fmt, ...) do { \
        if (DSP_LOG_LEVEL <= DSP_LOG_LEVEL_DEBUG) \
            fprintf(stderr, "[DEBUG] " fmt "\n", ##__VA_ARGS__); \
    } while(0)

#define DSP_LOG_INFO(fmt, ...) do { \
        if (DSP_LOG_LEVEL <= DSP_LOG_LEVEL_INFO) \
            fprintf(stderr, "[INFO] " fmt "\n", ##__VA_ARGS__); \
    } while(0)

#define DSP_LOG_WARN(fmt, ...) do { \
        if (DSP_LOG_LEVEL <= DSP_LOG_LEVEL_WARN) \
            fprintf(stderr, "[WARN] " fmt "\n", ##__VA_ARGS__); \
    } while(0)

#define DSP_LOG_ERROR(fmt, ...) do { \
        if (DSP_LOG_LEVEL <= DSP_LOG_LEVEL_ERROR) \
            fprintf(stderr, "[ERROR] " fmt "\n", ##__VA_ARGS__); \
    } while(0)

#endif // DSP_LOGGING_H