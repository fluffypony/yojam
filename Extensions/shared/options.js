document.addEventListener("DOMContentLoaded", async () => {
  // Feature-detect Safari (no webNavigation interception)
  const isSafari =
    chrome.runtime?.getURL("/")?.startsWith("safari-web-extension://");
  const supportsContainers = typeof browser !== "undefined" && !!browser.contextualIdentities;
  // Chrome exposes only explicit routing; Firefox and Orion expose container APIs.
  if (!supportsContainers && !isSafari) return;

  document.getElementById("automatic-routing").hidden = false;
  const toggle = document.getElementById("always-route");
  const safariNotice = document.getElementById("safari-notice");
  if (isSafari || !chrome.webNavigation?.onBeforeNavigate) {
    toggle.disabled = true;
    safariNotice.style.display = "block";
    return;
  }

  const { alwaysRoute = false } = await chrome.storage.local.get("alwaysRoute");
  toggle.checked = alwaysRoute;
  toggle.addEventListener("change", async () => {
    await chrome.storage.local.set({ alwaysRoute: toggle.checked });
  });
});
