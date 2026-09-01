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
 *
 * Modified by the legado-harmony project in 2026 for QuickJS runtime integration.
 */

import qjs from './NativeQuickJs';
import { JSContext } from './JSContext';

export class JSValue {
  private ctxHandle: JSContext;
  private handle: bigint;
  private _released: boolean = false;

  constructor(context: JSContext, valueHandle: bigint) {
    this.ctxHandle = context;
    this.handle = valueHandle;
  }

  get valueHandle(): bigint {
    return this.handle;
  }

  get context(): JSContext {
    return this.ctxHandle;
  }

  // ==================== Factory Methods ====================

  static valueWithUndefined(ctx: JSContext): JSValue {
    const handle = qjs.createUndefined(ctx.engineHandle);
    return new JSValue(ctx, handle);
  }

  static valueWithNull(ctx: JSContext): JSValue {
    const handle = qjs.createNull(ctx.engineHandle);
    return new JSValue(ctx, handle);
  }

  static valueWithBool(value: boolean, ctx: JSContext): JSValue {
    const handle = qjs.createBoolean(ctx.engineHandle, value);
    return new JSValue(ctx, handle);
  }

  static valueWithNumber(value: number, ctx: JSContext): JSValue {
    const handle = qjs.createNumber(ctx.engineHandle, value);
    return new JSValue(ctx, handle);
  }

  static valueWithString(value: string, ctx: JSContext): JSValue {
    const handle = qjs.createString(ctx.engineHandle, value);
    return new JSValue(ctx, handle);
  }

  static valueWithNewObject(ctx: JSContext): JSValue {
    const handle = qjs.createObject(ctx.engineHandle);
    return new JSValue(ctx, handle);
  }

  static valueWithNewArray(ctx: JSContext, length?: number): JSValue {
    const handle = qjs.createArray(ctx.engineHandle, length ?? 0);
    return new JSValue(ctx, handle);
  }

  static valueWithNewError(message: string, ctx: JSContext): JSValue {
    const handle = qjs.createError(ctx.engineHandle, 'Error', message);
    return new JSValue(ctx, handle);
  }

  static valueWithNewTypeError(message: string, ctx: JSContext): JSValue {
    const handle = qjs.createError(ctx.engineHandle, 'TypeError', message);
    return new JSValue(ctx, handle);
  }

  static valueWithNewRangeError(message: string, ctx: JSContext): JSValue {
    const handle = qjs.createError(ctx.engineHandle, 'RangeError', message);
    return new JSValue(ctx, handle);
  }

  static valueWithNewSyntaxError(message: string, ctx: JSContext): JSValue {
    const handle = qjs.createError(ctx.engineHandle, 'SyntaxError', message);
    return new JSValue(ctx, handle);
  }

  static valueWithNewReferenceError(message: string, ctx: JSContext): JSValue {
    const handle = qjs.createError(ctx.engineHandle, 'ReferenceError', message);
    return new JSValue(ctx, handle);
  }

  // ==================== Type Checks ====================

  get isUndefined(): boolean {
    return qjs.isUndefined(this.handle);
  }

  get isNull(): boolean {
    return qjs.isNull(this.handle);
  }

  get isBoolean(): boolean {
    return qjs.isBoolean(this.handle);
  }

  get isNumber(): boolean {
    return qjs.isNumber(this.handle);
  }

  get isString(): boolean {
    return qjs.isString(this.handle);
  }

  get isObject(): boolean {
    return qjs.isObject(this.handle);
  }

  get isArray(): boolean {
    return qjs.isArray(this.handle);
  }

  get isDate(): boolean {
    return qjs.isDate(this.handle);
  }

  get isCallable(): boolean {
    return qjs.isCallable(this.handle);
  }

  get isError(): boolean {
    return qjs.isError(this.handle);
  }

  get isException(): boolean {
    return qjs.isException(this.handle);
  }

  // ==================== Conversion ====================

  toObject(): object | null {
    if (!this.isObject) return null;
    // Return a proxy or plain object from properties
    return this.toDictionary();
  }

  toBoolean(): boolean {
    return qjs.toBooleanValue(this.handle);
  }

  toNumber(): number {
    return qjs.toNumberValue(this.handle);
  }

  toString(): string {
    return qjs.toStringValue(this.handle);
  }

  toDate(): Date | null {
    if (!this.isDate) return null;
    return new Date(this.toNumber());
  }

  toArray(): JSValue[] | null {
    if (!this.isArray) return null;
    const len = qjs.getArrayLength(this.ctxHandle.engineHandle, this.handle);
    const result: JSValue[] = [];
    for (let i = 0; i < len; i++) {
      const elemHandle = qjs.getElement(this.ctxHandle.engineHandle, this.handle, i);
      result.push(new JSValue(this.ctxHandle, elemHandle));
    }
    return result;
  }

  toDictionary(): Record<string, JSValue> | null {
    if (!this.isObject) return null;
    const namesHandle = qjs.getPropertyNames(this.ctxHandle.engineHandle, this.handle);
    const namesLen = qjs.getArrayLength(this.ctxHandle.engineHandle, namesHandle);
    const result: Record<string, JSValue> = {};
    for (let i = 0; i < namesLen; i++) {
      const nameHandle = qjs.getElement(this.ctxHandle.engineHandle, namesHandle, i);
      const name = qjs.toStringValue(nameHandle);
      qjs.release(nameHandle);
      const valHandle = qjs.getProperty(this.ctxHandle.engineHandle, this.handle, name);
      result[name] = new JSValue(this.ctxHandle, valHandle);
      qjs.release(valHandle);
    }
    qjs.release(namesHandle);
    return result;
  }

  // ==================== Property Access ====================

  getProperty(property: string): JSValue {
    const handle = qjs.getProperty(this.ctxHandle.engineHandle, this.handle, property);
    return new JSValue(this.ctxHandle, handle);
  }

  valueForProperty(property: string): JSValue {
    return this.getProperty(property);
  }

  setValue(value: JSValue, property: string): void {
    qjs.setProperty(this.ctxHandle.engineHandle, this.handle, property, value.handle);
  }

  hasProperty(property: string): boolean {
    return qjs.hasProperty(this.ctxHandle.engineHandle, this.handle, property);
  }

  deleteProperty(property: string): boolean {
    return qjs.deleteProperty(this.ctxHandle.engineHandle, this.handle, property);
  }

  getPropertyNames(): string[] {
    const namesHandle = qjs.getPropertyNames(this.ctxHandle.engineHandle, this.handle);
    const len = qjs.getArrayLength(this.ctxHandle.engineHandle, namesHandle);
    const result: string[] = [];
    for (let i = 0; i < len; i++) {
      const nameHandle = qjs.getElement(this.ctxHandle.engineHandle, namesHandle, i);
      result.push(qjs.toStringValue(nameHandle));
      qjs.release(nameHandle);
    }
    qjs.release(namesHandle);
    return result;
  }

  // ==================== Array Elements ====================

  valueAtIndex(index: number): JSValue {
    const handle = qjs.getElement(this.ctxHandle.engineHandle, this.handle, index);
    return new JSValue(this.ctxHandle, handle);
  }

  setValueAtIndex(value: JSValue, index: number): void {
    qjs.setElement(this.ctxHandle.engineHandle, this.handle, index, value.handle);
  }

  get arrayLength(): number {
    return qjs.getArrayLength(this.ctxHandle.engineHandle, this.handle);
  }

  // ==================== Function Call ====================

  callWithArguments(args: JSValue[]): JSValue {
    const argHandles = args.map((a) => a.handle);
    // Use global object as this
    const globalHandle = qjs.getGlobal(this.ctxHandle.engineHandle);
    const resultHandle = qjs.callFunction(this.ctxHandle.engineHandle, globalHandle, this.handle, argHandles);
    qjs.release(globalHandle);
    return new JSValue(this.ctxHandle, resultHandle);
  }

  constructWithArguments(args: JSValue[]): JSValue {
    const argHandles = args.map((a) => a.handle);
    const resultHandle = qjs.construct(this.ctxHandle.engineHandle, this.handle, argHandles);
    return new JSValue(this.ctxHandle, resultHandle);
  }

  invokeMethod(methodName: string, args: JSValue[]): JSValue {
    const method = this.getProperty(methodName);
    return method.callWithArguments(args);
  }

  // ==================== Error Details ====================

  get errorMessage(): string {
    if (!this.isError) return '';
    const msgHandle = qjs.getProperty(this.ctxHandle.engineHandle, this.handle, 'message');
    return qjs.toStringValue(msgHandle);
  }

  get errorName(): string {
    if (!this.isError) return '';
    const nameHandle = qjs.getProperty(this.ctxHandle.engineHandle, this.handle, 'name');
    return qjs.toStringValue(nameHandle);
  }

  get errorStack(): string {
    if (!this.isError) return '';
    const stackHandle = qjs.getProperty(this.ctxHandle.engineHandle, this.handle, 'stack');
    return qjs.toStringValue(stackHandle);
  }

  // ==================== Comparison ====================

  isEqualTo(value: JSValue): boolean {
    return qjs.strictEquals(this.handle, value.handle);
  }

  isEqualWithTypeCoercionTo(value: JSValue): boolean {
    return qjs.looseEquals(this.handle, value.handle);
  }

  isInstanceOf(constructor: JSValue): boolean {
    return qjs.instanceOf(this.handle, constructor.handle);
  }

  // ==================== Lifecycle ====================

  addRef(): void {
    this._released = false;
    qjs.addRef(this.handle);
  }

  release(): void {
    this.finalize();
  }

  finalize(): void {
    if (this._released) return;
    this._released = true;
    qjs.release(this.handle);
  }
}
