import { sendToYojam, buildYojamURL } from "./yojam-bridge.js";

// Detect browser type for sentinel selection
function getSourceSentinel() {
  if (typeof browser !== "undefined" && browser.runtime?.getBrowserInfo) {
    return "com.yojam.source.firefox-extension";
  }
  return "com.yojam.source.chrome-extension";
}

// Feature-detect Safari (no webNavigation interception support)
const isSafari =
  typeof chrome !== "undefined" &&
  chrome.runtime?.getURL("/")?.startsWith("safari-web-extension://");

// ---- Always-Route Interception ----

let alwaysRoute = false;
const routedTabs = new Map(); // tabId -> expiry timestamp

// Load setting on startup
chrome.storage.local.get("alwaysRoute", (r) => {
  alwaysRoute = !!r.alwaysRoute;
});
chrome.runtime.onStartup.addListener(async () => {
  const r = await chrome.storage.local.get("alwaysRoute");
  alwaysRoute = !!r.alwaysRoute;
});

function isRoutedRecently(tabId) {
  const exp = routedTabs.get(tabId);
  if (!exp) return false;
  if (exp < Date.now()) {
    routedTabs.delete(tabId);
    return false;
  }
  return true;
}

// webNavigation interception (Chrome/Firefox only, not Safari)
if (!isSafari && chrome.webNavigation?.onBeforeNavigate) {
  chrome.webNavigation.onBeforeNavigate.addListener((d) => {
    if (!alwaysRoute) return;
    if (d.frameId !== 0) return; // top-frame only
    if (!/^https?:\/\//i.test(d.url)) return; // http(s) only
    if (d.url.startsWith("yojam://")) return;
    if (isRoutedRecently(d.tabId)) return; // loop guard

    routedTabs.set(d.tabId, Date.now() + 3000);
    const yojamURL = buildYojamURL(d.url, getSourceSentinel());
    chrome.tabs.update(d.tabId, { url: yojamURL });
  });
}

// ---- Context Menus ----

async function ensureContextMenus() {
  await chrome.contextMenus.removeAll();
  chrome.contextMenus.create({
    id: "open-link-in-yojam",
    title: "Open Link in Yojam",
    contexts: ["link"],
  });
  chrome.contextMenus.create({
    id: "open-page-in-yojam",
    title: "Open Page in Yojam",
    contexts: ["page"],
  });
}
chrome.runtime.onInstalled.addListener(ensureContextMenus);
chrome.runtime.onStartup.addListener(ensureContextMenus);

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  let url = null;
  if (info.menuItemId === "open-link-in-yojam" && info.linkUrl) {
    url = info.linkUrl;
  } else if (info.menuItemId === "open-page-in-yojam" && tab?.url) {
    url = tab.url;
  }

  if (url && (url.startsWith("http://") || url.startsWith("https://"))) {
    await sendToYojam(url, getSourceSentinel());
  }
});

// ---- Keyboard Shortcut ----

chrome.commands.onCommand.addListener(async (command) => {
  if (command === "open-in-yojam") {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tab?.url && (tab.url.startsWith("http://") || tab.url.startsWith("https://"))) {
      await sendToYojam(tab.url, getSourceSentinel());
    }
  }
});

// ---- Firefox Container Support (Firefox only) ----

// Open a URL in a specific contextualIdentity container. No-op outside Firefox.
async function openInContainer(url, containerName) {
  if (typeof browser === "undefined" || !browser.contextualIdentities) {
    return false;
  }
  try {
    const matches = await browser.contextualIdentities.query({ name: containerName });
    if (!matches || matches.length === 0) return false;
    await browser.tabs.create({ url, cookieStoreId: matches[0].cookieStoreId });
    return true;
  } catch (e) {
    return false;
  }
}

async function listContainers() {
  if (typeof browser === "undefined" || !browser.contextualIdentities) {
    return [];
  }
  try {
    const all = await browser.contextualIdentities.query({});
    return all.map((c) => ({ name: c.name, cookieStoreId: c.cookieStoreId, color: c.color }));
  } catch (e) {
    return [];
  }
}

// ---- Popup / Options Messages ----

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.action === "route" && message.url) {
    sendToYojam(message.url, getSourceSentinel(), message.container)
      .then(() => sendResponse({ ok: true }))
      .catch((e) => sendResponse({ ok: false, error: String(e) }));
    return true; // async response
  }
  if (message.action === "open_in_container" && message.url && message.container) {
    openInContainer(message.url, message.container)
      .then((ok) => sendResponse({ ok }))
      .catch((e) => sendResponse({ ok: false, error: String(e) }));
    return true;
  }
  if (message.action === "list_containers") {
    listContainers()
      .then((containers) => sendResponse({ ok: true, containers }))
      .catch((e) => sendResponse({ ok: false, error: String(e) }));
    return true;
  }
  if (message.action === "updateAlwaysRoute") {
    alwaysRoute = !!message.enabled;
  }
});
