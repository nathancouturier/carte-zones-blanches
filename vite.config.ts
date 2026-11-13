import { defineConfig } from 'vitest/config';

// Le site est servi par GitHub Pages sous /carte-zones-blanches/.
export default defineConfig({
  base: '/carte-zones-blanches/',
  build: {
    target: 'es2022',
    sourcemap: true,
    chunkSizeWarningLimit: 1500,
  },
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
  },
});
