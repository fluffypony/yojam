document.addEventListener("DOMContentLoaded", async () => {
  const urlDisplay = document.getElementById("url-display");
  const openBtn = document.getElementById("open-btn");
  const status = document.getElementById("status");

  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  const url = tab?.url;

  if (url && (url.startsWith("http://") || url.startsWith("https://"))) {
    urlDisplay.textContent = url;
    openBtn.disabled = false;
  } else {
    urlDisplay.textContent = "This page can't be routed through Yojam.";
    openBtn.disabled = true;
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
