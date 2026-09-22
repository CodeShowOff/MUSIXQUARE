import { defineConfig, type UserConfig } from 'vite';
import { resolve } from 'path';

export const LEGACY_APP_BROWSER_TARGET = 'chrome79';

export function createViteConfig(): UserConfig {
  return {
    root: '.',
    publicDir: 'public',
    resolve: {
      alias: {
        '@': resolve(import.meta.dirname, 'src'),
      },
    },
    build: {
      outDir: 'dist',
      target: LEGACY_APP_BROWSER_TARGET,
      cssTarget: LEGACY_APP_BROWSER_TARGET,
      sourcemap: false,
      chunkSizeWarningLimit: 1000,
      rollupOptions: {
        input: {
          main: resolve(import.meta.dirname, 'index.html'),
        },
      },
    },
    server: {
      port: 3000,
      open: true,
      allowedHosts: ['localhost', '.localhost', '.musixquare.com'],
    },
    worker: {
      format: 'es',
    },
  };
}

export default defineConfig(() => {
  return createViteConfig();
});
