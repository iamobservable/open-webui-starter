// Global types for the erni-ki project

import type { TestUtils } from './testing';

declare global {
  namespace NodeJS {
    interface ProcessEnv {
      NODE_ENV: 'development' | 'production' | 'test';
      JWT_SECRET?: string;
      WEBUI_SECRET_KEY?: string;
      DATABASE_URL?: string;
      REDIS_URL?: string;
    }
  }

  var testUtils: TestUtils;
}

export {};
