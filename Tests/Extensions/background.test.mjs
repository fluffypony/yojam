import assert from "node:assert/strict";
import { afterEach, beforeEach, test } from "node:test";

const event = () => ({ listeners: [], addListener(listener) { this.listeners.push(listener); } });
let resolveSettings;
let navigations;
let sequence = 0;

beforeEach(() => {
  navigations = [];
  globalThis.browser = { contextualIdentities: { query: async () => [] } };
  const settings = new Promise(resolve => { resolveSettings = resolve; });
  globalThis.chrome = {
    runtime: { getURL: path => `moz-extension://test/${path}`,
      onStartup: event(), onInstalled: event(), onMessage: event(),
      sendNativeMessage: async () => ({ ok: true }) },
    storage: { local: { get: () => settings }, onChanged: event() },
    webNavigation: { onBeforeNavigate: event(), onCommitted: event() },
    contextMenus: { onClicked: event(), removeAll: async () => {}, create() {} },
    commands: { onCommand: event() },
    tabs: {
      update: async (id, properties) => navigations.push({ id, ...properties }),
      query: async () => [],
    },
  };
});

afterEach(() => { delete globalThis.chrome; delete globalThis.browser; });

async function loadWorker() {
  const url = new URL("../../Extensions/shared/background.js", import.meta.url);
  await import(`${url}?test=${++sequence}`);
  return chrome.webNavigation?.onBeforeNavigate.listeners[0];
}

test("Firefox navigation waits for its saved Always Route setting", async () => {
  const navigate = await loadWorker();
  let finished = false;
  const pending = navigate({ frameId: 0, tabId: 5, url: "https://example.com/work" })
    .then(() => { finished = true; });
  await Promise.resolve();
  assert.equal(finished, false);
  resolveSettings({ alwaysRoute: true });
  await pending;
  assert.equal(navigations.length, 1);
  assert.equal(new URL(navigations[0].url).searchParams.get("url"), "https://example.com/work");
});

test("a saved disabled setting leaves the navigation alone", async () => {
  const navigate = await loadWorker();
  const pending = navigate({ frameId: 0, tabId: 5, url: "https://example.com/" });
  resolveSettings({ alwaysRoute: false });
  await pending;
  assert.deepEqual(navigations, []);
});

test("settings changes update routing without a separate runtime message", async () => {
  const navigate = await loadWorker();
  resolveSettings({ alwaysRoute: false });
  await navigate({ frameId: 0, tabId: 5, url: "https://example.com/" });
  chrome.storage.onChanged.listeners[0]({ alwaysRoute: { newValue: true } }, "local");
  await navigate({ frameId: 0, tabId: 6, url: "https://example.com/" });
  assert.equal(navigations.length, 1);
  chrome.storage.onChanged.listeners[0]({ alwaysRoute: { newValue: false } }, "local");
  await navigate({ frameId: 0, tabId: 7, url: "https://example.com/" });
  assert.equal(navigations.length, 1);
});

test("routing failure reaches the popup as a failure", async () => {
  await loadWorker();
  resolveSettings({ alwaysRoute: false });
  chrome.runtime.sendNativeMessage = async () => ({ ok: false, error: "Invalid URL" });
  const response = await new Promise(resolve => {
    const asyncResponse = chrome.runtime.onMessage.listeners[0](
      { action: "route", url: "https://example.com/" }, {}, resolve);
    assert.equal(asyncResponse, true);
  });
  assert.deepEqual(response, { ok: false, error: "Invalid URL" });
});

test("the worker owns native preview and derives its source", async () => {
  chrome.runtime.getURL = path => `chrome-extension://test/${path}`;
  delete globalThis.browser;
  delete chrome.webNavigation;
  delete chrome.storage;
  await loadWorker();
  const preview = { summary: "Would show picker (preselected: Safari)" };
  chrome.runtime.sendNativeMessage = async (host, request) => {
    assert.equal(host, "org.yojam.host");
    assert.deepEqual(request, {
      action: "preview", url: "https://example.com/", source: "com.yojam.source.chrome-extension",
    });
    return { ok: true, preview };
  };
  const response = await new Promise(resolve => {
    assert.equal(chrome.runtime.onMessage.listeners[0](
      { action: "preview", url: "https://example.com/", source: "caller-supplied-source" }, {}, resolve), true);
  });
  assert.deepEqual(response, { ok: true, preview });
});

test("a rejected native preview reaches the popup without claiming success", async () => {
  await loadWorker();
  resolveSettings({ alwaysRoute: false });
  chrome.runtime.sendNativeMessage = async () => ({ ok: false, error: "Cannot load config" });
  const response = await new Promise(resolve => {
    chrome.runtime.onMessage.listeners[0](
      { action: "preview", url: "https://example.com/" }, {}, resolve);
  });
  assert.deepEqual(response, { ok: false, preview: null });
});

test("the Safari worker supplies the Safari source for native preview", async () => {
  chrome.runtime.getURL = path => `safari-web-extension://test/${path}`;
  delete globalThis.browser;
  await loadWorker();
  chrome.runtime.sendNativeMessage = async (_host, request) => {
    assert.equal(request.source, "com.yojam.source.safari-extension");
    return { ok: true, preview: { summary: "Would show picker" } };
  };
  const response = await new Promise(resolve => {
    chrome.runtime.onMessage.listeners[0](
      { action: "preview", url: "https://example.com/" }, {}, resolve);
  });
  assert.equal(response.ok, true);
});

test("Chromium ignores saved automatic routing and registers no navigation listener", async () => {
  chrome.runtime.getURL = path => `chrome-extension://test/${path}`;
  delete globalThis.browser;
  chrome.storage.local.get = () => { throw new Error("Chrome must not read automatic routing settings"); };
  await loadWorker();
  assert.equal(chrome.webNavigation.onBeforeNavigate.listeners.length, 0);
  assert.equal(chrome.webNavigation.onCommitted.listeners.length, 0);
  assert.equal(chrome.storage.onChanged.listeners.length, 0);
});

test("Chromium explicit routing works without navigation or storage permissions", async () => {
  chrome.runtime.getURL = path => `chrome-extension://test/${path}`;
  delete globalThis.browser;
  delete chrome.webNavigation;
  delete chrome.storage;
  await loadWorker();
  const response = await new Promise(resolve => {
    chrome.runtime.onMessage.listeners[0](
      { action: "route", url: "https://example.com/" }, {}, resolve);
  });
  assert.deepEqual(response, { ok: true, transport: "native" });
});

test("container APIs keep Orion interception without Firefox manifest metadata", async () => {
  chrome.runtime.getURL = path => `chrome-extension://test/${path}`;
  const navigate = await loadWorker();
  resolveSettings({ alwaysRoute: false });
  await navigate({ frameId: 0, tabId: 5,
    url: "https://yojam-container.invalid/open?c=Missing&u=https%3A%2F%2Fexample.com" });
  assert.deepEqual(navigations, [{ id: 5, url: "chrome-extension://test/container-error.html" }]);
});
