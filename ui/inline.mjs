import fs from 'node:fs';
import path from 'node:path';

const dir = path.resolve('../html');
const file = path.join(dir, 'index.html');
let html = fs.readFileSync(file, 'utf8');
html = html.replace(/<link rel="stylesheet"[^>]+href="\.\/assets\/([^"]+)"[^>]*>/g, (_, name) =>
  `<style>${fs.readFileSync(path.join(dir, 'assets', name), 'utf8').replaceAll('</style', '<\\/style')}</style>`);
let found = false;
let embedded = '';
html = html.replace(/<script type="module"[^>]+src="\.\/assets\/([^"]+)"[^>]*><\/script>/g, (_, name) => {
  found = true;
  embedded = fs.readFileSync(path.join(dir, 'assets', name), 'utf8').replaceAll('</script', '<\\/script');
  return '';
});
if (!found || /\.\/assets\//.test(html)) throw new Error('Could not inline the UI assets.');
html = html.replace('</body>', `<script>${embedded}</script></body>`);
fs.writeFileSync(file, html);
fs.rmSync(path.join(dir, 'assets'), { recursive: true, force: true });
