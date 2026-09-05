import { url, util } from '@kit.ArkTS';
import { LocalRuleRequestPlan } from './LocalRuleRuntimeTypes';

/** Declarative request sessions operate only on the current source and destination. */
export class LocalRuleRequestSession {
  static apply(plan: LocalRuleRequestPlan): string {
    const config = plan.session;
    if (Object.keys(config).length === 0) return '';
    const destination = new url.URL(plan.url);
    const cookies: Record<string, string> = {};
    let cookieKey = 'Cookie';
    let hasReferer = false;
    for (const key of Object.keys(plan.headers)) {
      if (key.toLowerCase() === 'referer') hasReferer = true;
      if (key.toLowerCase() !== 'cookie') continue;
      cookieKey = key;
      for (const part of plan.headers[key].split(';')) {
        const separator = part.indexOf('=');
        if (separator > 0) cookies[part.substring(0, separator).trim()] = part.substring(separator + 1).trim();
      }
    }
    const queryCookies = LocalRuleRequestSession.names(config['queryCookies']);
    let changed = false;
    for (const name of Object.keys(queryCookies)) {
      const value = destination.searchParams.get(queryCookies[name] || name);
      if (value && LocalRuleRequestSession.validValue(value)) { cookies[name] = value; changed = true; }
    }
    const generated = LocalRuleRequestSession.names(config['generatedCookies']);
    for (const name of Object.keys(generated)) {
      if (cookies[name]) continue;
      const value = LocalRuleRequestSession.expand(generated[name], destination);
      if (value && LocalRuleRequestSession.validValue(value)) { cookies[name] = value; changed = true; }
    }
    if (!hasReferer && config['referer']) {
      const rule = String(config['referer']);
      const referer = rule.toLowerCase() === 'origin' ? destination.origin + '/'
        : rule.toLowerCase() === 'request' ? plan.url : LocalRuleRequestSession.expand(rule, destination);
      if (new RegExp('^https?://', 'i').test(referer) && !new RegExp('[\\r\\n]').test(referer)) plan.headers['Referer'] = referer;
    }
    if (!changed) return '';
    const header = Object.keys(cookies).map((name: string): string => `${name}=${cookies[name]}`).join('; ');
    plan.headers[cookieKey] = header;
    return header;
  }

  private static names(value: Object | undefined): Record<string, string> {
    const result: Record<string, string> = {};
    if (value === undefined || value === null) return result;
    if (typeof value === 'string' || Array.isArray(value)) {
      const names: string[] = typeof value === 'string' ? value.split(',') : JSON.parse(JSON.stringify(value));
      for (const name of names) {
        const key = String(name).trim();
        if (LocalRuleRequestSession.validName(key)) result[key] = key;
      }
    } else if (typeof value === 'object') {
      const fields: Record<string, Object> = JSON.parse(JSON.stringify(value));
      for (const name of Object.keys(fields)) {
        if (LocalRuleRequestSession.validName(name) && typeof fields[name] === 'string') result[name] = String(fields[name]);
      }
    }
    return result;
  }

  private static validName(value: string): boolean { return new RegExp('^[A-Za-z0-9_.-]{1,128}$').test(value); }
  private static validValue(value: string): boolean { return value.length <= 4096 && !new RegExp('[;\\r\\n\\x00]').test(value); }

  private static expand(template: string, destination: url.URL): string {
    const timestamp = String(Date.now());
    const random = String(Math.floor(Math.random() * 1000000000));
    const uuid = util.generateRandomUUID(true);
    if (template === '@uuid') return uuid;
    if (template === '@random') return random;
    if (template === '@timestamp_random') return timestamp + '_' + random;
    return template.split('{{timestamp}}').join(timestamp).split('{{random}}').join(random)
      .split('{{uuid}}').join(uuid).split('{{origin}}').join(destination.origin + '/').split('{{url}}').join(destination.href);
  }
}
