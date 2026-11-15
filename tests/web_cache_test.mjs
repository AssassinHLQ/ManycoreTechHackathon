import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const handlers = new Map();
const cached = new Map();
const writes = [];
let finishWrite;
const writePending = new Promise(resolve => { finishWrite = resolve; });
const cache = {
  match: async request => cached.get(typeof request === 'string' ? request : new URL(request.url).pathname),
  keys: async () => [new Request('https://game.test/index.pck'), new Request('https://game.test/index.wasm')],
  delete: async request => { writes.push(['delete', request.url]); return true; },
  put: async request => { writes.push(['put', request.url]); await writePending; },
};
vm.runInNewContext(fs.readFileSync(new URL('../web_mobile/sw.js', import.meta.url), 'utf8'), {
  self: {
    location: {origin: 'https://game.test'},
    addEventListener: (name, callback) => handlers.set(name, callback),
    clients: {claim: async () => {}},
    skipWaiting: () => {},
  },
  caches: {open: async () => cache, keys: async () => ['starward-web-v1'], delete: async () => true},
  fetch: async () => new Response('network asset'),
  Request, Response, Headers, URL, Promise, console,
});
function dispatch(path) {
  const event = {
    request: new Request('https://game.test' + path), tasks: [],
    respondWith(promise) { this.response = promise; },
    waitUntil(promise) { this.tasks.push(promise); },
  };
  handlers.get('fetch')(event);
  return event;
}
const pack = dispatch('/index.pck');
assert.equal(pack.response, undefined, 'large packs use normal HTTP loading without a second cache copy');
assert.equal(writes.length, 0);
const js = dispatch('/index.js');
let timeout;
try {
  const response = await Promise.race([js.response, new Promise((_, reject) => {
    timeout = setTimeout(() => reject(new Error('cache write blocked the engine script')), 2000);
  })]);
  assert.equal(await response.text(), 'network asset');
  assert.equal(js.tasks.length, 1, 'small assets update their offline cache in the background');
} finally {
  clearTimeout(timeout);
  finishWrite();
}
await Promise.all(js.tasks);
cached.set('/index.wasm', new Response('cached wasm'));
assert.equal(await (await dispatch('/index.wasm').response).text(), 'cached wasm');
cached.set('./index.wasm', new Response('cached wasm'));
const activation = {waitUntil(task) { this.task = task; }};
handlers.get('activate')(activation);
await activation.task;
assert(writes.some(([kind, path]) => kind === 'delete' && path.endsWith('/index.pck')));
assert(!writes.some(([kind, path]) => kind === 'delete' && path.endsWith('/index.wasm')));
console.log('WEB CACHE TEST COMPLETE: startup streaming, background caching and wasm reuse passed');
