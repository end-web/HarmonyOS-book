export enum TingYouRetryAction {
  FAIL = 0,
  RETRY_REQUEST = 1,
  REFRESH_TOKEN = 2
}

export class TingYouRequestPolicy {
  static forHttpStatus(statusCode: number, attempt: number): TingYouRetryAction {
    if (attempt > 0) return TingYouRetryAction.FAIL;
    if (statusCode === 401) return TingYouRetryAction.REFRESH_TOKEN;
    if (statusCode >= 500 && statusCode < 600) return TingYouRetryAction.RETRY_REQUEST;
    return TingYouRetryAction.FAIL;
  }

  static shouldRetryNetworkError(attempt: number): boolean {
    return attempt === 0;
  }
}
