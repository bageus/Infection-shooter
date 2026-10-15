// Chrome DevTools Protocol over a pipe, using only Node built-ins.
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve, extname } from 'node:path';
import assert from 'node:assert/strict';

const directory = resolve(process.argv[2]);
const output = resolve(process.argv[3]);
const mime = { '.wasm': 'application/wasm', '.js': 'application/javascript', '.html': 'text/html', '.pck': 'application/octet-stream' };
const server = createServer(async (request, response) => {
  try {
    const path = new URL(request.url, 'http://localhost').pathname;
    assert(!path.includes('..'));
    const file = resolve(directory, '.' + (path === '/' ? '/index.html' : path));
    assert(file.startsWith(directory + '/'));
    response.setHeader('Content-Type', mime[extname(file)] || 'application/octet-stream');
    response.end(await readFile(file));
  } catch {
    response.writeHead(404);
    response.end();
  }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const chrome = spawn(process.env.CHROME || '/usr/bin/google-chrome', [
  '--headless', '--no-sandbox', '--remote-debugging-pipe', '--no-first-run',
  '--disable-dev-shm-usage', '--use-gl=angle', '--use-angle=swiftshader',
  '--enable-unsafe-swiftshader', '--no-startup-window',
  `--user-data-dir=${resolve(output + '-profile')}`,
], { stdio: ['ignore', 'pipe', 'pipe', 'pipe', 'pipe'] });
let nextId = 0;
let buffer = '';
const pending = new Map();
const consoleErrors = [];
chrome.stderr.on('data', chunk => process.stderr.write(chunk));
chrome.on('error', error => { for (const item of pending.values()) item.reject(error); });
chrome.stdio[4].on('data', chunk => {
  buffer += chunk.toString();
  let delimiter;
  while ((delimiter = buffer.indexOf('\0')) !== -1) {
    const packet = buffer.slice(0, delimiter);
    buffer = buffer.slice(delimiter + 1);
    if (!packet) continue;
    const message = JSON.parse(packet);
    if (message.id && pending.has(message.id)) {
      const item = pending.get(message.id);
      pending.delete(message.id);
      message.error ? item.reject(message.error) : item.resolve(message.result);
    }
    if (message.method === 'Runtime.exceptionThrown') consoleErrors.push(message.params.exceptionDetails);
    if (message.method === 'Runtime.consoleAPICalled') {
      const text = message.params.args.map(arg => arg.value ?? arg.description).join(' ');
      if (message.params.type === 'error' && /SCRIPT ERROR|SHADER ERROR|^ERROR:/.test(text)) consoleErrors.push(text);
      process.stdout.write(text + '\n');
    }
  }
});
function call(method, params = {}, sessionId) {
  const id = ++nextId;
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    chrome.stdio[3].write(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }) + '\0');
  });
}
const timeout = setTimeout(() => { console.error('Web skin probe timed out'); chrome.kill(); server.close(); process.exit(1); }, 90000);
try {
  const { targetId } = await call('Target.createTarget', { url: `http://127.0.0.1:${server.address().port}/` });
  const { sessionId } = await call('Target.attachToTarget', { targetId, flatten: true });
  await call('Runtime.enable', {}, sessionId);
  let probe;
  while (!probe) {
    const result = await call('Runtime.evaluate', { expression: 'window.skinProbeResult', returnByValue: true }, sessionId);
    probe = result.result.value;
    if (!probe) await new Promise(resolve => setTimeout(resolve, 250));
  }
  const gl = await call('Runtime.evaluate', { expression: `(()=>{const g=document.createElement('canvas').getContext('webgl2');return {maxArrayLayers:g.getParameter(g.MAX_ARRAY_TEXTURE_LAYERS),maxVertexUniformVectors:g.getParameter(g.MAX_VERTEX_UNIFORM_VECTORS),maxFragmentUniformVectors:g.getParameter(g.MAX_FRAGMENT_UNIFORM_VECTORS)}})()`, returnByValue: true }, sessionId);
  await writeFile(output + '.json', JSON.stringify({ probe, webgl2: gl.result.value, consoleErrors }, null, 2));
  const screenshot = await call('Page.captureScreenshot', { format: 'png' }, sessionId);
  await writeFile(output + '.png', Buffer.from(screenshot.data, 'base64'));
  assert.equal(probe.errors.length, 0, JSON.stringify(probe));
  assert.equal(consoleErrors.length, 0, JSON.stringify(consoleErrors));
  assert(probe.array_layers <= gl.result.value.maxArrayLayers);
  console.log('Web skin probe PASS', JSON.stringify(probe));
} finally {
  clearTimeout(timeout);
  chrome.kill();
  server.close();
}
