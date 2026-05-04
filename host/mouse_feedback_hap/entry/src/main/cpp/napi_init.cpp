#include "napi/native_api.h"

#include <multimodalinput/oh_input_manager.h>
#include <multimedia/player_framework/native_avscreen_capture.h>

#include <stdbool.h>
#include <string.h>
#include <mutex>
#include <string>

namespace {

struct MouseMonitorContext {
    napi_threadsafe_function tsfn = nullptr;
    int32_t lastX = 0;
    int32_t lastY = 0;
    bool running = false;
    std::mutex mtx;
};

MouseMonitorContext g_mouseCtx;

void onMouseEvent(const Input_MouseEvent* event) {
    int32_t action = OH_Input_GetMouseEventAction(event);
    if (action != MOUSE_ACTION_MOVE) {
        return;
    }

    int32_t x = OH_Input_GetMouseEventDisplayX(event);
    int32_t y = OH_Input_GetMouseEventDisplayY(event);

    if (x < 0 || y < 0) {
        return;
    }

    std::lock_guard<std::mutex> lock(g_mouseCtx.mtx);
    g_mouseCtx.lastX = x;
    g_mouseCtx.lastY = y;

    if (g_mouseCtx.tsfn != nullptr) {
        napi_call_threadsafe_function(g_mouseCtx.tsfn, nullptr, napi_tsfn_nonblocking);
    }
}

void callJS(napi_env env, napi_value js_callback, void* context, void* data) {
    (void)context;
    (void)data;

    int32_t x, y;
    {
        std::lock_guard<std::mutex> lock(g_mouseCtx.mtx);
        x = g_mouseCtx.lastX;
        y = g_mouseCtx.lastY;
    }

    napi_value args[2];
    napi_create_int32(env, x, &args[0]);
    napi_create_int32(env, y, &args[1]);

    napi_value result;
    napi_call_function(env, nullptr, js_callback, 2, args, &result);
}

static napi_value StartMouseMonitor(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1) {
        napi_throw_error(env, nullptr, "Expected 1 argument: callback function");
        return nullptr;
    }

    napi_value callback = args[0];
    napi_valuetype type;
    napi_typeof(env, callback, &type);
    if (type != napi_function) {
        napi_throw_error(env, nullptr, "Argument must be a function");
        return nullptr;
    }

    if (g_mouseCtx.running) {
        napi_value result;
        napi_get_boolean(env, true, &result);
        return result;
    }

    // Release old tsfn if exists
    if (g_mouseCtx.tsfn != nullptr) {
        napi_release_threadsafe_function(g_mouseCtx.tsfn, napi_tsfn_release);
        g_mouseCtx.tsfn = nullptr;
    }

    napi_value resourceName;
    napi_create_string_utf8(env, "MouseMonitorTSFN", NAPI_AUTO_LENGTH, &resourceName);

    napi_status status = napi_create_threadsafe_function(
        env,
        callback,       // js callback
        nullptr,        // async resource
        resourceName,   // resource name
        0,              // max queue size (0 = unlimited)
        1,              // initial thread count
        nullptr,        // thread finalize data
        nullptr,        // thread finalize callback
        nullptr,        // context
        callJS,         // call js callback
        &g_mouseCtx.tsfn
    );

    if (status != napi_ok) {
        napi_throw_error(env, nullptr, "Failed to create threadsafe function");
        return nullptr;
    }

    Input_Result monitorResult = OH_Input_AddMouseEventMonitor(onMouseEvent);
    if (monitorResult != INPUT_SUCCESS) {
        napi_release_threadsafe_function(g_mouseCtx.tsfn, napi_tsfn_release);
        g_mouseCtx.tsfn = nullptr;

        char errMsg[128];
        snprintf(errMsg, sizeof(errMsg), "Failed to register mouse monitor: error %d. Requires ohos.permission.INPUT_MONITORING.", (int)monitorResult);
        napi_throw_error(env, nullptr, errMsg);
        return nullptr;
    }

    g_mouseCtx.running = true;

    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

static napi_value StopMouseMonitor(napi_env env, napi_callback_info info) {
    (void)info;

    if (!g_mouseCtx.running) {
        napi_value result;
        napi_get_boolean(env, true, &result);
        return result;
    }

    OH_Input_RemoveMouseEventMonitor(onMouseEvent);

    if (g_mouseCtx.tsfn != nullptr) {
        napi_release_threadsafe_function(g_mouseCtx.tsfn, napi_tsfn_release);
        g_mouseCtx.tsfn = nullptr;
    }

    g_mouseCtx.running = false;

    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

static napi_value IsMonitorRunning(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value result;
    napi_get_boolean(env, g_mouseCtx.running, &result);
    return result;
}

static napi_value GetVersion(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value result;
    napi_create_string_utf8(env, "mouse_feedback_hap_1.0.0", NAPI_AUTO_LENGTH, &result);
    return result;
}

static OH_AVScreenCapture* g_screenCapture = nullptr;

static napi_value StartScreenCapture(napi_env env, napi_callback_info info) {
    (void)info;

    if (g_screenCapture != nullptr) {
        napi_value result;
        napi_get_boolean(env, true, &result);
        return result;
    }

    g_screenCapture = OH_AVScreenCapture_Create();
    if (g_screenCapture == nullptr) {
        napi_throw_error(env, nullptr, "Failed to create screen capture instance");
        return nullptr;
    }

    OH_AVScreenCaptureConfig config;
    memset(&config, 0, sizeof(config));
    config.captureMode = OH_CAPTURE_HOME_SCREEN;
    config.dataType = OH_ORIGINAL_STREAM;
    // No audio
    config.audioInfo.micCapInfo.audioSampleRate = 0;
    config.audioInfo.micCapInfo.audioChannels = 0;
    config.audioInfo.micCapInfo.audioSource = OH_SOURCE_INVALID;
    // Minimal video config
    config.videoInfo.videoCapInfo.videoFrameWidth = 1;
    config.videoInfo.videoCapInfo.videoFrameHeight = 1;
    config.videoInfo.videoCapInfo.videoSource = OH_VIDEO_SOURCE_SURFACE_RGBA;
    config.videoInfo.videoEncInfo.videoCodec = OH_VIDEO_DEFAULT;
    config.videoInfo.videoEncInfo.videoBitrate = 0;
    config.videoInfo.videoEncInfo.videoFrameRate = 1;

    OH_AVSCREEN_CAPTURE_ErrCode ret = OH_AVScreenCapture_Init(g_screenCapture, config);
    if (ret != AV_SCREEN_CAPTURE_ERR_OK) {
        OH_AVScreenCapture_Release(g_screenCapture);
        g_screenCapture = nullptr;

        char errMsg[128];
        snprintf(errMsg, sizeof(errMsg), "Failed to init screen capture: error %d", (int)ret);
        napi_throw_error(env, nullptr, errMsg);
        return nullptr;
    }

    ret = OH_AVScreenCapture_StartScreenCapture(g_screenCapture);
    if (ret != AV_SCREEN_CAPTURE_ERR_OK) {
        OH_AVScreenCapture_Release(g_screenCapture);
        g_screenCapture = nullptr;

        char errMsg[128];
        snprintf(errMsg, sizeof(errMsg), "Failed to start screen capture: error %d", (int)ret);
        napi_throw_error(env, nullptr, errMsg);
        return nullptr;
    }

    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

static napi_value StopScreenCapture(napi_env env, napi_callback_info info) {
    (void)info;

    if (g_screenCapture == nullptr) {
        napi_value result;
        napi_get_boolean(env, true, &result);
        return result;
    }

    OH_AVScreenCapture_StopScreenCapture(g_screenCapture);
    OH_AVScreenCapture_Release(g_screenCapture);
    g_screenCapture = nullptr;

    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"startMouseMonitor", nullptr, StartMouseMonitor, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopMouseMonitor", nullptr, StopMouseMonitor, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isMonitorRunning", nullptr, IsMonitorRunning, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startScreenCapture", nullptr, StartScreenCapture, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopScreenCapture", nullptr, StopScreenCapture, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getVersion", nullptr, GetVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
    };

    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

} // anonymous namespace

NAPI_MODULE(mousefeedback_native, Init)
