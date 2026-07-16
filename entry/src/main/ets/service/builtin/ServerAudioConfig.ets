import { PreferenceService } from '../PreferenceService';
import { HttpClient } from '../http/HttpClient';
import { JsonObj } from './JsonValue';

export const DEFAULT_SERVER_AUDIO_API_BASE = 'https://121.196.223.85/api/v1';

export enum ServerAudioConfigErrorCode {
  EMPTY = 'SERVER_AUDIO_API_EMPTY',
  INVALID_SCHEME = 'SERVER_AUDIO_API_INVALID_SCHEME',
  INVALID_URL = 'SERVER_AUDIO_API_INVALID_URL',
  CONNECTION_FAILED = 'SERVER_AUDIO_API_CONNECTION_FAILED'
}

const HEALTH_TIMEOUT_MS = 8000;

/** 云源地址的单一配置入口，负责规范化、持久化和进程内缓存。 */
export class ServerAudioConfig {
  private static cachedApiBase: string | null = null;

  static peekApiBase(): string {
    return ServerAudioConfig.cachedApiBase ?? DEFAULT_SERVER_AUDIO_API_BASE;
  }

  static async getApiBase(): Promise<string> {
    if (ServerAudioConfig.cachedApiBase) {
      return ServerAudioConfig.cachedApiBase;
    }
    try {
      const stored = await PreferenceService.getServerAudioApiBase();
      ServerAudioConfig.cachedApiBase = stored
        ? ServerAudioConfig.normalizeApiBase(stored)
        : DEFAULT_SERVER_AUDIO_API_BASE;
    } catch (_e) {
      ServerAudioConfig.cachedApiBase = DEFAULT_SERVER_AUDIO_API_BASE;
    }
    return ServerAudioConfig.cachedApiBase;
  }

  static async saveApiBase(value: string): Promise<string> {
    const normalized = ServerAudioConfig.normalizeApiBase(value);
    await PreferenceService.setServerAudioApiBase(normalized);
    ServerAudioConfig.cachedApiBase = normalized;
    return normalized;
  }

  static async resetApiBase(): Promise<string> {
    await PreferenceService.clearServerAudioApiBase();
    ServerAudioConfig.cachedApiBase = DEFAULT_SERVER_AUDIO_API_BASE;
    return DEFAULT_SERVER_AUDIO_API_BASE;
  }

  static normalizeApiBase(value: string): string {
    let normalized = value.trim();
    if (!normalized) {
      throw new Error(ServerAudioConfigErrorCode.EMPTY);
    }
    if (!normalized.includes('://')) {
      normalized = `https://${normalized}`;
    }

    const lower = normalized.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      throw new Error(ServerAudioConfigErrorCode.INVALID_SCHEME);
    }
    if (/\s|[?#]/.test(normalized)) {
      throw new Error(ServerAudioConfigErrorCode.INVALID_URL);
    }

    normalized = normalized.replace(/\/+$/, '');
    const schemeEnd = normalized.indexOf('://') + 3;
    const pathStart = normalized.indexOf('/', schemeEnd);
    const authority = pathStart >= 0
      ? normalized.substring(schemeEnd, pathStart)
      : normalized.substring(schemeEnd);
    const authorityPattern = /^(\[[0-9a-fA-F:]+\]|[a-zA-Z0-9.-]+)(:\d{1,5})?$/;
    if (!authority || !authorityPattern.test(authority)) {
      throw new Error(ServerAudioConfigErrorCode.INVALID_URL);
    }

    if (pathStart < 0) {
      normalized += '/api/v1';
    }
    return normalized;
  }

  /** 返回 true 表示解析引擎就绪，false 表示接口可达但服务处于 degraded。 */
  static async checkConnection(value: string): Promise<boolean> {
    const apiBase = ServerAudioConfig.normalizeApiBase(value);
    try {
      const response = await HttpClient.request(`${apiBase}/health`, {
        method: 'GET',
        headers: { 'Accept': 'application/json' },
        timeout: HEALTH_TIMEOUT_MS,
        retry: 0
      });
      if (response.statusCode < 200 || response.statusCode >= 300 || !response.body) {
        throw new Error(ServerAudioConfigErrorCode.CONNECTION_FAILED);
      }
      const root = new JsonObj(JSON.parse(response.body) as Object);
      if (root.getString('code', '') !== 'OK') {
        throw new Error(ServerAudioConfigErrorCode.CONNECTION_FAILED);
      }
      return root.getObj('data').getString('status', 'ready') !== 'degraded';
    } catch (e) {
      if (e instanceof Error && (e.message === ServerAudioConfigErrorCode.EMPTY ||
        e.message === ServerAudioConfigErrorCode.INVALID_SCHEME ||
        e.message === ServerAudioConfigErrorCode.INVALID_URL)) {
        throw e;
      }
      throw new Error(ServerAudioConfigErrorCode.CONNECTION_FAILED);
    }
  }
}
