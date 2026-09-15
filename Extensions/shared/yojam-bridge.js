/**
 * Yojam Bridge - Shared URL routing logic for browser extensions.
 * Builds yojam://route URLs and handles transport to the main app.
 */

/**
 * Build a yojam:// URL for routing a link to the main app.
 * @param {string} targetURL - The URL to route.
 * @param {string} sourceSentinel - The source app sentinel identifier.
 * @param {string} [container] - Optional Firefox container name to target.
 * @returns {string} The yojam:// URL.
 */
export function buildYojamURL(targetURL, sourceSentinel, container) {
  const params = new URLSearchParams({
    url: targetURL,
    source: sourceSentinel,
  });
  if (container) params.set("container", container);
  return `yojam://route?${params.toString()}`;
}

/**
 * Two-tier transport strategy:
 * 1. Try native messaging host (Chrome/Firefox only, no prompt, bidirectional).
 * 2. If native messaging is unavailable, open yojam:// in an active tab
 *    and leave it open so the user can complete the browser's confirmation.
 *
 * @param {string} targetURL - The URL to route.
 * @param {string} sourceSentinel - The source app sentinel identifier.
 * @returns {Promise<"native"|"protocol">} The transport used for the request.
 */
export async function sendToYojam(targetURL, sourceSentinel, container) {
  // Try native messaging first (Chrome/Firefox only)
  if (typeof chrome !== "undefined" && chrome.runtime?.sendNativeMessage) {
    let response;
    let receivedResponse = false;
    try {
      response = await chrome.runtime.sendNativeMessage("org.yojam.host", {
        action: "route",
        url: targetURL,
        source: sourceSentinel,
        container: container || undefined,
      });
      receivedResponse = true;
    } catch (_e) {
      // Native host not installed — fall through to yojam:// scheme.
      console.warn(
        "Yojam native host unavailable, falling back to yojam:// scheme"
      );
    }

    if (receivedResponse) {
      // A reply means the host handled the request. Retrying through another
      // transport could repeat an action or conceal the host's rejection.
      if (!response || typeof response !== "object" ||
          Array.isArray(response) || typeof response.ok !== "boolean" ||
          (response.error != null && typeof response.error !== "string") ||
          (response.ok && response.error != null)) {
        throw new Error("Yojam returned an invalid response.");
      }
      if (!response.ok) {
        throw new Error(
          typeof response.error === "string" && response.error.trim()
            ? response.error
            : "Yojam could not open this link."
        );
      }
      return "native";
    }
  }

  // Detect Safari for correct sentinel in fallback
  const isSafari =
    typeof chrome !== "undefined" &&
    chrome.runtime?.getURL("/")?.startsWith("safari-web-extension://");
  const effectiveSentinel = isSafari
    ? "com.yojam.source.safari-extension"
    : sourceSentinel;

  // Keep the confirmation visible until the user decides whether to continue.
  const url = buildYojamURL(targetURL, effectiveSentinel, container);
  await chrome.tabs.create({ url, active: true });
  return "protocol";
}

/**
 * Preview a URL's routing decision without opening it.
 * Returns a RouteDecisionPreview object, or null on failure.
 * @param {string} targetURL - The URL to preview.
 * @param {string} sourceSentinel - The source app sentinel identifier.
 * @returns {Promise<object|null>} The preview object or null.
 */
export async function previewInYojam(targetURL, sourceSentinel) {
  if (
    !(typeof chrome !== "undefined" && chrome.runtime?.sendNativeMessage)
  ) {
    return null;
  }
  try {
    const resp = await Promise.race([
      chrome.runtime.sendNativeMessage("org.yojam.host", {
        action: "preview",
        url: targetURL,
        source: sourceSentinel,
      }),
      new Promise((_, rej) =>
        setTimeout(() => rej(new Error("preview timeout")), 1500)
      ),
    ]);
    return resp?.ok === true && resp.preview &&
      typeof resp.preview === "object" && typeof resp.preview.summary === "string"
      ? resp.preview
      : null;
  } catch (_e) {
    return null;
  }
}
