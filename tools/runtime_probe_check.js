#!/usr/bin/env node
// Integration harness for the JavaScript injected into the headless WebView.
// It runs the exact bootstrap string from runtime_probe.dart against a minimal
// DOM, so an error-capture regression fails CI without needing an emulator.
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');

const root = path.resolve(__dirname, '..');
const dart = fs.readFileSync(
  path.join(root, 'src/container_app/lib/services/runtime_probe.dart'), 'utf8');
const match = dart.match(/static const String bootstrap = '''([\s\S]*?)''';/);
if (!match) {
  console.error('Could not find RuntimeProbe.bootstrap in runtime_probe.dart');
  process.exit(1);
}
const bootstrap = match[1]
  .replace(/^\s*<script>/, '')
  .replace(/<\/script>\s*$/, '');

function environment(body) {
  const onWindow = {};
  const onDocument = {};
  const timers = [];
  const logged = [];
  const document = {
    body,
    addEventListener(type, fn) { (onDocument[type] = onDocument[type] || []).push(fn); },
    querySelectorAll(selector) {
      if (selector.includes('canvas') || selector.includes('svg')) return body.visuals || [];
      return body.controls || [];
    },
  };
  const window = {
    addEventListener(type, fn) { (onWindow[type] = onWindow[type] || []).push(fn); },
  };
  const consoleMock = {
    error(...args) { logged.push(args.join(' ')); },
  };
  const sandbox = {
    window, document, console: consoleMock,
    setTimeout(fn) { timers.push(fn); },
    Array, String, Number, Math, Date, JSON,
  };
  vm.runInNewContext(bootstrap, sandbox, { filename: 'runtime_probe.js' });
  return {
    window, onWindow, onDocument, timers, logged, console: consoleMock,
    fire(type, event) { for (const fn of onWindow[type] || []) fn(event); },
    fireDocument(type, event) { for (const fn of onDocument[type] || []) fn(event); },
    finish() { for (const fn of timers) fn(); },
  };
}

const body = {
  innerText: 'Budget $120.00', children: [{}, {}],
  controls: [{}, {}, {}], visuals: [],
};
const env = environment(body);
const runtime = env.window.__applixRuntime;
assert(runtime, 'probe did not install window.__applixRuntime');
assert.strictEqual(runtime.ready, false);

env.fire('error', { message: 'TypeError: app is not defined', lineno: 12, colno: 4, filename: 'index.html' });
env.fire('unhandledrejection', { reason: new Error('fetch failed') });
env.console.error('manual console failure');
env.fire('load', {});
env.fireDocument('DOMContentLoaded', {});
env.finish();

assert.strictEqual(runtime.ready, true, 'probe did not become ready');
assert.strictEqual(runtime.loaded, true, 'load event not recorded');
assert.strictEqual(runtime.domReady, true, 'DOMContentLoaded not recorded');
assert(runtime.errors.some((e) => e.includes('TypeError: app is not defined')), 'window error was not captured');
assert(runtime.errors.some((e) => e.includes('Unhandled rejection')), 'unhandled rejection was not captured');
assert(runtime.errors.some((e) => e.includes('manual console failure')), 'console.error was not captured');
assert.strictEqual(runtime.textLength, body.innerText.length);
assert.strictEqual(runtime.bodyChildren, body.children.length);
assert.strictEqual(runtime.interactive, body.controls.length);

const blank = environment({ innerText: '', children: [], controls: [], visuals: [] });
blank.finish();
assert.strictEqual(blank.window.__applixRuntime.ready, true);
assert.strictEqual(blank.window.__applixRuntime.textLength, 0);
assert.strictEqual(blank.window.__applixRuntime.bodyChildren, 0);

console.log('Runtime probe harness passed: errors, rejections, console.error and blank screen.');
