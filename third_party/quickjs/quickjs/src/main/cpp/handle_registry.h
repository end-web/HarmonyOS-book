/*
 * Copyright (c) 2021 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef QUICKJS_HANDLE_REGISTRY_H
#define QUICKJS_HANDLE_REGISTRY_H

#include <cstdint>
#include <mutex>
#include <unordered_map>
#include "quickjs_headers.h"

// Engine entry: holds both runtime and context for cleanup
struct EngineEntry {
    JSRuntime* runtime;
    JSContext* context;
};

// Engine Registry: maps int64_t handle -> {JSRuntime*, JSContext*}
class EngineRegistry {
public:
    static int64_t Register(JSRuntime* runtime, JSContext* context) {
        std::lock_guard<std::mutex> lock(mutex_);
        int64_t handle = nextHandle_++;
        engines_[handle] = {runtime, context};
        return handle;
    }

    static JSContext* GetContext(int64_t handle) {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = engines_.find(handle);
        if (it != engines_.end()) {
            return it->second.context;
        }
        return nullptr;
    }

    static JSRuntime* GetRuntime(int64_t handle) {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = engines_.find(handle);
        if (it != engines_.end()) {
            return it->second.runtime;
        }
        return nullptr;
    }

    static void Unregister(int64_t handle) {
        std::lock_guard<std::mutex> lock(mutex_);
        engines_.erase(handle);
    }

private:
    static std::mutex mutex_;
    static std::unordered_map<int64_t, EngineEntry> engines_;
    static int64_t nextHandle_;
};

// Value Registry: maps int64_t handle -> {JSValue, JSContext*}
struct ValueEntry {
    JSValue value;
    JSContext* context;
};

class ValueRegistry {
public:
    static int64_t Register(JSValue value, JSContext* context) {
        std::lock_guard<std::mutex> lock(mutex_);
        int64_t handle = nextHandle_++;
        values_[handle] = {value, context};
        return handle;
    }

    static ValueEntry Get(int64_t handle) {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = values_.find(handle);
        if (it != values_.end()) {
            return it->second;
        }
        return {JS_UNDEFINED, nullptr};
    }

    static void Unregister(int64_t handle) {
        std::lock_guard<std::mutex> lock(mutex_);
        values_.erase(handle);
    }

private:
    static std::mutex mutex_;
    static std::unordered_map<int64_t, ValueEntry> values_;
    static int64_t nextHandle_;
};

#endif /* QUICKJS_HANDLE_REGISTRY_H */
