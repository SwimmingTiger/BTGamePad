#include "napi/native_api.h"

#include <GameControllerKit/game_device.h>
#include <GameControllerKit/game_device_event.h>
#include <GameControllerKit/game_pad.h>
#include <GameControllerKit/game_pad_event.h>

#include <algorithm>
#include <deque>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

namespace {

constexpr int32_t DEFAULT_POLL_EVENT_COUNT = 32;
constexpr size_t MAX_BUFFERED_EVENT_COUNT = 256;

std::mutex g_stateMutex;
std::mutex g_queueMutex;
std::deque<std::string> g_eventQueue;
bool g_monitoringStarted = false;
int32_t g_lastErrorCode = GAME_CONTROLLER_SUCCESS;

using ButtonRegisterFn = GameController_ErrorCode (*)(GamePad_ButtonInputMonitorCallback);
using ButtonUnregisterFn = GameController_ErrorCode (*)(void);
using AxisRegisterFn = GameController_ErrorCode (*)(GamePad_AxisInputMonitorCallback);
using AxisUnregisterFn = GameController_ErrorCode (*)(void);

struct ButtonMonitorDescriptor {
    ButtonRegisterFn registerFn;
    ButtonUnregisterFn unregisterFn;
};

struct AxisMonitorDescriptor {
    AxisRegisterFn registerFn;
    AxisUnregisterFn unregisterFn;
};

const ButtonMonitorDescriptor BUTTON_MONITORS[] = {
    { OH_GamePad_LeftShoulder_RegisterButtonInputMonitor, OH_GamePad_LeftShoulder_UnregisterButtonInputMonitor },
    { OH_GamePad_RightShoulder_RegisterButtonInputMonitor, OH_GamePad_RightShoulder_UnregisterButtonInputMonitor },
    { OH_GamePad_LeftTrigger_RegisterButtonInputMonitor, OH_GamePad_LeftTrigger_UnregisterButtonInputMonitor },
    { OH_GamePad_RightTrigger_RegisterButtonInputMonitor, OH_GamePad_RightTrigger_UnregisterButtonInputMonitor },
    { OH_GamePad_ButtonMenu_RegisterButtonInputMonitor, OH_GamePad_ButtonMenu_UnregisterButtonInputMonitor },
    { OH_GamePad_ButtonHome_RegisterButtonInputMonitor, OH_GamePad_ButtonHome_UnregisterButtonInputMonitor },
    { OH_GamePad_ButtonA_RegisterButtonInputMonitor, OH_GamePad_ButtonA_UnregisterButtonInputMonitor },
    { OH_GamePad_ButtonB_RegisterButtonInputMonitor, OH_GamePad_ButtonB_UnregisterButtonInputMonitor },
    { OH_GamePad_ButtonX_RegisterButtonInputMonitor, OH_GamePad_ButtonX_UnregisterButtonInputMonitor },
    { OH_GamePad_ButtonY_RegisterButtonInputMonitor, OH_GamePad_ButtonY_UnregisterButtonInputMonitor },
    { OH_GamePad_ButtonC_RegisterButtonInputMonitor, OH_GamePad_ButtonC_UnregisterButtonInputMonitor },
    { OH_GamePad_Dpad_LeftButton_RegisterButtonInputMonitor, OH_GamePad_Dpad_LeftButton_UnregisterButtonInputMonitor },
    { OH_GamePad_Dpad_RightButton_RegisterButtonInputMonitor, OH_GamePad_Dpad_RightButton_UnregisterButtonInputMonitor },
    { OH_GamePad_Dpad_UpButton_RegisterButtonInputMonitor, OH_GamePad_Dpad_UpButton_UnregisterButtonInputMonitor },
    { OH_GamePad_Dpad_DownButton_RegisterButtonInputMonitor, OH_GamePad_Dpad_DownButton_UnregisterButtonInputMonitor },
    { OH_GamePad_LeftThumbstick_RegisterButtonInputMonitor, OH_GamePad_LeftThumbstick_UnregisterButtonInputMonitor },
    { OH_GamePad_RightThumbstick_RegisterButtonInputMonitor, OH_GamePad_RightThumbstick_UnregisterButtonInputMonitor },
};

const AxisMonitorDescriptor AXIS_MONITORS[] = {
    { OH_GamePad_LeftTrigger_RegisterAxisInputMonitor, OH_GamePad_LeftTrigger_UnregisterAxisInputMonitor },
    { OH_GamePad_RightTrigger_RegisterAxisInputMonitor, OH_GamePad_RightTrigger_UnregisterAxisInputMonitor },
    { OH_GamePad_Dpad_RegisterAxisInputMonitor, OH_GamePad_Dpad_UnregisterAxisInputMonitor },
    { OH_GamePad_LeftThumbstick_RegisterAxisInputMonitor, OH_GamePad_LeftThumbstick_UnregisterAxisInputMonitor },
    { OH_GamePad_RightThumbstick_RegisterAxisInputMonitor, OH_GamePad_RightThumbstick_UnregisterAxisInputMonitor },
};

std::string JsonEscape(const char* value)
{
    if (value == nullptr) {
        return "";
    }

    std::string escaped;
    escaped.reserve(std::char_traits<char>::length(value));
    for (const char* cursor = value; *cursor != '\0'; ++cursor) {
        switch (*cursor) {
            case '\\':
                escaped += "\\\\";
                break;
            case '"':
                escaped += "\\\"";
                break;
            case '\n':
                escaped += "\\n";
                break;
            case '\r':
                escaped += "\\r";
                break;
            case '\t':
                escaped += "\\t";
                break;
            default:
                escaped.push_back(*cursor);
                break;
        }
    }
    return escaped;
}

std::string AxisSourceTypeToString(GamePad_AxisSourceType sourceType)
{
    switch (sourceType) {
        case DPAD:
            return "dpad";
        case LEFT_THUMBSTICK:
            return "left-thumbstick";
        case RIGHT_THUMBSTICK:
            return "right-thumbstick";
        case LEFT_TRIGGER:
            return "left-trigger";
        case RIGHT_TRIGGER:
            return "right-trigger";
        default:
            return "unknown";
    }
}

std::string DeviceChangeTypeToString(GameDevice_StatusChangedType changeType)
{
    switch (changeType) {
        case ONLINE:
            return "online";
        case OFFLINE:
            return "offline";
        default:
            return "unknown";
    }
}

void SetLastErrorCode(int32_t errorCode)
{
    std::lock_guard<std::mutex> lock(g_stateMutex);
    g_lastErrorCode = errorCode;
}

void EnqueueEvent(std::string&& eventJson)
{
    std::lock_guard<std::mutex> lock(g_queueMutex);
    if (g_eventQueue.size() >= MAX_BUFFERED_EVENT_COUNT) {
        g_eventQueue.pop_front();
    }
    g_eventQueue.push_back(std::move(eventJson));
}

void OnGameDeviceEvent(const GameDevice_DeviceEvent* deviceEvent)
{
    if (deviceEvent == nullptr) {
        return;
    }

    GameDevice_StatusChangedType changeType = OFFLINE;
    GameDevice_DeviceInfo* deviceInfo = nullptr;
    if (OH_GameDevice_DeviceEvent_GetChangedType(deviceEvent, &changeType) != GAME_CONTROLLER_SUCCESS) {
        return;
    }
    if (OH_GameDevice_DeviceEvent_GetDeviceInfo(deviceEvent, &deviceInfo) != GAME_CONTROLLER_SUCCESS || deviceInfo == nullptr) {
        return;
    }

    char* deviceId = nullptr;
    char* name = nullptr;
    GameDevice_DeviceType deviceType = UNKNOWN;
    OH_GameDevice_DeviceInfo_GetDeviceId(deviceInfo, &deviceId);
    OH_GameDevice_DeviceInfo_GetName(deviceInfo, &name);
    OH_GameDevice_DeviceInfo_GetDeviceType(deviceInfo, &deviceType);

    std::ostringstream json;
    json << "{"
         << "\"kind\":\"device-status\"," 
         << "\"change\":\"" << DeviceChangeTypeToString(changeType) << "\"," 
         << "\"deviceId\":\"" << JsonEscape(deviceId) << "\"," 
         << "\"name\":\"" << JsonEscape(name) << "\"," 
         << "\"deviceType\":" << static_cast<int32_t>(deviceType)
         << "}";
    EnqueueEvent(json.str());
    OH_GameDevice_DestroyDeviceInfo(&deviceInfo);
}

void OnGamePadButtonEvent(const GamePad_ButtonEvent* buttonEvent)
{
    if (buttonEvent == nullptr) {
        return;
    }

    char* deviceId = nullptr;
    char* codeName = nullptr;
    GamePad_Button_ActionType actionType = DOWN;
    int32_t code = 0;
    int32_t pressedCount = 0;
    int64_t actionTime = 0;

    OH_GamePad_ButtonEvent_GetDeviceId(buttonEvent, &deviceId);
    OH_GamePad_ButtonEvent_GetButtonAction(buttonEvent, &actionType);
    OH_GamePad_ButtonEvent_GetButtonCode(buttonEvent, &code);
    OH_GamePad_ButtonEvent_GetButtonCodeName(buttonEvent, &codeName);
    OH_GamePad_PressedButtons_GetCount(buttonEvent, &pressedCount);
    OH_GamePad_ButtonEvent_GetActionTime(buttonEvent, &actionTime);

    std::ostringstream pressedButtons;
    pressedButtons << "[";
    for (int32_t index = 0; index < pressedCount; ++index) {
        GamePad_PressedButton* pressedButton = nullptr;
        if (OH_GamePad_PressedButtons_GetButtonInfo(buttonEvent, index, &pressedButton) != GAME_CONTROLLER_SUCCESS ||
            pressedButton == nullptr) {
            continue;
        }

        int32_t pressedCode = 0;
        char* pressedCodeName = nullptr;
        OH_GamePad_PressedButton_GetButtonCode(pressedButton, &pressedCode);
        OH_GamePad_PressedButton_GetButtonCodeName(pressedButton, &pressedCodeName);
        if (pressedButtons.tellp() > 1) {
            pressedButtons << ",";
        }
        pressedButtons << "{"
                      << "\"code\":" << pressedCode << ","
                      << "\"codeName\":\"" << JsonEscape(pressedCodeName) << "\""
                      << "}";
        OH_GamePad_DestroyPressedButton(&pressedButton);
    }
    pressedButtons << "]";

    std::ostringstream json;
    json << "{"
         << "\"kind\":\"gamepad-button\"," 
         << "\"deviceId\":\"" << JsonEscape(deviceId) << "\"," 
         << "\"action\":\"" << (actionType == DOWN ? "down" : "up") << "\"," 
         << "\"code\":" << code << ","
         << "\"codeName\":\"" << JsonEscape(codeName) << "\"," 
         << "\"actionTime\":" << actionTime << ","
         << "\"pressedButtons\":" << pressedButtons.str()
         << "}";
    EnqueueEvent(json.str());
}

void OnGamePadAxisEvent(const GamePad_AxisEvent* axisEvent)
{
    if (axisEvent == nullptr) {
        return;
    }

    char* deviceId = nullptr;
    GamePad_AxisSourceType sourceType = DPAD;
    double x = 0;
    double y = 0;
    double z = 0;
    double rz = 0;
    double hatX = 0;
    double hatY = 0;
    double brake = 0;
    double gas = 0;
    int64_t actionTime = 0;

    OH_GamePad_AxisEvent_GetDeviceId(axisEvent, &deviceId);
    OH_GamePad_AxisEvent_GetAxisSourceType(axisEvent, &sourceType);
    OH_GamePad_AxisEvent_GetXAxisValue(axisEvent, &x);
    OH_GamePad_AxisEvent_GetYAxisValue(axisEvent, &y);
    OH_GamePad_AxisEvent_GetZAxisValue(axisEvent, &z);
    OH_GamePad_AxisEvent_GetRZAxisValue(axisEvent, &rz);
    OH_GamePad_AxisEvent_GetHatXAxisValue(axisEvent, &hatX);
    OH_GamePad_AxisEvent_GetHatYAxisValue(axisEvent, &hatY);
    OH_GamePad_AxisEvent_GetBrakeAxisValue(axisEvent, &brake);
    OH_GamePad_AxisEvent_GetGasAxisValue(axisEvent, &gas);
    OH_GamePad_AxisEvent_GetActionTime(axisEvent, &actionTime);

    std::ostringstream json;
    json << "{"
         << "\"kind\":\"gamepad-axis\"," 
         << "\"deviceId\":\"" << JsonEscape(deviceId) << "\"," 
         << "\"source\":\"" << AxisSourceTypeToString(sourceType) << "\"," 
         << "\"x\":" << x << ","
         << "\"y\":" << y << ","
         << "\"z\":" << z << ","
         << "\"rz\":" << rz << ","
         << "\"hatX\":" << hatX << ","
         << "\"hatY\":" << hatY << ","
         << "\"brake\":" << brake << ","
         << "\"gas\":" << gas << ","
         << "\"actionTime\":" << actionTime
         << "}";
    EnqueueEvent(json.str());
}

int32_t StartNativeInputMonitoringImpl()
{
    std::lock_guard<std::mutex> lock(g_stateMutex);
    if (g_monitoringStarted) {
        return GAME_CONTROLLER_SUCCESS;
    }

    GameController_ErrorCode result = OH_GameDevice_RegisterDeviceMonitor(OnGameDeviceEvent);
    if (result != GAME_CONTROLLER_SUCCESS) {
        g_lastErrorCode = result;
        return result;
    }

    for (const auto& monitor : BUTTON_MONITORS) {
        result = monitor.registerFn(OnGamePadButtonEvent);
        if (result != GAME_CONTROLLER_SUCCESS) {
            goto rollback;
        }
    }
    for (const auto& monitor : AXIS_MONITORS) {
        result = monitor.registerFn(OnGamePadAxisEvent);
        if (result != GAME_CONTROLLER_SUCCESS) {
            goto rollback;
        }
    }

    g_monitoringStarted = true;
    g_lastErrorCode = GAME_CONTROLLER_SUCCESS;
    return GAME_CONTROLLER_SUCCESS;

rollback:
    for (const auto& monitor : AXIS_MONITORS) {
        monitor.unregisterFn();
    }
    for (const auto& monitor : BUTTON_MONITORS) {
        monitor.unregisterFn();
    }
    OH_GameDevice_UnregisterDeviceMonitor();
    g_monitoringStarted = false;
    g_lastErrorCode = result;
    return result;
}

int32_t StopNativeInputMonitoringImpl()
{
    std::lock_guard<std::mutex> lock(g_stateMutex);
    for (const auto& monitor : AXIS_MONITORS) {
        monitor.unregisterFn();
    }
    for (const auto& monitor : BUTTON_MONITORS) {
        monitor.unregisterFn();
    }
    OH_GameDevice_UnregisterDeviceMonitor();
    g_monitoringStarted = false;
    g_lastErrorCode = GAME_CONTROLLER_SUCCESS;
    return GAME_CONTROLLER_SUCCESS;
}

std::string PollNativeInputEventsJsonImpl(int32_t maxCount)
{
    const int32_t boundedMaxCount = std::max(1, maxCount);
    std::lock_guard<std::mutex> lock(g_queueMutex);

    std::ostringstream json;
    json << "[";
    int32_t emittedCount = 0;
    while (!g_eventQueue.empty() && emittedCount < boundedMaxCount) {
        if (emittedCount > 0) {
            json << ",";
        }
        json << g_eventQueue.front();
        g_eventQueue.pop_front();
        emittedCount++;
    }
    json << "]";
    return json.str();
}

std::string GetConnectedGamepadDevicesJsonImpl()
{
    GameDevice_AllDeviceInfos* allDeviceInfos = nullptr;
    GameController_ErrorCode result = OH_GameDevice_GetAllDeviceInfos(&allDeviceInfos);
    if (result != GAME_CONTROLLER_SUCCESS || allDeviceInfos == nullptr) {
        SetLastErrorCode(result);
        return "[]";
    }

    int32_t count = 0;
    OH_GameDevice_AllDeviceInfos_GetCount(allDeviceInfos, &count);
    std::ostringstream json;
    json << "[";
    bool first = true;
    for (int32_t index = 0; index < count; ++index) {
        GameDevice_DeviceInfo* deviceInfo = nullptr;
        if (OH_GameDevice_AllDeviceInfos_GetDeviceInfo(allDeviceInfos, index, &deviceInfo) != GAME_CONTROLLER_SUCCESS ||
            deviceInfo == nullptr) {
            continue;
        }

        GameDevice_DeviceType deviceType = UNKNOWN;
        OH_GameDevice_DeviceInfo_GetDeviceType(deviceInfo, &deviceType);
        if (deviceType != GAME_PAD) {
            OH_GameDevice_DestroyDeviceInfo(&deviceInfo);
            continue;
        }

        char* deviceId = nullptr;
        char* name = nullptr;
        char* physicalAddress = nullptr;
        int32_t product = 0;
        int32_t version = 0;
        OH_GameDevice_DeviceInfo_GetDeviceId(deviceInfo, &deviceId);
        OH_GameDevice_DeviceInfo_GetName(deviceInfo, &name);
        OH_GameDevice_DeviceInfo_GetPhysicalAddress(deviceInfo, &physicalAddress);
        OH_GameDevice_DeviceInfo_GetProduct(deviceInfo, &product);
        OH_GameDevice_DeviceInfo_GetVersion(deviceInfo, &version);

        if (!first) {
            json << ",";
        }
        first = false;
        json << "{"
             << "\"deviceId\":\"" << JsonEscape(deviceId) << "\"," 
             << "\"name\":\"" << JsonEscape(name) << "\"," 
             << "\"physicalAddress\":\"" << JsonEscape(physicalAddress) << "\"," 
             << "\"product\":" << product << ","
             << "\"version\":" << version
             << "}";
        OH_GameDevice_DestroyDeviceInfo(&deviceInfo);
    }
    json << "]";
    OH_GameDevice_DestroyAllDeviceInfos(&allDeviceInfos);
    return json.str();
}

std::string GetNativeInputBridgeStateJsonImpl()
{
    std::lock_guard<std::mutex> stateLock(g_stateMutex);
    std::lock_guard<std::mutex> queueLock(g_queueMutex);
    std::ostringstream json;
    json << "{"
         << "\"monitoringStarted\":" << (g_monitoringStarted ? "true" : "false") << ","
         << "\"queuedEventCount\":" << g_eventQueue.size() << ","
         << "\"lastErrorCode\":" << g_lastErrorCode
         << "}";
    return json.str();
}

napi_value CreateUtf8String(napi_env env, const std::string& value)
{
    napi_value result = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.length(), &result);
    return result;
}

napi_value CreateInt32Value(napi_env env, int32_t value)
{
    napi_value result = nullptr;
    napi_create_int32(env, value, &result);
    return result;
}

int32_t GetOptionalInt32Argument(napi_env env, napi_callback_info info, int32_t fallback)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc == 0 || args[0] == nullptr) {
        return fallback;
    }

    napi_valuetype valueType = napi_undefined;
    napi_typeof(env, args[0], &valueType);
    if (valueType != napi_number) {
        return fallback;
    }

    int32_t parsedValue = fallback;
    napi_get_value_int32(env, args[0], &parsedValue);
    return parsedValue;
}

static napi_value Add(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    double value0 = 0;
    double value1 = 0;
    napi_get_value_double(env, args[0], &value0);
    napi_get_value_double(env, args[1], &value1);

    napi_value sum = nullptr;
    napi_create_double(env, value0 + value1, &sum);
    return sum;
}

static napi_value GetNativeInputBridgeVersion(napi_env env, napi_callback_info info)
{
    (void)info;
    return CreateUtf8String(env, "game-controller-bridge-v1");
}

static napi_value StartNativeInputMonitoring(napi_env env, napi_callback_info info)
{
    (void)info;
    return CreateInt32Value(env, StartNativeInputMonitoringImpl());
}

static napi_value StopNativeInputMonitoring(napi_env env, napi_callback_info info)
{
    (void)info;
    return CreateInt32Value(env, StopNativeInputMonitoringImpl());
}

static napi_value PollNativeInputEvents(napi_env env, napi_callback_info info)
{
    return CreateUtf8String(env, PollNativeInputEventsJsonImpl(GetOptionalInt32Argument(env, info, DEFAULT_POLL_EVENT_COUNT)));
}

static napi_value GetConnectedGamepadDevicesJson(napi_env env, napi_callback_info info)
{
    (void)info;
    return CreateUtf8String(env, GetConnectedGamepadDevicesJsonImpl());
}

static napi_value GetNativeInputBridgeStateJson(napi_env env, napi_callback_info info)
{
    (void)info;
    return CreateUtf8String(env, GetNativeInputBridgeStateJsonImpl());
}

} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "add", nullptr, Add, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getNativeInputBridgeVersion", nullptr, GetNativeInputBridgeVersion, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "startNativeInputMonitoring", nullptr, StartNativeInputMonitoring, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopNativeInputMonitoring", nullptr, StopNativeInputMonitoring, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "pollNativeInputEvents", nullptr, PollNativeInputEvents, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getConnectedGamepadDevicesJson", nullptr, GetConnectedGamepadDevicesJson, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getNativeInputBridgeStateJson", nullptr, GetNativeInputBridgeStateJson, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void)
{
    napi_module_register(&demoModule);
}
