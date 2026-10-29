#include "../common/include/dsp_errors.h"

/**
 * @brief Convert error code to string
 * @param error The error code
 * @return String representation of the error
 */
const char* dsp_error_string(dsp_error_t error) {
    switch (error) {
        case DSP_SUCCESS:
            return "Success";
        case DSP_ERROR_INVALID_PARAM:
            return "Invalid parameter";
        case DSP_ERROR_MEMORY:
            return "Memory allocation failed";
        case DSP_ERROR_INVALID_STATE:
            return "Invalid object state";
        case DSP_ERROR_CUDA:
            return "CUDA operation failed";
        case DSP_ERROR_IO:
            return "I/O operation failed";
        case DSP_ERROR_NOT_IMPLEMENTED:
            return "Feature not implemented";
        default:
            return "Unknown error";
    }
}