// C Header declaration for Cactus FFI bridge used by Pantry Pilot Android runtime
#ifndef CACTUS_BRIDGE_H
#define CACTUS_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void* CactusHandle;

// Lifecycle
CactusHandle cactus_init(const char* model_path, bool use_npu);
void         cactus_destroy(CactusHandle handle);

// Mirage Vision/OCR
const char*  cactus_mirage_ocr(CactusHandle handle, const uint8_t* yuv_bytes, int32_t width, int32_t height);

// Needle LLM / Tool Calling Agent
const char*  cactus_needle_complete(CactusHandle handle, const char* messages_json, const char* tools_json);

// Memory
void         cactus_free_string(const char* ptr);

#ifdef __cplusplus
}
#endif

#endif // CACTUS_BRIDGE_H

