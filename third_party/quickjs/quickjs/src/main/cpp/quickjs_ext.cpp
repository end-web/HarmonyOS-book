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

#include <cstring>

#include "native_value.h"
#include "quickjs_headers.h"

struct JSObjectInfo {
    JSContext* context = nullptr;
    JSFinalizer finalizer = nullptr;
    void* data = nullptr;
    void* hint = nullptr;
};

JSClassID g_baseClassId = 1;

void AddIntrinsicExternal(JSContext* context)
{
    const char* className = "External";
    JSValue global = JS_GetGlobalObject(context);
    JSValue external = JS_NewCFunction2(
        context,
        [](JSContext* ctx, JSValueConst newTarget, int argc, JSValueConst* argv) {
            JSValue proto = JS_GetPropertyStr(ctx, newTarget, "prototype");
            JSValue result = JS_NewObjectProtoClass(ctx, proto, GetBaseClassID());
            JS_FreeValue(ctx, proto);
            return result;
        },
        className, strlen(className), JS_CFUNC_constructor, 0);
    JSValue proto = JS_NewObject(context);

    JS_DefinePropertyValueStr(context, external, "prototype", JS_DupValue(context, proto), 0);
    JS_DefinePropertyValueStr(
        context, proto, "constructor", JS_DupValue(context, external), JS_PROP_WRITABLE | JS_PROP_CONFIGURABLE);

    JS_SetPropertyStr(context, global, "External", external);
    JS_FreeValue(context, proto);
    JS_FreeValue(context, global);
}

JSClassID GetBaseClassID()
{
    return g_baseClassId;
}

JSValue JS_NewExternal(JSContext* context, void* value, JSFinalizer finalizer, void* hint)
{
    JSValue global = JS_GetGlobalObject(context);
    JSValue external = JS_GetPropertyStr(context, global, "External");
    JSValue result = JS_CallConstructor(context, external, 0, nullptr);

    auto info = new JSObjectInfo();
    if (info != nullptr) {
        info->context = context;
        info->finalizer = finalizer;
        info->data = value;
        info->hint = hint;
        JS_SetOpaque(result, info);
    }

    JS_FreeValue(context, external);
    JS_FreeValue(context, global);
    return result;
}

void* JS_ExternalToNativeObject(JSContext* context, JSValue value)
{
    auto* info = reinterpret_cast<JSObjectInfo*>(JS_GetOpaque(value, GetBaseClassID()));
    return (info != nullptr) ? info->data : nullptr;
}

bool JS_IsExternal(JSContext* context, JSValue value)
{
    bool result = false;
    JSValue constructor = JS_GetPropertyStr(context, value, "constructor");
    JSValue name = JS_GetPropertyStr(context, constructor, "name");
    const char* cName = JS_ToCString(context, name);
    result = !strcmp("External", cName ? cName : "");
    JS_FreeCString(context, cName);
    JS_FreeValue(context, name);
    JS_FreeValue(context, constructor);
    return result;
}

void AddIntrinsicBaseClass(JSContext* context)
{
    const JSClassDef baseClassDef = {
        .class_name = "BaseClass",
        .finalizer =
            [](JSRuntime* rt, JSValue val) {
                auto* info = reinterpret_cast<JSObjectInfo*>(JS_GetOpaque(val, GetBaseClassID()));
                if (info != nullptr) {
                    info->finalizer(info->context, info->data, info->hint);
                    delete info;
                }
            },
    };

    JS_NewClassID(&g_baseClassId);
    JS_NewClass(JS_GetRuntime(context), g_baseClassId, &baseClassDef);
}

void JS_AddFinalizer(JSContext* context, JSValue value, void* pointer, JSFinalizer finalizer, void* hint)
{
    auto* info = reinterpret_cast<JSObjectInfo*>(JS_GetOpaque(value, GetBaseClassID()));
    if (info == nullptr) {
        info = new JSObjectInfo();
        if (info != nullptr) {
            info->context = context;
            info->finalizer = finalizer;
            info->data = pointer;
            info->hint = hint;
        }
    }

    if (info) {
        JS_SetOpaque(value, info);
    }
}

void JS_FreeFinalizer(JSValue value)
{
    auto* info = reinterpret_cast<JSObjectInfo*>(JS_GetOpaque(value, GetBaseClassID()));
    if (info != nullptr) {
        delete info;
        info = nullptr;
        JS_SetOpaque(value, info);
    }
}

void JS_SetNativePointer(JSContext* context, JSValue value, void* pointer, JSFinalizer finalizer, void* hint)
{
    auto* info = reinterpret_cast<JSObjectInfo*>(JS_GetOpaque(value, GetBaseClassID()));
    if (info == nullptr) {
        info = new JSObjectInfo();
        if (info != nullptr) {
            info->context = context;
            info->finalizer = finalizer;
            info->data = pointer;
            info->hint = hint;
        }
    } else if (pointer == nullptr) {
        delete info;
        info = nullptr;
    }

    JS_SetOpaque(value, info);
}

void* JS_GetNativePointer(JSContext* context, JSValue value)
{
    auto* info = reinterpret_cast<JSObjectInfo*>(JS_GetOpaque(value, GetBaseClassID()));
    return (info != nullptr) ? info->data : nullptr;
}

bool JS_IsPromise(JSContext* context, JSValue value)
{
    bool result = false;
    JSValue constructor = JS_GetPropertyStr(context, value, "constructor");
    JSValue name = JS_GetPropertyStr(context, constructor, "name");
    const char* cName = JS_ToCString(context, name);
    result = !strcmp("Promise", cName ? cName : "");
    JS_FreeCString(context, cName);
    JS_FreeValue(context, name);
    JS_FreeValue(context, constructor);
    return result;
}

bool JS_IsMapIterator(JSContext* context, JSValue value)
{
    return false;
}

bool JS_IsSetIterator(JSContext* context, JSValue value)
{
    return false;
}

bool JS_IsGeneratorObject(JSContext* context, JSValue value)
{
    return false;
}

bool JS_IsModuleNamespaceObject(JSContext* context, JSValue value)
{
    return false;
}

bool JS_IsProxy(JSContext* context, JSValue value)
{
    return false;
}

bool JS_IsRegExp(JSContext* context, JSValue value)
{
    return false;
}

bool JS_IsNumberObject(JSContext* context, JSValue value)
{
    return false;
}

bool JS_IsMap(JSContext* context, JSValue value)
{
    return false;
}

bool JS_IsSet(JSContext* context, JSValue value)
{
    return false;
}

bool JS_IsKeyObject(JSContext* context, JSValue value)
{
    return false;
}

bool JS_IsArrayBuffer(JSContext* context, JSValue value)
{
    bool result = false;
    JSValue constructor = JS_GetPropertyStr(context, value, "constructor");
    JSValue name = JS_GetPropertyStr(context, constructor, "name");
    const char* cName = JS_ToCString(context, name);
    result = !strcmp("ArrayBuffer", cName ? cName : "");
    JS_FreeCString(context, cName);
    JS_FreeValue(context, name);
    JS_FreeValue(context, constructor);

    JSAtom key = JS_NewAtom(context, "napi_buffer");
    bool hasPro = JS_HasProperty(context, value, key);
    JS_FreeAtom(context, key);
    return (result && !hasPro);
}

bool JS_IsBuffer(JSContext* context, JSValue value)
{
    bool result = false;
    JSValue constructor = JS_GetPropertyStr(context, value, "constructor");
    JSValue name = JS_GetPropertyStr(context, constructor, "name");
    const char* cName = JS_ToCString(context, name);
    result = !strcmp("ArrayBuffer", cName ? cName : "");
    JS_FreeValue(context, name);
    JS_FreeCString(context, cName);
    JS_FreeValue(context, constructor);

    JSAtom key = JS_NewAtom(context, "napi_buffer");
    bool hasPro = JS_HasProperty(context, value, key);
    JS_FreeAtom(context, key);

    return (result && hasPro);
}

bool JS_IsDate(JSContext* context, JSValue value)
{
    bool result = false;
    JSValue constructor = JS_GetPropertyStr(context, value, "constructor");
    JSValue name = JS_GetPropertyStr(context, constructor, "name");
    const char* cName = JS_ToCString(context, name);
    result = !strcmp("Date", cName ? cName : "");
    JS_FreeCString(context, cName);
    JS_FreeValue(context, name);
    JS_FreeValue(context, constructor);
    return result;
}

bool JS_IsDataView(JSContext* context, JSValue value)
{
    bool result = false;
    JSValue constructor = JS_GetPropertyStr(context, value, "constructor");
    JSValue name = JS_GetPropertyStr(context, constructor, "name");
    const char* cName = JS_ToCString(context, name);
    result = !strcmp("DataView", cName ? cName : "");
    JS_FreeCString(context, cName);
    JS_FreeValue(context, name);
    JS_FreeValue(context, constructor);
    return result;
}

bool JS_IsTypedArray(JSContext* context, JSValue value)
{
    bool result = false;
    JSValue constructor = JS_GetPropertyStr(context, value, "constructor");
    JSValue name = JS_GetPropertyStr(context, constructor, "name");
    const char* cName = JS_ToCString(context, name);
    result = !strcmp("Uint8ClampedArray", cName ? cName : "") || !strcmp("Int8Array", cName ? cName : "") ||
             !strcmp("Uint8Array", cName ? cName : "") || !strcmp("Int16Array", cName ? cName : "") ||
             !strcmp("Uint16Array", cName ? cName : "") || !strcmp("Int32Array", cName ? cName : "") ||
             !strcmp("Uint32Array", cName ? cName : "") || !strcmp("BigInt64Array", cName ? cName : "") ||
             !strcmp("BigUint64Array", cName ? cName : "") || !strcmp("Float32Array", cName ? cName : "") ||
             !strcmp("Float64Array", cName ? cName : "");

    JS_FreeCString(context, cName);
    JS_FreeValue(context, name);
    JS_FreeValue(context, constructor);
    return result;
}

bool JS_StrictEquals(JSContext* context, JSValue v1, JSValue v2)
{
    JSValue thisVar = JS_UNDEFINED;
    JSValue argv[2] = { v1, v2 };
    const char script[] = "(v1, v2) => v1 === v2;";
    JSValue func = JS_Eval(context, script, strlen(script), "<input>", JS_EVAL_TYPE_GLOBAL);
    JSValue ret = JS_Call(context, func, thisVar, 2, (JSValue*)&argv);
    bool result = JS_ToBool(context, ret);
    JS_FreeValue(context, func);
    JS_FreeValue(context, ret);
    //js_std_loop(context);

    return result;
}

bool JS_LooseEquals(JSContext* context, JSValue v1, JSValue v2)
{
    JSValue thisVar = JS_UNDEFINED;
    JSValue argv[2] = { v1, v2 };
    const char script[] = "(v1, v2) => v1 == v2;";
    JSValue func = JS_Eval(context, script, strlen(script), "<input>", JS_EVAL_TYPE_GLOBAL);
    JSValue ret = JS_Call(context, func, thisVar, 2, (JSValue*)&argv);
    bool result = JS_ToBool(context, ret);
    JS_FreeValue(context, func);
    JS_FreeValue(context, ret);

    return result;
}

JSValue JS_StrictDate(JSContext* context, double time)
{
    JSValue thisVar = JS_UNDEFINED;
    JSValue v1 = JS_NewInt64(context, (int64_t)time);
    if (JS_IsException(v1)) {
        JS_FreeValue(context, v1);
        return JS_GetException(context);
    }

    JSValue argv[1] = { v1 };
    const char script[] = " (v1) => new Date(v1); ";
    JSValue func = JS_Eval(context, script, strlen(script), "<input>", JS_EVAL_TYPE_GLOBAL);
    JSValue ret = JS_Call(context, func, thisVar, 1, (JSValue*)&argv);
    JS_FreeValue(context, func);

    if (JS_IsException(ret)) {
        JS_FreeValue(context, ret);
        return JS_GetException(context);
    }
    return ret;
}

JSValue JS_CreateBigIntWords(JSContext* context, int signBit, size_t wordCount, const uint64_t* words)
{
    JSValue thisVar = JS_UNDEFINED;
    constexpr size_t Count = 20;
    constexpr size_t Two = 2;
    if (wordCount <= 0 || wordCount > Count || words == nullptr) {
        //HILOG_INFO("%{public}s called. Params is invalid or the BigInt too big.", __func__);
        return JS_EXCEPTION;
    }

    JSValue signValue = JS_NewInt32(context, (signBit % Two));
    if (JS_IsException(signValue)) {
        //HILOG_INFO("%{public}s called. Invoke JS_NewInt32 error.", __func__);
        return JS_EXCEPTION;
    }

    JSValue wordsValue = JS_NewArray(context);
    if (JS_IsException(wordsValue)) {
        //HILOG_INFO("%{public}s called. Invoke JS_NewArray error.", __func__);
        return JS_EXCEPTION;
    }

    for (size_t i = 0; i < wordCount; i++) {
        // shift 32 bits right to get high bit
        JSValue idxValueHigh = JS_NewUint32(context, (uint32_t)(words[i] >> 32));
        // gets lower 32 bits
        JSValue idxValueLow = JS_NewUint32(context, (uint32_t)(words[i] & 0xFFFFFFFF));
        if (!(JS_IsException(idxValueHigh)) && !(JS_IsException(idxValueLow))) {
            JS_SetPropertyUint32(context, wordsValue, (i * Two), idxValueHigh);
            JS_SetPropertyUint32(context, wordsValue, (i * Two + 1), idxValueLow);
            JS_FreeValue(context, idxValueHigh);
            JS_FreeValue(context, idxValueLow);
        }
    }

    JSValue argv[2] = { signValue, wordsValue };
    const char script[] = "(sign, word) => { "
                          " const max_v = BigInt(2 ** 64 - 1);"
                          " var bg = 0n;"
                          "  for (var i=0; i<word.length/2; i++) {"
                          "      bg = bg + (BigInt(word[i*2]) * 2n**32n + BigInt(word[i*2 +1])) * (max_v ** BigInt(i));"
                          "  }"
                          "  if (sign  !=  0) {"
                          "      bg = bg * (-1n);"
                          "  }"
                          "  return bg;"
                          "};";

    JSValue func = JS_Eval(context, script, strlen(script), "<input>", JS_EVAL_TYPE_GLOBAL);
    JSValue ret = JS_Call(context, func, thisVar, 2, (JSValue*)&argv);
    JS_FreeValue(context, func);
    JS_FreeValue(context, signValue);
    JS_FreeValue(context, wordsValue);
    return ret;
}

bool ParseBigIntWordsInternal(JSContext* context, JSValue value, int* signBit, size_t* wordCount, uint64_t* words)
{
    int cntValue = 0;
    if (wordCount == nullptr) {
        return false;
    }

    JSValue jsValue = JS_GetPropertyStr(context, value, "count");
    if (!JS_IsException(jsValue)) {
        JS_ToInt32(context, &cntValue, jsValue);
        JS_FreeValue(context, jsValue);
    } else {
        return false;
    }

    if (signBit == nullptr && words == nullptr) {
        *wordCount = cntValue;
        return true;
    } else if (signBit != nullptr && words != nullptr) {
        cntValue = (cntValue > *wordCount) ? *wordCount : cntValue;
        jsValue = JS_GetPropertyStr(context, value, "sign");
        if (!JS_IsException(jsValue)) {
            int sigValue = 0;
            JS_ToInt32(context, &sigValue, jsValue);
            *signBit = sigValue;
            JS_FreeValue(context, jsValue);
        }

        jsValue = JS_GetPropertyStr(context, value, "words");
        if (!JS_IsException(jsValue)) {
            JSValue element;
            int64_t cValue = 0;
            for (uint32_t i = 0; i < (uint32_t)cntValue; i++) {
                element = JS_GetPropertyUint32(context, jsValue, i);
                JS_ToInt64Ext(context, &cValue, element);
                JS_FreeValue(context, element);
                words[i] = (uint64_t)cValue;
            }
            JS_FreeValue(context, jsValue);
            *wordCount = cntValue;
            return true;
        }
    }
    return false;
}

bool JS_GetBigIntWords(JSContext* context, JSValue value, int* signBit, size_t* wordCount, uint64_t* words)
{
    //HILOG_INFO("%{public}s called. ", __func__);

    bool rev = false;
    JSValue thisVar = JS_UNDEFINED;
    if (wordCount == nullptr) {
        //HILOG_INFO("%{public}s called. Params are invalid.", __func__);
        return false;
    }

    const char script[] = "(big) => {"
                          "const max_v = BigInt(2 ** 64 - 1);"
                          "var rev = {};"
                          "rev.sign = 0;"
                          "rev.count = 0;"
                          "rev.words = [];"
                          "if (big < 0n) {"
                          "	rev.sign = 1;"
                          "	big = big * (-1n);"
                          "}"
                          "while (big >= max_v) {"
                          "	rev.words[rev.count] = big % max_v;"
                          "	big = big / max_v;"
                          "	rev.count++;"
                          "}"
                          "rev.words[rev.count] = big % max_v;"
                          "rev.count++;"
                          "return rev;"
                          "}";

    JSValue func = JS_Eval(context, script, strlen(script), "<input>", JS_EVAL_TYPE_GLOBAL);
    JSValue bigObj = JS_Call(context, func, thisVar, 1, &value);
    if (!JS_IsException(bigObj)) {
        if (JS_IsObject(bigObj)) {
            rev = ParseBigIntWordsInternal(context, bigObj, signBit, wordCount, words);
        } else {
            //HILOG_INFO("%{public}s called. JSValue is not Object. ", __func__);
        }
    }

    JS_FreeValue(context, func);
    JS_FreeValue(context, bigObj);
    return rev;
}

JSValue JS_Freeze(JSContext* context, JSValue value)
{
    JSValue thisVar = JS_UNDEFINED;
    const char script[] = "(obj) => Object.freeze(obj);";
    JSValue func = JS_Eval(context, script, strlen(script), "<input>", JS_EVAL_TYPE_GLOBAL);
    JSValue ret = JS_Call(context, func, thisVar, 1, &value);
    JS_FreeValue(context, func);
    JS_FreeValue(context, ret);
    return JS_DupValue(context, value);
}

JSValue JS_Seal(JSContext* context, JSValue value)
{
    JSValue thisVar = JS_UNDEFINED;
    const char script[] = "(obj) => Object.seal(obj);";
    JSValue func = JS_Eval(context, script, strlen(script), "<input>", JS_EVAL_TYPE_GLOBAL);
    JSValue ret = JS_Call(context, func, thisVar, 1, &value);
    JS_FreeValue(context, func);
    JS_FreeValue(context, ret);
    return JS_DupValue(context, value);
}

struct JS_BigFloatExt {
    JSRefCountHeader header;
    bf_t num;
};

bool JS_ToInt64WithBigInt(JSContext* context, JSValueConst value, int64_t* pres, bool* lossless)
{
    if (pres == nullptr || lossless == nullptr) {
        //HILOG_INFO("%{public}s called. Params are invalid.", __func__);
        return false;
    }

    bool rev = false;
    JSValue val = JS_DupValue(context, value);
    JS_BigFloatExt* p = (JS_BigFloatExt*)JS_VALUE_GET_PTR(val);
    if (p) {
        int opFlag = bf_get_int64(pres, &p->num, 0);
        if (lossless != nullptr) {
            *lossless = (opFlag == 0);
        }
        rev = true;
    }
    JS_FreeValue(context, val);
    return rev;
}

bool JS_ToUInt64WithBigInt(JSContext* context, JSValueConst value, uint64_t* pres, bool* lossless)
{
    if (pres == nullptr || lossless == nullptr) {
        //HILOG_INFO("%{public}s called. Params are invalid.", __func__);
        return false;
    }

    bool rev = false;
    JSValue val = JS_DupValue(context, value);
    JS_BigFloatExt* p = (JS_BigFloatExt*)JS_VALUE_GET_PTR(val);
    if (p) {
        int opFlag = bf_get_uint64(pres, &p->num);
        if (lossless != nullptr) {
            *lossless = (opFlag == 0);
        }
        rev = true;
    }
    JS_FreeValue(context, val);
    return rev;
}
