import { buffer, url } from '@kit.ArkTS';
import { HttpClient, HttpRequestOptions, HttpResponse } from '../http/HttpClient';

export enum RuleSourceRemoteImportFailure {
  ADDRESS,
  TOO_LARGE,
  AUTH,
  NOT_FOUND,
  HTML,
  FORMAT,
  NETWORK
}

export class RuleSourceRemoteImportError extends Error {
  failure: RuleSourceRemoteImportFailure;

  constructor(failure: RuleSourceRemoteImportFailure) {
    // Never include a personal subscription URL or the server response in an error/log.
    super('Rule source remote import failed');
    this.failure = failure;
  }
}

/** Subscription downloads feed the ordinary imported-source parser and encrypted repository. */
export class LocalRuleSourceRemoteImporter {
  static readonly MAX_BYTES: number = 10 * 1024 * 1024;

  static isRemote(input: string): boolean {
    return new RegExp('^(https?://|legado://|yuedu://)', 'i').test(input.trim());
  }

  static address(input: string): string {
    let value = input.trim();
    if (new RegExp('^(legado|yuedu)://', 'i').test(value)) {
      try {
        const shared = url.URL.parseURL(value);
        const host = shared.hostname.toLowerCase();
        const path = shared.pathname.toLowerCase().replace(new RegExp('/$'), '');
        const supported = (host === 'booksource' && (path === '' || path === '/importonline')) ||
          (shared.protocol.toLowerCase() === 'legado:' && host === 'import' && path === '/booksource');
        if (!supported || value.length > 32 * 1024) {
          throw new RuleSourceRemoteImportError(RuleSourceRemoteImportFailure.ADDRESS);
        }
        // Only unwrap a second layer if the whole URL is still encoded. Never decode
        // the query again once its HTTP(S) prefix is visible (signed values must survive).
        value = shared.params.get('src') ?? '';
        if (new RegExp('^https?%3a%2f%2f', 'i').test(value)) value = decodeURIComponent(value);
        if (value.length > 16 * 1024) {
          throw new RuleSourceRemoteImportError(RuleSourceRemoteImportFailure.ADDRESS);
        }
      } catch (_error) {
        throw new RuleSourceRemoteImportError(RuleSourceRemoteImportFailure.ADDRESS);
      }
    }
    try {
      const parsed = url.URL.parseURL(value);
      if (!['http:', 'https:'].includes(parsed.protocol.toLowerCase()) || !parsed.hostname ||
          parsed.username || parsed.password) {
        throw new RuleSourceRemoteImportError(RuleSourceRemoteImportFailure.ADDRESS);
      }
    } catch (_error) {
      throw new RuleSourceRemoteImportError(RuleSourceRemoteImportFailure.ADDRESS);
    }
    return value;
  }

  static async resolve(input: string): Promise<string> {
    if (input.length > LocalRuleSourceRemoteImporter.MAX_BYTES ||
        buffer.byteLength(input, 'utf-8') > LocalRuleSourceRemoteImporter.MAX_BYTES) {
      throw new RuleSourceRemoteImportError(RuleSourceRemoteImportFailure.TOO_LARGE);
    }
    if (!LocalRuleSourceRemoteImporter.isRemote(input)) return input;
    const address = LocalRuleSourceRemoteImporter.address(input);
    const options: HttpRequestOptions = {
      method: 'GET',
      headers: {
        'Accept': 'application/json,text/plain,*/*',
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36'
      },
      timeout: 20000,
      retry: 0
    };
    let failure = new RuleSourceRemoteImportError(RuleSourceRemoteImportFailure.NETWORK);
    // Retry transport/format failures through the existing system HTTP channel,
    // retaining the exact user-provided address and subscription parameters.
    for (let channel = 0; channel < 2; channel++) {
      try {
        const response = channel === 0 ? await HttpClient.request(address, options) :
          await HttpClient.requestLegacy(address, options);
        return LocalRuleSourceRemoteImporter.content(response);
      } catch (error) {
        if (error instanceof RuleSourceRemoteImportError) {
          failure = error;
          if (error.failure === RuleSourceRemoteImportFailure.TOO_LARGE ||
              error.failure === RuleSourceRemoteImportFailure.AUTH ||
              error.failure === RuleSourceRemoteImportFailure.NOT_FOUND) throw error;
        }
      }
    }
    throw failure;
  }

  private static content(response: HttpResponse): string {
    if (response.statusCode === 401 || response.statusCode === 403) {
      throw new RuleSourceRemoteImportError(RuleSourceRemoteImportFailure.AUTH);
    }
    if (response.statusCode === 404 || response.statusCode === 410) {
      throw new RuleSourceRemoteImportError(RuleSourceRemoteImportFailure.NOT_FOUND);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw new RuleSourceRemoteImportError(RuleSourceRemoteImportFailure.NETWORK);
    }
    if (response.body.length > LocalRuleSourceRemoteImporter.MAX_BYTES ||
        buffer.byteLength(response.body, 'utf-8') > LocalRuleSourceRemoteImporter.MAX_BYTES) {
      throw new RuleSourceRemoteImportError(RuleSourceRemoteImportFailure.TOO_LARGE);
    }
    const text = response.body.trim();
    if (text.startsWith('<')) {
      throw new RuleSourceRemoteImportError(RuleSourceRemoteImportFailure.HTML);
    }
    if (!text.startsWith('{') && !text.startsWith('[')) {
      throw new RuleSourceRemoteImportError(RuleSourceRemoteImportFailure.FORMAT);
    }
    try {
      JSON.parse(text);
    } catch (_error) {
      throw new RuleSourceRemoteImportError(RuleSourceRemoteImportFailure.FORMAT);
    }
    return text;
  }
}
