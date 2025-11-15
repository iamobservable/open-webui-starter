import { vi } from 'vitest';

import type { MockRequest, MockResponse, TestUtils } from '../../types/testing';

const POLL_INTERVAL_MS = 10;

const createMockRequest = <
  TBody = Record<string, unknown>,
  TQuery = Record<string, string | string[] | undefined>,
  TParams = Record<string, string>,
>(
  options: Partial<MockRequest<TBody, TQuery, TParams>> = {}
): MockRequest<TBody, TQuery, TParams> => ({
  headers: {},
  query: {} as TQuery,
  params: {} as TParams,
  body: {} as TBody,
  cookies: {},
  method: 'GET',
  url: '/',
  ...options,
});

const createChainableStub = <TArgs extends unknown[], TBody>(response: MockResponse<TBody>) =>
  vi.fn<(..._args: TArgs) => MockResponse<TBody>>().mockImplementation(() => response);

const createMockResponse = <TBody = unknown>(
  options: Partial<MockResponse<TBody>> = {}
): MockResponse<TBody> => {
  const response = {
    statusCode: options.statusCode ?? 200,
    status: vi.fn<(code: number) => MockResponse<TBody>>().mockImplementation(code => {
      response.statusCode = code;
      return response;
    }),
    json: vi.fn(),
    send: vi.fn(),
    cookie: vi.fn(),
    header: vi.fn(),
    redirect: vi.fn(),
    end: vi.fn(),
  } as MockResponse<TBody>;

  response.json = createChainableStub<[TBody], TBody>(response);
  response.send = createChainableStub<[TBody], TBody>(response);
  response.cookie = createChainableStub<[string, string, Record<string, unknown>?], TBody>(
    response
  );
  response.header = createChainableStub<[string, string | number | readonly string[]], TBody>(
    response
  );
  response.redirect = vi
    .fn<(url: string, status?: number) => MockResponse<TBody>>()
    .mockImplementation(() => response);
  response.end = createChainableStub<[], TBody>(response);

  return Object.assign(response, options);
};

const sleep: TestUtils['sleep'] = ms => new Promise(resolve => setTimeout(resolve, ms));

const waitFor: TestUtils['waitFor'] = async (fn, timeout = 5000) => {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    if (fn()) return;
    await sleep(POLL_INTERVAL_MS);
  }
  throw new Error(`Timeout waiting for condition after ${timeout}ms`);
};

const testUtils: TestUtils = {
  createMockRequest,
  createMockResponse,
  waitFor,
  sleep,
};

export { createMockRequest, createMockResponse, waitFor, sleep };
export type { MockRequest, MockResponse, TestUtils, WaitForPredicate } from '../../types/testing';
export default testUtils;
