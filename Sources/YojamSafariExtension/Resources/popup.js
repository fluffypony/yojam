import { previewInYojam } from "./yojam-bridge.js";

function getSourceSentinel() {
  if (typeof browser !== "undefined" && browser.runtime?.getBrowserInfo) {
    return "com.yojam.source.firefox-extension";
  }
  return "com.yojam.source.chrome-extension";
}

document.addEventListener("DOMContentLoaded", async () => {
  const urlDisplay = document.getElementById("url-display");
  const openBtn = document.getElementById("open-btn");
  const status = document.getElementById("status");

  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab) {
    urlDisplay.textContent = "No active tab";
    openBtn.disabled = true;
    return;
  }
  const url = tab.url;

  if (url && (url.startsWith("http://") || url.startsWith("https://"))) {
    urlDisplay.textContent = url;
    openBtn.disabled = false;
  } else {
    urlDisplay.textContent = "This page can't be routed through Yojam.";
    openBtn.disabled = true;
    return;
  }

  // Fetch and display preview
  const preview = await previewInYojam(url, getSourceSentinel());
  if (preview) {
    status.textContent = preview.summary;
  } else {
    status.textContent = "Preview unavailable";
  }

  openBtn.addEventListener("click", async () => {
    openBtn.disabled = true;
    status.textContent = "Routing...";
    try {
      await chrome.runtime.sendMessage({ action: "route", url });
      status.textContent = "Sent to Yojam";
      setTimeout(() => window.close(), 500);
    } catch (e) {
      status.textContent = "Failed: " + e.message;
      openBtn.disabled = false;
    }
  });
});
