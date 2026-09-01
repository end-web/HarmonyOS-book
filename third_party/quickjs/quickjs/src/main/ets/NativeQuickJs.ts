/*
 * Copyright (c) 2026 legado-harmony contributors
 * SPDX-License-Identifier: MIT
 */

import type { QuickJsNativeApi } from 'libquickjs.so';

// The native module registers its object dynamically with napi_define_properties.
// DevEco cannot infer that object as a default export from Index.d.ts, but the
// runtime import below is the same import that this library has always used.
// @ts-ignore Native default export is supplied by the Harmony N-API loader.
import nativeQuickJs from 'libquickjs.so';

const qjs = nativeQuickJs as unknown as QuickJsNativeApi;

export default qjs;
