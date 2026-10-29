#ifndef DSP_EFFECT_H
#define DSP_EFFECT_H

#include "dsp_errors.h"

#ifdef __cplusplus
    extern "C" {
#endif

        // ============================================================================
        // FUNCTION POINTER TYPES
        // ============================================================================

        /**
         * @brief Effect initialization function type
         * @param effect Pointer to effect instance
         * @param ... Variable arguments (configuration parameters)
         * @return DSP_SUCCESS on success, error code otherwise
         */
        typedef dsp_error_t (*effect_init_func)(void *effect, ...);

        /**
         * @brief Effect processing function type (single sample)
         * @param effect Pointer to effect instance
         * @param input Input audio sample
         * @param output Output audio sample (can be same as input for in-place)
         * @return DSP_SUCCESS on success, error code otherwise
         */
        typedef dsp_error_t (*effect_process_func)(void *effect, float input, float *output);

        /**
         * @brief Effect batch processing function type
         * @param input Input audio buffer
         * @param n Number of samples
         * @param params Effect parameters
         * @param output Output buffer (allocated by the function, must be freed)
         * @return DSP_SUCCESS on success, error code otherwise
         */
        typedef dsp_error_t (*effect_batch_func)(float *input, int n, void *params, float **output);

        /**
         * @brief Effect cleanup function type
         * @param effect Pointer to effect instance
         * @return DSP_SUCCESS on success, error code otherwise
         */
        typedef dsp_error_t (*effect_free_func)(void *effect);

        /**
         * @brief Effect parameter update function type
         * @param effect Pointer to effect instance
         * @param params Parameter name/value pairs
         * @return DSP_SUCCESS on success, error code otherwise
         */
        typedef dsp_error_t (*effect_update_func)(void *effect, const char *param_name, float value);

        /**
         * @brief Effect reset function type
         * @param effect Pointer to effect instance
         * @return DSP_SUCCESS on success, error code otherwise
         */
        typedef dsp_error_t (*effect_reset_func)(void *effect);

        // ============================================================================
        // EFFECT INTERFACE STRUCTURE
        // ============================================================================

        /**
         * @brief Generic effect interface
         * 
         * This structure allows for extensible effect implementations
         * without modifying the core library.
         * 
         * Usage example:
         * @code
         * dsp_effect_t delay = {
         *     .instance = &my_delay,
         *     .init = delay_init_func,
         *     .process = delay_process_func,
         *     .batch_process = delay_batch_func,
         *     .free = delay_free_func,
         *     .update = delay_update_func,
         *     .reset = delay_reset_func,
         *     .name = "delay"
         * };
         * dsp_error_t err = dsp_effect_register(&delay);
         * @endcode
         */
        typedef struct {
            void *instance;                    /**< Effect instance data */
            effect_init_func init;             /**< Initialization function */
            effect_process_func process;       /**< Single sample processing */
            effect_batch_func batch_process;   /**< Batch processing (optional) */
            effect_free_func free;             /**< Cleanup function */
            effect_update_func update;         /**< Parameter update function (optional) */
            effect_reset_func reset;           /**< Reset function (optional) */
            const char *name;                  /**< Effect name for identification */
        } dsp_effect_t;

        // ============================================================================
        // EFFECT REGISTRY API
        // ============================================================================

        /**
         * @brief Register a new effect
         * @param effect Pointer to effect interface
         * @return DSP_SUCCESS on success, error code otherwise
         * 
         * @note Effect name must be unique. The library maintains an internal
         *       registry of registered effects.
         */
        dsp_error_t dsp_effect_register(dsp_effect_t *effect);

        /**
         * @brief Unregister an effect by name
         * @param name Effect name
         * @return DSP_SUCCESS on success, error code otherwise
         */
        dsp_error_t dsp_effect_unregister(const char *name);

        /**
         * @brief Get registered effect by name
         * @param name Effect name
         * @return Pointer to effect interface or NULL if not found
         */
        dsp_effect_t* dsp_effect_get(const char *name);

        /**
         * @brief List all registered effects
         * @param effects Array to fill with effect pointers
         * @param max_count Maximum number of effects to return
         * @return Number of effects returned
         */
        int dsp_effect_list(dsp_effect_t **effects, int max_count);

        /**
         * @brief Get number of registered effects
         * @return Number of registered effects
         */
        int dsp_effect_count(void);

        /**
         * @brief Clear all registered effects (for cleanup)
         */
        void dsp_effect_clear_all(void);

        // ============================================================================
        // CONVENIENCE MACROS
        // ============================================================================

        /**
         * @brief Helper macro to check effect pointer
         */
        #define DSP_EFFECT_VALID(effect) ((effect) != NULL && (effect)->process != NULL)

        /**
         * @brief Helper macro to call effect process safely
         */
        #define DSP_EFFECT_PROCESS(effect, input, output) \
            (DSP_EFFECT_VALID(effect) ? (effect)->process((effect)->instance, input, output) : DSP_ERR_INVALID_PARAM)

#ifdef __cplusplus
    }
#endif

#endif // DSP_EFFECT_H