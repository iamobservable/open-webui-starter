// Глобальные типы для проекта erni-ki

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

  // Тестовые утилиты
  var testUtils: {
    createMockRequest: (options?: any) => any;
    createMockResponse: (options?: any) => any;
    waitFor: (fn: () => boolean, timeout?: number) => Promise<void>;
    sleep: (ms: number) => Promise<void>;
  };
}

export {};
