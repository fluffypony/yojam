document.addEventListener("DOMContentLoaded", async () => {
  const toggle = document.getElementById("always-route");
  const safariNotice = document.getElementById("safari-notice");

  // Feature-detect Safari (no webNavigation interception)
  const isSafari =
    chrome.runtime?.getURL("/")?.startsWith("safari-web-extension://");
  if (isSafari || !chrome.webNavigation?.onBeforeNavigate) {
    toggle.disabled = true;
    safariNotice.style.display = "block";
    return;
  }

  const { alwaysRoute = false } = await chrome.storage.local.get("alwaysRoute");
  toggle.checked = alwaysRoute;
  toggle.addEventListener("change", async () => {
    await chrome.storage.local.set({ alwaysRoute: toggle.checked });
    chrome.runtime.sendMessage({
      action: "updateAlwaysRoute",
      enabled: toggle.checked,
    });
  });
});
