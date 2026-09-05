export class LocalRuleScriptState {
  variable: string = '';
  definitionVariable: string = '';
  values: Record<string, string> = {};
  loginInfo: string = '';
  loginHeader: string = '';

  static parse(json: string, defaultVariable: string | undefined = undefined): LocalRuleScriptState {
    const state = new LocalRuleScriptState();
    state.variable = defaultVariable ?? '';
    state.definitionVariable = defaultVariable ?? '';
    if (json.length === 0) return state;
    const record: Record<string, Object> = JSON.parse(json);
    if (typeof record['variable'] === 'string') state.variable = String(record['variable']);
    state.definitionVariable = String(record['definitionVariable'] ?? defaultVariable ?? '');
    if (defaultVariable !== undefined && state.definitionVariable !== defaultVariable) {
      state.variable = defaultVariable;
      state.definitionVariable = defaultVariable;
    }
    if (typeof record['loginInfo'] === 'string') state.loginInfo = String(record['loginInfo']);
    if (typeof record['loginHeader'] === 'string') state.loginHeader = String(record['loginHeader']);
    const rawValues = record['values'];
    if (rawValues !== undefined && rawValues !== null && typeof rawValues === 'object' && !Array.isArray(rawValues)) {
      const values: Record<string, Object> = JSON.parse(JSON.stringify(rawValues));
      for (const key of Object.keys(values)) {
        if (typeof values[key] === 'string') state.values[key] = String(values[key]);
      }
    }
    return state;
  }
}
