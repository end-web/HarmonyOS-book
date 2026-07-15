interface ReaderEnvelope<T> {
  isSuccess?: boolean;
  errorMsg?: string;
  data?: T;
}

export class ReaderClient {
  constructor(private readonly baseUrl: string) {}

  async health(): Promise<Record<string, unknown>> {
    return await this.request<Record<string, unknown>>('/reader3/getSystemInfo');
  }

  async post<T>(pathname: string, body: Record<string, unknown>): Promise<T> {
    return await this.request<T>(pathname, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify(body)
    });
  }

  private async request<T>(pathname: string, init?: RequestInit): Promise<T> {
    const response = await fetch(new URL(pathname, this.baseUrl), {
      ...init,
      signal: AbortSignal.timeout(30000)
    });
    if (!response.ok) throw new Error(`READER_HTTP_${response.status}`);
    const envelope = await response.json() as ReaderEnvelope<T>;
    if (envelope.isSuccess === false || envelope.errorMsg) {
      throw new Error(`READER_ERROR:${envelope.errorMsg || 'UNKNOWN'}`);
    }
    if (envelope.data === undefined) throw new Error('READER_EMPTY_DATA');
    return envelope.data;
  }
}
