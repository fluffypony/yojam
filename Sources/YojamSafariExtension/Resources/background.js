import { sendToYojam } from "./yojam-bridge.js";

// Detect browser type for sentinel selection
function getSourceSentinel() {
  // Safari extension always uses the Safari sentinel
  return "com.yojam.source.safari-extension";
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

// ---- Popup Messages ----

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.action === "route" && message.url) {
    sendToYojam(message.url, getSourceSentinel())
      .then(() => sendResponse({ ok: true }))
      .catch((e) => sendResponse({ ok: false, error: String(e) }));
    return true; // async response
  }
});
