// Shared testing types for erni-ki

export interface MockRequest<
  TBody = Record<string, unknown>,
  TQuery = Record<string, string | string[] | undefined>,
  TParams = Record<string, string>,
> {
  headers: Record<string, string>;
  query: TQuery;
  params: TParams;
  body: TBody;
  cookies: Record<string, string>;
  method: string;
  url: string;
}

export interface MockResponse<TBody = unknown> {
  statusCode: number;
  status: (code: number) => MockResponse<TBody>;
  json: (payload: TBody) => MockResponse<TBody>;
  send: (payload: TBody) => MockResponse<TBody>;
  cookie: (name: string, value: string, options?: Record<string, unknown>) => MockResponse<TBody>;
  header: (name: string, value: string | number | readonly string[]) => MockResponse<TBody>;
  redirect: (url: string, status?: number) => MockResponse<TBody>;
  end: () => MockResponse<TBody>;
}

export type WaitForPredicate = () => boolean;

export interface TestUtils {
  createMockRequest: <
    TBody = Record<string, unknown>,
    TQuery = Record<string, string | string[] | undefined>,
    TParams = Record<string, string>,
  >(
    options?: Partial<MockRequest<TBody, TQuery, TParams>>
  ) => MockRequest<TBody, TQuery, TParams>;
  createMockResponse: <TBody = unknown>(
    options?: Partial<MockResponse<TBody>>
  ) => MockResponse<TBody>;
  waitFor: (fn: WaitForPredicate, timeout?: number) => Promise<void>;
  sleep: (ms: number) => Promise<void>;
}

export {};
