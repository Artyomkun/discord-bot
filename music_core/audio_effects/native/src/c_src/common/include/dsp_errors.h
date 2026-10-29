#ifndef DSP_ERRORS_H
#define DSP_ERRORS_H

#ifdef __cplusplus
    extern "C" {
#endif

        /**
         * @brief Error codes for DSP library
         */
        typedef enum {
            DSP_SUCCESS = 0,              /**< Operation completed successfully */
            DSP_ERROR_INVALID_PARAM = -1, /**< Invalid parameter passed to function */
            DSP_ERROR_MEMORY = -2,        /**< Memory allocation failed */
            DSP_ERROR_INVALID_STATE = -3, /**< Object is in invalid state */
            DSP_ERROR_CUDA = -4,          /**< CUDA operation failed */
            DSP_ERROR_IO = -5,            /**< I/O operation failed */
            DSP_ERROR_NOT_IMPLEMENTED = -6,/**< Feature not implemented */
            DSP_ERROR_NULL_POINTER = -7,  /**< Null pointer provided */
            DSP_ERROR_BUFFER_TOO_SMALL = -8,/**< Buffer too small */
            DSP_ERROR_NOT_FOUND = -9,     /**< Resource not found */
            DSP_ERROR_ALREADY_EXISTS = -10 /**< Resource already exists */
        } dsp_error_t;

        /**
         * @brief Get error message string
         * @param error Error code
         * @return Error message string
         */
        const char* dsp_error_string(dsp_error_t error);

#ifdef __cplusplus
    }
#endif

#endif // DSP_ERRORS_H