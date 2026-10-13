#include "Cangjie.h"
#include <napi/native_api.h>
#include <hilog/log.h>
#include <dlfcn.h>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace {
constexpr size_t kMaxInput = 16 * 1024 * 1024;
constexpr size_t kMaxCharacters = 4 * 1024 * 1024;
constexpr size_t kMaxOutput = 32 * 1024 * 1024;
std::mutex coreMutex;
bool initialized = false;
CJTaskFunc tokenizeFunction = nullptr;
CJTaskFunc freeFunction = nullptr;

bool EnsureRuntime(std::string& error)
{
    if (initialized) { return true; }
    RuntimeParam settings {};
    settings.heapParam.heapSize = 192 * 1024;
    settings.logParam.logLevel = RTLOG_ERROR;
    settings.coParam.processorNum = 2;
    if (InitCJRuntime(&settings) != E_OK) {
        error = "Cangjie runtime initialization failed";
        return false;
    }
    Dl_info location {};
    if (!dladdr(reinterpret_cast<void*>(&EnsureRuntime), &location) || !location.dli_fname) {
        error = "Cannot locate rulecore native library";
        return false;
    }
    const std::string current(location.dli_fname);
    const auto slash = current.find_last_of('/');
    const std::string library = current.substr(0, slash + 1) + "librulecore_cj.so";
    if (LoadCJLibraryWithInit(library.c_str()) != E_OK) {
        error = "Cangjie rulecore library initialization failed";
        return false;
    }
    tokenizeFunction = reinterpret_cast<CJTaskFunc>(FindCJSymbol(library.c_str(), "rulecore_tokenize"));
    freeFunction = reinterpret_cast<CJTaskFunc>(FindCJSymbol(library.c_str(), "rulecore_free"));
    if (!tokenizeFunction || !freeFunction) {
        error = "Cangjie rulecore C ABI symbols are missing";
        return false;
    }
    initialized = true;
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xD003F00, "NativeRuleCore", "Cangjie 1.2.0 tokenizer initialized (C ABI)");
    return true;
}

void* Invoke(CJTaskFunc function, void* input, std::string& error)
{
    CJThreadHandle handle = RunCJTask(function, input);
    if (!handle) {
        error = "Cannot schedule Cangjie rulecore task";
        return nullptr;
    }
    void* output = nullptr;
    const int status = GetTaskRet(handle, &output);
    ReleaseHandle(handle);
    if (status != 0) { error = "Cangjie rulecore task failed"; }
    return output;
}

napi_value Fail(napi_env env, const char* message)
{
    napi_throw_error(env, "NATIVE_RULECORE", message);
    return nullptr;
}

napi_value TokenizeHtml(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argument = nullptr;
    if (napi_get_cb_info(env, info, &argc, &argument, nullptr, nullptr) != napi_ok || argc != 1) {
        return Fail(env, "tokenizeHtml expects one HTML string");
    }
    napi_valuetype type;
    if (napi_typeof(env, argument, &type) != napi_ok || type != napi_string) {
        return Fail(env, "tokenizeHtml expects a string");
    }
    size_t length = 0;
    size_t characters = 0;
    if (napi_get_value_string_utf16(env, argument, nullptr, 0, &characters) != napi_ok || characters > kMaxCharacters) {
        return Fail(env, "HTML exceeds the 4 Mi UTF-16 character limit");
    }
    if (napi_get_value_string_utf8(env, argument, nullptr, 0, &length) != napi_ok || length > kMaxInput) {
        return Fail(env, "HTML exceeds the 16 MiB UTF-8 input limit");
    }
    std::vector<char> input(length + 1, 0);
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, argument, input.data(), input.size(), &copied) != napi_ok || copied != length ||
        std::memchr(input.data(), 0, length) != nullptr) {
        return Fail(env, "HTML contains an unsupported NUL character");
    }
    // One fixed lexer operation at a time bounds peak allocation across taskpool workers.
    std::lock_guard<std::mutex> guard(coreMutex);
    std::string error;
    if (!EnsureRuntime(error)) { return Fail(env, error.c_str()); }
    char* output = static_cast<char*>(Invoke(tokenizeFunction, input.data(), error));
    if (!output) { return Fail(env, error.empty() ? "Cangjie rulecore returned no output" : error.c_str()); }
    const size_t outputLength = strnlen(output, kMaxOutput + 1);
    napi_value result = nullptr;
    const napi_status status = outputLength <= kMaxOutput
        ? napi_create_string_utf8(env, output, outputLength, &result) : napi_invalid_arg;
    Invoke(freeFunction, output, error);
    if (status != napi_ok) { return Fail(env, "Cangjie rulecore output limit exceeded"); }
    if (!error.empty()) { return Fail(env, error.c_str()); }
    return result;
}

napi_value Register(napi_env env, napi_value exports)
{
    napi_property_descriptor properties[] = {
        { "tokenizeHtml", nullptr, TokenizeHtml, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    if (napi_define_properties(env, exports, 1, properties) != napi_ok) { return nullptr; }
    return exports;
}

napi_module module = {1, 0, nullptr, Register, "native_rulecore", nullptr, {0}};
}

extern "C" __attribute__((constructor)) void RegisterNativeRuleCore()
{
    napi_module_register(&module);
}
