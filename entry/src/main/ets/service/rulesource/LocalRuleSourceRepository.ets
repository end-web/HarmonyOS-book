import { common } from '@kit.AbilityKit';
import { buffer } from '@kit.ArkTS';
import { relationalStore } from '@kit.ArkData';
import {
  LocalRuleSource,
  LocalRuleSourceCookie,
  LocalRuleSourceImportReport,
  LocalRuleSourceSession,
  LocalRuleSourceStatus
} from '../../model/LocalRuleSource';
import { LocalRuleSourceImportParser } from './LocalRuleSourceImportParser';

const DATABASE_NAME = 'rule_sources.db';
const TABLE_NAME = 'rule_sources';
const SESSION_TABLE_NAME = 'rule_source_sessions';
const COOKIE_TABLE_NAME = 'rule_source_cookies';
const MAX_SOURCE_JSON_BYTES = 512 * 1024;
const MAX_SESSION_TOKEN_LENGTH = 4096;
const MAX_SESSION_DEVICE_ID_LENGTH = 256;
const MAX_COOKIE_HEADER_LENGTH = 64 * 1024;
const BATCH_PREDICATE_LIMIT = 400;

const CREATE_TABLE_SQL = `CREATE TABLE IF NOT EXISTS ${TABLE_NAME} (
  source_url TEXT PRIMARY KEY NOT NULL,
  source_name TEXT NOT NULL,
  source_type INTEGER NOT NULL DEFAULT 0,
  source_group TEXT NOT NULL DEFAULT '',
  source_json TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  validation_status INTEGER NOT NULL DEFAULT 0,
  validation_message TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)`;

// 不建级联外键：书源 upsert 使用 REPLACE，同 URL 重导不能连带删除既有会话。
const CREATE_SESSION_TABLE_SQL = `CREATE TABLE IF NOT EXISTS ${SESSION_TABLE_NAME} (
  source_url TEXT PRIMARY KEY NOT NULL,
  token TEXT NOT NULL,
  device_id TEXT NOT NULL,
  account_label TEXT NOT NULL DEFAULT '',
  updated_at INTEGER NOT NULL
)`;

const CREATE_COOKIE_TABLE_SQL = `CREATE TABLE IF NOT EXISTS ${COOKIE_TABLE_NAME} (
  source_url TEXT NOT NULL,
  origin TEXT NOT NULL,
  cookie_header TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (source_url, origin)
)`;

const SELECT_COLUMNS = 'source_url, source_name, source_type, source_group, source_json, ' +
  'enabled, validation_status, validation_message';
const LIST_SQL = `SELECT ${SELECT_COLUMNS} FROM ${TABLE_NAME} ` +
  'ORDER BY sort_order DESC, source_name COLLATE NOCASE ASC';
const GET_SQL = `SELECT ${SELECT_COLUMNS} FROM ${TABLE_NAME} WHERE source_url = ? LIMIT 1`;
const SESSION_SELECT_COLUMNS = 'source_url, token, device_id, account_label, updated_at';
const GET_SESSION_SQL = `SELECT ${SESSION_SELECT_COLUMNS} FROM ${SESSION_TABLE_NAME} ` +
  'WHERE source_url = ? LIMIT 1';
const COOKIE_SELECT_COLUMNS = 'source_url, origin, cookie_header, updated_at';
const LIST_COOKIES_SQL = `SELECT ${COOKIE_SELECT_COLUMNS} FROM ${COOKIE_TABLE_NAME} ` +
  'WHERE source_url = ? ORDER BY updated_at DESC';

class PreparedRuleSource {
  source: LocalRuleSource = new LocalRuleSource();
  sourceJson: string = '';

  constructor(source: LocalRuleSource, sourceJson: string) {
    this.source = source;
    this.sourceJson = sourceJson;
  }
}

/**
 * 本地规则书源的独立持久化仓库。
 *
 * 初始化和读写错误会原样抛给调用方，由上层决定是否降级到内置源；仓库不会删除或重建损坏数据库。
 */
export class LocalRuleSourceRepository {
  private static store: relationalStore.RdbStore | null = null;
  private static initPromise: Promise<void> | null = null;

  static async init(context: common.BaseContext): Promise<void> {
    if (LocalRuleSourceRepository.store !== null) return;
    if (LocalRuleSourceRepository.initPromise !== null) {
      await LocalRuleSourceRepository.initPromise;
      return;
    }

    const pending = LocalRuleSourceRepository.open(context);
    LocalRuleSourceRepository.initPromise = pending;
    try {
      await pending;
    } catch (error) {
      if (LocalRuleSourceRepository.initPromise === pending) {
        LocalRuleSourceRepository.initPromise = null;
      }
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  static async list(): Promise<LocalRuleSource[]> {
    const store = await LocalRuleSourceRepository.ensureStore();
    let resultSet: relationalStore.ResultSet | null = null;
    const sources: LocalRuleSource[] = [];
    try {
      resultSet = await store.querySql(LIST_SQL);
      while (resultSet.goToNextRow()) {
        sources.push(LocalRuleSourceRepository.readSource(resultSet));
      }
      return sources;
    } finally {
      if (resultSet !== null) resultSet.close();
    }
  }

  static async getAll(): Promise<LocalRuleSource[]> {
    return LocalRuleSourceRepository.list();
  }

  static async getEnabled(): Promise<LocalRuleSource[]> {
    const sources = await LocalRuleSourceRepository.list();
    return sources.filter((source: LocalRuleSource): boolean => source.isSearchEnabled());
  }

  static async get(sourceUrl: string): Promise<LocalRuleSource | undefined> {
    const normalizedUrl = sourceUrl.trim();
    if (normalizedUrl.length === 0) return undefined;

    const store = await LocalRuleSourceRepository.ensureStore();
    let resultSet: relationalStore.ResultSet | null = null;
    const args: relationalStore.ValueType[] = [normalizedUrl];
    try {
      resultSet = await store.querySql(GET_SQL, args);
      if (!resultSet.goToFirstRow()) return undefined;
      return LocalRuleSourceRepository.readSource(resultSet);
    } finally {
      if (resultSet !== null) resultSet.close();
    }
  }

  static async getByUrl(sourceUrl: string): Promise<LocalRuleSource | undefined> {
    return LocalRuleSourceRepository.get(sourceUrl);
  }

  static async findByUrl(sourceUrl: string): Promise<LocalRuleSource | undefined> {
    return LocalRuleSourceRepository.get(sourceUrl);
  }

  static async insert(source: LocalRuleSource): Promise<void> {
    await LocalRuleSourceRepository.upsert(source);
  }

  static async update(source: LocalRuleSource): Promise<void> {
    await LocalRuleSourceRepository.upsert(source);
  }

  static async getSession(sourceUrl: string): Promise<LocalRuleSourceSession | undefined> {
    const normalizedUrl = LocalRuleSourceRepository.requireSourceUrl(sourceUrl);
    const store = await LocalRuleSourceRepository.ensureStore();
    let resultSet: relationalStore.ResultSet | null = null;
    const args: relationalStore.ValueType[] = [normalizedUrl];
    try {
      resultSet = await store.querySql(GET_SESSION_SQL, args);
      if (!resultSet.goToFirstRow()) return undefined;
      const session = new LocalRuleSourceSession();
      session.sourceUrl = resultSet.getString(0);
      session.token = LocalRuleSourceRepository.requireSessionToken(resultSet.getString(1));
      session.deviceId = LocalRuleSourceRepository.requireSessionValue(
        'deviceId', resultSet.getString(2), MAX_SESSION_DEVICE_ID_LENGTH);
      session.accountLabel = resultSet.getString(3);
      session.updatedAt = resultSet.getLong(4);
      return session;
    } finally {
      if (resultSet !== null) resultSet.close();
    }
  }

  static async saveSession(session: LocalRuleSourceSession): Promise<void> {
    const sourceUrl = LocalRuleSourceRepository.requireSourceUrl(session.sourceUrl);
    const token = LocalRuleSourceRepository.requireSessionToken(session.token);
    const deviceId = LocalRuleSourceRepository.requireSessionValue(
      'deviceId', session.deviceId, MAX_SESSION_DEVICE_ID_LENGTH);
    const source = await LocalRuleSourceRepository.get(sourceUrl);
    if (source === undefined) throw new Error(`书源不存在：${sourceUrl}`);

    const store = await LocalRuleSourceRepository.ensureStore();
    const updatedAt = Date.now();
    const values: relationalStore.ValuesBucket = {
      'source_url': sourceUrl,
      'token': token,
      'device_id': deviceId,
      'account_label': session.accountLabel,
      'updated_at': updatedAt
    };
    const rowId = await store.insert(SESSION_TABLE_NAME, values,
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    if (rowId < 0) throw new Error(`书源会话写入失败：${sourceUrl}`);
    session.sourceUrl = sourceUrl;
    session.updatedAt = updatedAt;
  }

  static async clearSession(sourceUrl: string): Promise<void> {
    const normalizedUrl = LocalRuleSourceRepository.requireSourceUrl(sourceUrl);
    const store = await LocalRuleSourceRepository.ensureStore();
    const predicates = new relationalStore.RdbPredicates(SESSION_TABLE_NAME);
    predicates.equalTo('source_url', normalizedUrl);
    await store.delete(predicates);
  }

  static async listCookies(sourceUrl: string): Promise<LocalRuleSourceCookie[]> {
    const normalizedUrl = LocalRuleSourceRepository.requireSourceUrl(sourceUrl);
    const store = await LocalRuleSourceRepository.ensureStore();
    let resultSet: relationalStore.ResultSet | null = null;
    const cookies: LocalRuleSourceCookie[] = [];
    const args: relationalStore.ValueType[] = [normalizedUrl];
    try {
      resultSet = await store.querySql(LIST_COOKIES_SQL, args);
      while (resultSet.goToNextRow()) {
        const cookie = new LocalRuleSourceCookie();
        cookie.sourceUrl = resultSet.getString(0);
        cookie.origin = LocalRuleSourceRepository.requireOrigin(resultSet.getString(1));
        cookie.cookieHeader = LocalRuleSourceRepository.requireCookieHeader(resultSet.getString(2));
        cookie.updatedAt = resultSet.getLong(3);
        cookies.push(cookie);
      }
      return cookies;
    } finally {
      if (resultSet !== null) resultSet.close();
    }
  }

  static async saveCookie(cookie: LocalRuleSourceCookie): Promise<void> {
    const sourceUrl = LocalRuleSourceRepository.requireSourceUrl(cookie.sourceUrl);
    const origin = LocalRuleSourceRepository.requireOrigin(cookie.origin);
    const cookieHeader = LocalRuleSourceRepository.requireCookieHeader(cookie.cookieHeader);
    if (cookieHeader.length === 0) {
      await LocalRuleSourceRepository.clearCookie(sourceUrl, origin);
      return;
    }
    const source = await LocalRuleSourceRepository.get(sourceUrl);
    if (source === undefined) throw new Error(`书源不存在：${sourceUrl}`);

    const store = await LocalRuleSourceRepository.ensureStore();
    const updatedAt = Date.now();
    const values: relationalStore.ValuesBucket = {
      'source_url': sourceUrl,
      'origin': origin,
      'cookie_header': cookieHeader,
      'updated_at': updatedAt
    };
    const rowId = await store.insert(COOKIE_TABLE_NAME, values,
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    if (rowId < 0) throw new Error(`书源 Cookie 写入失败：${sourceUrl}`);
    cookie.sourceUrl = sourceUrl;
    cookie.origin = origin;
    cookie.cookieHeader = cookieHeader;
    cookie.updatedAt = updatedAt;
  }

  static async clearCookie(sourceUrl: string, origin: string): Promise<void> {
    const normalizedUrl = LocalRuleSourceRepository.requireSourceUrl(sourceUrl);
    const normalizedOrigin = LocalRuleSourceRepository.requireOrigin(origin);
    const store = await LocalRuleSourceRepository.ensureStore();
    const predicates = new relationalStore.RdbPredicates(COOKIE_TABLE_NAME);
    predicates.equalTo('source_url', normalizedUrl);
    predicates.equalTo('origin', normalizedOrigin);
    await store.delete(predicates);
  }

  static async clearCookies(sourceUrl: string): Promise<void> {
    const normalizedUrl = LocalRuleSourceRepository.requireSourceUrl(sourceUrl);
    const store = await LocalRuleSourceRepository.ensureStore();
    const predicates = new relationalStore.RdbPredicates(COOKIE_TABLE_NAME);
    predicates.equalTo('source_url', normalizedUrl);
    await store.delete(predicates);
  }

  static async upsert(source: LocalRuleSource): Promise<void> {
    const sources: LocalRuleSource[] = [source];
    await LocalRuleSourceRepository.upsertBatch(sources);
  }

  static async upsertMany(sources: LocalRuleSource[]): Promise<void> {
    await LocalRuleSourceRepository.upsertBatch(sources);
  }

  /** 更新已导入书源时沿用用户当前的启用状态。 */
  static async upsertImportedBatch(sources: LocalRuleSource[]): Promise<number> {
    const existing = await LocalRuleSourceRepository.list();
    LocalRuleSourceRepository.preserveEnabledStates(sources, existing);
    return LocalRuleSourceRepository.upsertBatch(sources);
  }

  static preserveEnabledStates(incoming: LocalRuleSource[], existing: LocalRuleSource[]): void {
    const enabledByUrl = new Map<string, boolean>();
    for (const source of existing) {
      enabledByUrl.set(source.bookSourceUrl.trim(), source.enabled);
    }
    for (const source of incoming) {
      const sourceUrl = source.bookSourceUrl.trim();
      if (!source.canExecute()) {
        source.enabled = false;
      } else if (enabledByUrl.has(sourceUrl)) {
        source.enabled = enabledByUrl.get(sourceUrl) ?? false;
      }
    }
  }

  /** 全批次预校验后再写入，任意一条失败都会回滚整个批次。 */
  static async upsertBatch(sources: LocalRuleSource[]): Promise<number> {
    if (sources.length === 0) return 0;

    const prepared: PreparedRuleSource[] = [];
    for (const source of sources) {
      prepared.push(LocalRuleSourceRepository.prepare(source));
    }

    const store = await LocalRuleSourceRepository.ensureStore();
    const transaction = await store.createTransaction();
    const now = Date.now();
    try {
      for (let index = 0; index < prepared.length; index++) {
        const item = prepared[index];
        const values = LocalRuleSourceRepository.toValues(item, now - index, now);
        const rowId = await transaction.insert(TABLE_NAME, values,
          relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        if (rowId < 0) {
          throw new Error(`书源写入失败：${item.source.bookSourceName}`);
        }
      }
      await transaction.commit();
      return prepared.length;
    } catch (error) {
      try {
        await transaction.rollback();
      } catch (_rollbackError) {
        // 事务可能已因提交失败而关闭，保留原始写入错误。
      }
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  /** 批量测试仅更新健康状态，避免重复解析和重写整份书源 JSON。 */
  static async updateValidationBatch(sources: LocalRuleSource[]): Promise<void> {
    if (sources.length === 0) return;
    const store = await LocalRuleSourceRepository.ensureStore();
    const transaction = await store.createTransaction();
    try {
      for (const source of sources) {
        const sourceUrl = LocalRuleSourceRepository.requireSourceUrl(source.bookSourceUrl);
        const values: relationalStore.ValuesBucket = {
          'validation_status': source.validationStatus,
          'validation_message': source.validationMessage,
          'updated_at': Date.now()
        };
        const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
        predicates.equalTo('source_url', sourceUrl);
        const updated = await transaction.update(values, predicates);
        if (updated !== 1) throw new Error(`书源状态更新失败：${sourceUrl}`);
      }
      await transaction.commit();
    } catch (error) {
      try {
        await transaction.rollback();
      } catch (_rollbackError) {
        // 事务可能已关闭，保留原始状态更新错误。
      }
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  static async setEnabled(sourceUrl: string, enabled: boolean): Promise<void> {
    const normalizedUrl = LocalRuleSourceRepository.requireSourceUrl(sourceUrl);
    const updated = await LocalRuleSourceRepository.updateEnabled(normalizedUrl, enabled);
    if (!updated) throw new Error(`书源不存在：${normalizedUrl}`);
  }

  /** 在同一事务中启用或禁用多条书源，任一书源不存在则整批回滚。 */
  static async setEnabledBatch(sourceUrls: string[], enabled: boolean): Promise<number> {
    if (sourceUrls.length === 0) return 0;
    const normalizedUrls: string[] = [];
    const seen = new Set<string>();
    for (const sourceUrl of sourceUrls) {
      const normalizedUrl = LocalRuleSourceRepository.requireSourceUrl(sourceUrl);
      if (seen.has(normalizedUrl)) continue;
      seen.add(normalizedUrl);
      normalizedUrls.push(normalizedUrl);
    }

    const store = await LocalRuleSourceRepository.ensureStore();
    const transaction = await store.createTransaction();
    const values: relationalStore.ValuesBucket = {
      'enabled': enabled ? 1 : 0,
      'updated_at': Date.now()
    };
    let updatedCount = 0;
    try {
      for (let start = 0; start < normalizedUrls.length; start += BATCH_PREDICATE_LIMIT) {
        const end = Math.min(normalizedUrls.length, start + BATCH_PREDICATE_LIMIT);
        const batchValues: relationalStore.ValueType[] = [];
        for (let index = start; index < end; index++) batchValues.push(normalizedUrls[index]);
        const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
        predicates.in('source_url', batchValues);
        const updated = await transaction.update(values, predicates);
        if (updated !== batchValues.length) throw new Error('部分书源不存在，批量启停已取消');
        updatedCount += updated;
      }
      await transaction.commit();
      return updatedCount;
    } catch (error) {
      try {
        await transaction.rollback();
      } catch (_rollbackError) {
        // 事务可能已关闭，保留原始更新错误。
      }
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  static async toggle(sourceUrl: string): Promise<boolean> {
    const normalizedUrl = LocalRuleSourceRepository.requireSourceUrl(sourceUrl);
    const source = await LocalRuleSourceRepository.get(normalizedUrl);
    if (source === undefined) {
      throw new Error(`书源不存在：${normalizedUrl}`);
    }
    const enabled = !source.enabled;
    await LocalRuleSourceRepository.setEnabled(normalizedUrl, enabled);
    return enabled;
  }

  static async delete(sourceUrl: string): Promise<boolean> {
    const normalizedUrl = LocalRuleSourceRepository.requireSourceUrl(sourceUrl);
    const store = await LocalRuleSourceRepository.ensureStore();
    const transaction = await store.createTransaction();
    const sessionPredicates = new relationalStore.RdbPredicates(SESSION_TABLE_NAME);
    sessionPredicates.equalTo('source_url', normalizedUrl);
    const cookiePredicates = new relationalStore.RdbPredicates(COOKIE_TABLE_NAME);
    cookiePredicates.equalTo('source_url', normalizedUrl);
    const sourcePredicates = new relationalStore.RdbPredicates(TABLE_NAME);
    sourcePredicates.equalTo('source_url', normalizedUrl);
    try {
      await transaction.delete(sessionPredicates);
      await transaction.delete(cookiePredicates);
      const deleted = await transaction.delete(sourcePredicates);
      await transaction.commit();
      return deleted > 0;
    } catch (error) {
      try {
        await transaction.rollback();
      } catch (_rollbackError) {
        // 事务可能已关闭，保留原始删除错误。
      }
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  /** 在同一事务中分块删除多条书源、登录会话和 Cookie，避免大批量逐行调用。 */
  static async deleteBatch(sourceUrls: string[]): Promise<number> {
    if (sourceUrls.length === 0) return 0;
    const normalizedUrls: string[] = [];
    const seen = new Set<string>();
    for (const sourceUrl of sourceUrls) {
      const normalizedUrl = LocalRuleSourceRepository.requireSourceUrl(sourceUrl);
      if (seen.has(normalizedUrl)) continue;
      seen.add(normalizedUrl);
      normalizedUrls.push(normalizedUrl);
    }

    const store = await LocalRuleSourceRepository.ensureStore();
    const transaction = await store.createTransaction();
    let deletedCount = 0;
    try {
      for (let start = 0; start < normalizedUrls.length; start += BATCH_PREDICATE_LIMIT) {
        const end = Math.min(normalizedUrls.length, start + BATCH_PREDICATE_LIMIT);
        const batchValues: relationalStore.ValueType[] = [];
        for (let index = start; index < end; index++) batchValues.push(normalizedUrls[index]);
        const sessionPredicates = new relationalStore.RdbPredicates(SESSION_TABLE_NAME);
        sessionPredicates.in('source_url', batchValues);
        const cookiePredicates = new relationalStore.RdbPredicates(COOKIE_TABLE_NAME);
        cookiePredicates.in('source_url', batchValues);
        const sourcePredicates = new relationalStore.RdbPredicates(TABLE_NAME);
        sourcePredicates.in('source_url', batchValues);
        await transaction.delete(sessionPredicates);
        await transaction.delete(cookiePredicates);
        deletedCount += await transaction.delete(sourcePredicates);
      }
      if (deletedCount !== normalizedUrls.length) throw new Error('部分书源不存在，批量删除已取消');
      await transaction.commit();
      return deletedCount;
    } catch (error) {
      try {
        await transaction.rollback();
      } catch (_rollbackError) {
        // 事务可能已关闭，保留原始删除错误。
      }
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  static async remove(sourceUrl: string): Promise<void> {
    await LocalRuleSourceRepository.delete(sourceUrl);
  }

  private static async open(context: common.BaseContext): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S2,
      encrypt: true,
      allowRebuild: false
    };
    const store = await relationalStore.getRdbStore(context, config);
    await store.execute(CREATE_TABLE_SQL);
    await store.execute(CREATE_SESSION_TABLE_SQL);
    await store.execute(CREATE_COOKIE_TABLE_SQL);
    LocalRuleSourceRepository.store = store;
  }

  private static async ensureStore(): Promise<relationalStore.RdbStore> {
    if (LocalRuleSourceRepository.store === null && LocalRuleSourceRepository.initPromise !== null) {
      await LocalRuleSourceRepository.initPromise;
    }
    if (LocalRuleSourceRepository.store === null) {
      throw new Error('LocalRuleSourceRepository 尚未初始化');
    }
    return LocalRuleSourceRepository.store;
  }

  private static async updateEnabled(sourceUrl: string, enabled: boolean): Promise<boolean> {
    const store = await LocalRuleSourceRepository.ensureStore();
    const values: relationalStore.ValuesBucket = {
      'enabled': enabled ? 1 : 0,
      'updated_at': Date.now()
    };
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('source_url', sourceUrl);
    return (await store.update(values, predicates)) > 0;
  }

  private static prepare(source: LocalRuleSource): PreparedRuleSource {
    const sourceUrl = LocalRuleSourceRepository.requireSourceUrl(source.bookSourceUrl);
    if (source.bookSourceName.trim().length === 0) {
      throw new Error(`书源名称为空：${sourceUrl}`);
    }

    const sourceJson = source.rawSourceJson.trim().length > 0
      ? source.rawSourceJson : JSON.stringify(source);
    const sourceBytes = buffer.byteLength(sourceJson, 'utf-8');
    if (sourceBytes > MAX_SOURCE_JSON_BYTES) {
      throw new Error(`书源数据超过 512 KiB：${source.bookSourceName}`);
    }

    const report = LocalRuleSourceImportParser.parse(sourceJson);
    let matched = false;
    for (const parsed of report.sources) {
      if (parsed.bookSourceUrl === sourceUrl) {
        matched = true;
        break;
      }
    }
    if (!matched) {
      const detail = report.message.length > 0 ? `，${report.message}` : '';
      throw new Error(`书源原始数据无法重建：${source.bookSourceName}${detail}`);
    }
    return new PreparedRuleSource(source, sourceJson);
  }

  private static toValues(item: PreparedRuleSource, sortOrder: number,
    now: number): relationalStore.ValuesBucket {
    const source = item.source;
    const values: relationalStore.ValuesBucket = {
      'source_url': source.bookSourceUrl.trim(),
      'source_name': source.bookSourceName.trim(),
      'source_type': source.bookSourceType,
      'source_group': source.bookSourceGroup,
      'source_json': item.sourceJson,
      'enabled': source.enabled ? 1 : 0,
      'validation_status': source.validationStatus,
      'validation_message': source.validationMessage,
      'sort_order': sortOrder,
      'created_at': now,
      'updated_at': now
    };
    return values;
  }

  private static readSource(resultSet: relationalStore.ResultSet): LocalRuleSource {
    const sourceUrl = resultSet.getString(0);
    const sourceName = resultSet.getString(1);
    const sourceType = resultSet.getLong(2);
    const sourceGroup = resultSet.getString(3);
    const sourceJson = resultSet.getString(4);
    const enabled = resultSet.getLong(5) !== 0;
    const validationStatus = resultSet.getLong(6);
    const validationMessage = resultSet.getString(7);

    const report: LocalRuleSourceImportReport = LocalRuleSourceImportParser.parse(sourceJson);
    let source: LocalRuleSource | undefined = undefined;
    for (const parsed of report.sources) {
      if (parsed.bookSourceUrl === sourceUrl) {
        source = parsed;
        break;
      }
    }
    if (source === undefined) {
      source = LocalRuleSource.descriptor(sourceUrl, sourceName);
      source.enabled = false;
      source.validationStatus = LocalRuleSourceStatus.UNSUPPORTED;
      source.validationMessage = report.message.length > 0
        ? `持久化书源无法解析：${report.message}` : '持久化书源无法解析';
    } else {
      source.enabled = enabled;
      if (validationStatus === LocalRuleSourceStatus.UNSUPPORTED) {
        source.validationStatus = LocalRuleSourceStatus.UNCHECKED;
        source.validationMessage = '兼容层已更新，等待重新测试';
      } else {
        source.validationStatus = validationStatus;
        source.validationMessage = validationMessage;
      }
    }

    source.bookSourceUrl = sourceUrl;
    source.bookSourceName = sourceName;
    source.bookSourceType = sourceType;
    source.bookSourceGroup = sourceGroup;
    source.rawSourceJson = sourceJson;
    return source;
  }

  private static requireSourceUrl(sourceUrl: string): string {
    const normalizedUrl = sourceUrl.trim();
    if (normalizedUrl.length === 0) throw new Error('书源地址为空');
    return normalizedUrl;
  }

  private static requireSessionValue(fieldName: string, value: string, maxLength: number): string {
    if (value.length === 0) throw new Error(`${fieldName} 不能为空`);
    if (value.length > maxLength) throw new Error(`${fieldName} 长度不能超过 ${maxLength}`);
    if (value.includes('\r') || value.includes('\n') || value.includes(';')) {
      throw new Error(`${fieldName} 包含非法字符`);
    }
    return value;
  }

  private static requireSessionToken(value: string): string {
    if (value.length > MAX_SESSION_TOKEN_LENGTH) {
      throw new Error(`token 长度不能超过 ${MAX_SESSION_TOKEN_LENGTH}`);
    }
    if (value.includes('\r') || value.includes('\n') || value.includes(';')) {
      throw new Error('token 包含非法字符');
    }
    return value;
  }

  private static requireOrigin(value: string): string {
    const normalized = value.trim().toLowerCase();
    const schemeEnd = normalized.indexOf('://');
    if (schemeEnd < 0 || (normalized.substring(0, schemeEnd) !== 'https' &&
      normalized.substring(0, schemeEnd) !== 'http')) {
      throw new Error('Cookie origin 格式不正确');
    }
    const authority = normalized.substring(schemeEnd + 3);
    if (authority.length === 0 || authority.includes('/') || authority.includes('?') ||
      authority.includes('#') || authority.includes(' ') || authority.includes('\t')) {
      throw new Error('Cookie origin 格式不正确');
    }
    return normalized;
  }

  private static requireCookieHeader(value: string): string {
    const normalized = value.trim();
    if (normalized.length > MAX_COOKIE_HEADER_LENGTH) {
      throw new Error(`Cookie 长度不能超过 ${MAX_COOKIE_HEADER_LENGTH}`);
    }
    if (normalized.includes('\r') || normalized.includes('\n')) {
      throw new Error('Cookie 包含非法字符');
    }
    return normalized;
  }
}
