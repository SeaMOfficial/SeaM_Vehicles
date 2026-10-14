import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

export default defineConfig({
  base: './', plugins: [svelte()],
  build: { outDir: '../html', emptyOutDir: true, target: 'es2020', sourcemap: false }
});
