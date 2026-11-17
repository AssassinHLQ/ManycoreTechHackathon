import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import {spawn} from 'node:child_process';

const directory = path.resolve(process.argv[2] || 'build/web');
const output = path.resolve(process.argv[3] || '_tools/_tmp/web_export');
const edge = process.env.WEB_TEST_BROWSER || path.join(process.env['ProgramFiles(x86)'] || '', 'Microsoft/Edge/Application/msedge.exe');
assert(fs.existsSync(edge), 'Set WEB_TEST_BROWSER to a Chromium browser executable');
const html = fs.readFileSync(path.join(directory, 'index.html'), 'utf8');
const config = JSON.parse(html.match(/const GODOT_CONFIG\s*=\s*(\{.*?\});/)[1]);
for (const [file, size] of Object.entries(config.fileSizes)) {
  assert.equal(fs.statSync(path.join(directory, file)).size, size, file + ' matches HTML size');
}
assert(html.includes('<!-- mobile-immersive -->'), 'mobile fullscreen integration is included');
const wasm = fs.openSync(path.join(directory, 'index.wasm'), 'r');
const magic = Buffer.alloc(8);
fs.readSync(wasm, magic, 0, 8, 0);
fs.closeSync(wasm);
assert.equal(magic.toString('hex'), '0061736d01000000');
const requests = [];
const server = http.createServer((request, response) => {
  const url = new URL(request.url, 'http://127.0.0.1');
  const file = path.resolve(directory, '.' + decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname));
  if (!file.startsWith(directory + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
    response.writeHead(404).end();
    requests.push({url: request.url, status: 404});
    return;
  }
  const types = {'.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream'};
  response.writeHead(200, {'Content-Type': types[path.extname(file)] || 'application/octet-stream', 'Content-Length': fs.statSync(file).size});
  requests.push({url: request.url, status: 200});
  fs.createReadStream(file).pipe(response);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const profile = fs.mkdtempSync(output + '_profile_');
const browser = spawn(edge, ['--headless=new', '--remote-debugging-port=0', '--user-data-dir=' + profile,
  '--no-first-run', '--no-default-browser-check', '--disable-extensions', '--disable-sync',
  '--window-size=1280,720', 'about:blank'], {windowsHide: true, stdio: 'ignore'});
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const messages = [];
const exceptions = [];
let socket;
let passed = false;
let result = {};
try {
  const portfile = path.join(profile, 'DevToolsActivePort');
  for (let i = 0; i < 150 && !fs.existsSync(portfile); i++) await delay(100);
  const port = fs.readFileSync(portfile, 'utf8').split('\n')[0];
  const tab = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, {method: 'PUT'})).json();
  socket = new WebSocket(tab.webSocketDebuggerUrl);
  await new Promise(resolve => socket.addEventListener('open', resolve, {once: true}));
  let sequence = 0;
  const pending = new Map();
  const call = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++sequence;
    const timer = setTimeout(() => {pending.delete(id); reject(new Error(method + ' timeout'));}, 30000);
    pending.set(id, {resolve, reject, timer});
    socket.send(JSON.stringify({id, method, params}));
  });
  socket.addEventListener('message', ({data}) => {
    const message = JSON.parse(data);
    if (message.id) {
      const item = pending.get(message.id);
      if (!item) return;
      pending.delete(message.id);
      clearTimeout(item.timer);
      if (message.error) item.reject(new Error(JSON.stringify(message.error)));
      else item.resolve(message.result);
    }
    if (message.method === 'Runtime.consoleAPICalled') {
      const line = message.params.args.map(arg => arg.value ?? arg.description ?? '').join(' ');
      messages.push(line);
      if (/BUILD|SCRIPT ERROR|^ERROR:/.test(line)) console.log(line);
    }
    if (message.method === 'Runtime.exceptionThrown') exceptions.push(message.params.exceptionDetails);
  });
  await call('Page.enable');
  await call('Runtime.enable');
  await call('Emulation.setDeviceMetricsOverride', {width: 1280, height: 720, deviceScaleFactor: 1, mobile: false});
  const started = Date.now();
  await call('Page.navigate', {url: `http://127.0.0.1:${server.address().port}/index.html`});
  while (Date.now() - started < 300000 && !messages.some(line => /\[BUILD\].*\u884c\u661f\u603b\u6570 20/.test(line))) {
    if (exceptions.length || messages.some(line => /^(SCRIPT ERROR:|ERROR:)/.test(line))) break;
    await delay(1000);
  }
  const ready = messages.some(line => /\[BUILD\].*\u884c\u661f\u603b\u6570 20/.test(line));
  await delay(2000);
  const screenshot = await call('Page.captureScreenshot', {format: 'png'});
  fs.writeFileSync(output + '_desktop.png', Buffer.from(screenshot.data, 'base64'));
  const evaluate = async expression => (await call('Runtime.evaluate', {expression, returnByValue: true})).result.value;
  const desktop = await evaluate(`(() => {const c = document.querySelector('canvas'); const g = c?.getContext('webgl2'); return {width: c?.width, height: c?.height, webgl2: !!g, contextLost: g?.isContextLost(), status: document.querySelector('#status-notice')?.textContent};})()`);
  await call('Emulation.setDeviceMetricsOverride', {width: 844, height: 390, deviceScaleFactor: 2, mobile: true});
  await delay(1500);
  const mobileShot = await call('Page.captureScreenshot', {format: 'png'});
  fs.writeFileSync(output + '_mobile.png', Buffer.from(mobileShot.data, 'base64'));
  const mobile = await evaluate(`(() => {const c = document.querySelector('canvas');return {width: c?.width, height: c?.height, viewportWidth: innerWidth, viewportHeight: innerHeight};})()`);
  const errors = messages.filter(line => /^(SCRIPT ERROR:|ERROR:)|WebGL.*(?:CONTEXT_LOST|context lost)/i.test(line));
  result = {ready, secondsToValidation: (Date.now() - started) / 1000, desktop, mobile, errors, exceptions, requests,
    scope: 'Release WebGL2 boot and resize smoke; mobile browser emulation is not Android device gameplay'};
  assert(ready, 'Web release builds all twenty planets');
  assert(desktop.webgl2 && !desktop.contextLost && desktop.width > 0 && desktop.height > 0, 'WebGL2 canvas is active');
  assert.equal(errors.length, 0, 'No Godot/WebGL errors');
  assert.equal(exceptions.length, 0, 'No browser exceptions');
  assert(!requests.some(item => item.status !== 200), 'All requested assets load');
  passed = true;
  console.log('WEB EXPORT TEST COMPLETE: desktop boot and mobile resize passed');
} finally {
  fs.writeFileSync(output + '_result.json', JSON.stringify({...result, passed, messages, exceptions, requests}, null, 2));
  socket?.close();
  if (browser.exitCode === null) {
    const closed = new Promise(resolve => browser.once('exit', resolve));
    if (process.platform === 'win32') {
      const killer = spawn('taskkill', ['/PID', String(browser.pid), '/T', '/F'], {windowsHide: true, stdio: 'ignore'});
      await new Promise(resolve => killer.once('exit', resolve));
    } else browser.kill('SIGTERM');
    await closed;
  }
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  fs.rmSync(profile, {recursive: true, force: true, maxRetries: 10, retryDelay: 250});
}
