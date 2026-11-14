import { defineConfig } from 'vitest/config';
import { offlineShell } from './src/offline/shell';

// Le site est servi par GitHub Pages sous /carte-zones-blanches/.
export default defineConfig({
  base: '/carte-zones-blanches/',
  // Écrit dans dist/sw.js la liste versionnée des fichiers du site (mode hors ligne).
  plugins: [offlineShell()],
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
