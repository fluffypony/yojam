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

  openBtn.addEventListener("click", async () => {
    openBtn.disabled = true;
    status.textContent = "Routing...";
    try {
      const response = await chrome.runtime.sendMessage({ action: "route", url });
      if (response?.ok !== true ||
          !["native", "protocol"].includes(response.transport)) {
        throw new Error(response?.error || "Yojam returned an invalid response.");
      }
      if (response.transport === "native") {
        status.textContent = "Sent to Yojam";
        setTimeout(() => window.close(), 500);
      } else {
        status.textContent = "Confirm the request in your browser to open Yojam.";
      }
    } catch (e) {
      status.textContent = "Failed: " + e.message;
      openBtn.disabled = false;
    }
  });

  // A slow preview must not delay the Open button or overwrite its result.
  let preview;
  try {
    const response = await chrome.runtime.sendMessage({ action: "preview", url });
    if (response?.ok === true) preview = response.preview;
  } catch (_) {
    // Routing remains available when the preview request cannot complete.
  }
  if (!openBtn.disabled && !status.textContent) {
    status.textContent = preview?.summary || "Preview unavailable";
  }
});
