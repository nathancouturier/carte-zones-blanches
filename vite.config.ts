import { defineConfig } from 'vitest/config';
import { noscriptMessages } from './src/i18n/noscript';
import { offlineShell } from './src/offline/shell';

// Le site est servi par GitHub Pages sous /carte-zones-blanches/.
export default defineConfig({
  base: '/carte-zones-blanches/',
  // Message <noscript> de index.html dans chaque langue ; liste versionnée des fichiers
  // du site écrite dans dist/sw.js (mode hors ligne).
  plugins: [noscriptMessages(), offlineShell()],
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
