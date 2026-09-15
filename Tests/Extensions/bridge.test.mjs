import assert from "node:assert/strict";
import { afterEach, beforeEach, test } from "node:test";
import { setTimeout as delay } from "node:timers/promises";
import { sendToYojam, previewInYojam } from "../../Extensions/shared/yojam-bridge.js";

const target = "https://example.com/a%20path?q=one&next=two";
const source = "com.yojam.source.chrome-extension";
let requests;
let tabs;
let removed;

beforeEach(() => {
  requests = [];
  tabs = [];
  removed = [];
  globalThis.chrome = {
    runtime: {
      getURL: path => `chrome-extension://test/${path}`,
      sendNativeMessage: async (host, request) => {
        requests.push({ host, request });
        return { ok: true };
      },
    },
    tabs: {
      create: async properties => {
        tabs.push(properties);
        return { id: 42, ...properties };
      },
      remove: async id => removed.push(id),
    },
  };
});

afterEach(() => { delete globalThis.chrome; });

test("native success sends the complete request without opening a browser tab", async () => {
  assert.equal(await sendToYojam(target, source, "Work & Personal"), "native");
  assert.deepEqual(requests, [{
    host: "org.yojam.host",
    request: { action: "route", url: target, source, container: "Work & Personal" },
  }]);
  assert.deepEqual(tabs, []);
});

test("native rejection preserves the error and never retries the action", async () => {
  chrome.runtime.sendNativeMessage = async () => ({ ok: false, error: "open failed (1)" });
  await assert.rejects(sendToYojam(target, source), { message: "open failed (1)" });
  assert.deepEqual(tabs, []);
});

test("native rejection without a message still fails without a fallback", async () => {
  chrome.runtime.sendNativeMessage = async () => ({ ok: false });
  await assert.rejects(sendToYojam(target, source), { message: "Yojam could not open this link." });
  assert.deepEqual(tabs, []);
});

test("malformed native replies fail without repeating the request", async () => {
  for (const reply of [undefined, null, [], "ok", {}, { ok: "true" },
    { ok: true, error: "failed" }, { ok: false, error: 5 }]) {
    chrome.runtime.sendNativeMessage = async () => reply;
    await assert.rejects(sendToYojam(target, source), { message: "Yojam returned an invalid response." });
  }
  assert.deepEqual(tabs, []);
});

test("transport failure leaves an active confirmation tab open", async () => {
  chrome.runtime.sendNativeMessage = async () => { throw new Error("Host not found"); };
  assert.equal(await sendToYojam(target, source, "Work & Personal"), "protocol");
  assert.equal(tabs.length, 1);
  assert.equal(tabs[0].active, true);
  const url = new URL(tabs[0].url);
  assert.equal(url.protocol, "yojam:");
  assert.equal(url.searchParams.get("url"), target);
  assert.equal(url.searchParams.get("source"), source);
  assert.equal(url.searchParams.get("container"), "Work & Personal");
  await delay(700);
  assert.deepEqual(removed, []);
});

test("Safari's protocol fallback keeps the Safari source", async () => {
  delete chrome.runtime.sendNativeMessage;
  chrome.runtime.getURL = path => `safari-web-extension://test/${path}`;
  assert.equal(await sendToYojam(target, source), "protocol");
  assert.equal(new URL(tabs[0].url).searchParams.get("source"), "com.yojam.source.safari-extension");
});

test("a failed protocol tab does not report success", async () => {
  delete chrome.runtime.sendNativeMessage;
  chrome.tabs.create = async () => { throw new Error("Cannot create a tab"); };
  await assert.rejects(sendToYojam(target, source), { message: "Cannot create a tab" });
});

test("preview accepts a real summary and rejects malformed replies", async () => {
  const preview = { summary: "Open in Firefox" };
  chrome.runtime.sendNativeMessage = async () => ({ ok: true, preview });
  assert.deepEqual(await previewInYojam(target, source), preview);
  for (const response of [{ ok: false }, { ok: "true", preview }, { ok: true },
    { ok: true, preview: "Open in Firefox" }, { ok: true, preview: { summary: 5 } }]) {
    chrome.runtime.sendNativeMessage = async () => response;
    assert.equal(await previewInYojam(target, source), null);
  }
});
