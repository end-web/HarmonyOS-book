// Compatibility patch: independent engine 1eb86df predates legado-harmony 67e5f2d.
// Keep the existing bounded wait behavior until upstream includes the fix.
module.exports = function preserveWebWait(text) {
  if (text.includes('private matchesWebJs(') && text.includes('Math.min(120,')) return text;
  const beforeFinish = "    this.finishActive(this.success(finalUrl, value && value !== 'undefined' && value !== 'null' ? value : html));";
  const beforeRetry = `  private shouldRetryWebJs(task: WebBookFetchTask, value: string): boolean {
    const pattern = String(task.request.webJsAcceptPattern || '');
    const maxAttempts = Math.max(1, Math.min(20, Math.floor(task.request.webJsMaxAttempts || 1)));
    if (!pattern || task.webJsAttempts >= maxAttempts) return false;
    try {
      return !new RegExp(pattern, 'i').test(value);`;
  if (text.split(beforeFinish).length !== 2 || text.split(beforeRetry).length !== 2) {
    throw new Error('WebBookFetchRuntime changed; review the bounded-web-wait compatibility patch before syncing.');
  }
  return text.replace(beforeFinish, `    if (!this.matchesWebJs(task, value)) {
      this.finishActive(this.failure(finalUrl, '网页等待条件未满足，未取得可用内容'));
      return;
    }
${beforeFinish}`).replace(beforeRetry, `  private shouldRetryWebJs(task: WebBookFetchTask, value: string): boolean {
    // Honor the declared wait duration; the request timer remains the hard limit.
    const maxAttempts = Math.max(1, Math.min(120, Math.floor(task.request.webJsMaxAttempts || 1)));
    return task.webJsAttempts < maxAttempts && !this.matchesWebJs(task, value);
  }

  private matchesWebJs(task: WebBookFetchTask, value: string): boolean {
    const pattern = String(task.request.webJsAcceptPattern || '');
    if (!pattern) return true;
    try {
      return new RegExp(pattern, 'i').test(value);`);
};
