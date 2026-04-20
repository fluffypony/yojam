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
 * 2. Fall back to opening a throwaway tab pointed at yojam:// (triggers
 *    the protocol-handler prompt on first use, closes automatically).
 *
 * @param {string} targetURL - The URL to route.
 * @param {string} sourceSentinel - The source app sentinel identifier.
 */
export async function sendToYojam(targetURL, sourceSentinel, container) {
  // Try native messaging first (Chrome/Firefox only)
  if (typeof chrome !== "undefined" && chrome.runtime?.sendNativeMessage) {
    try {
      await chrome.runtime.sendNativeMessage("org.yojam.host", {
        action: "route",
        url: targetURL,
        source: sourceSentinel,
        container: container || undefined,
      });
      return;
    } catch (_e) {
      // Native host not installed — fall through to yojam:// scheme.
      console.warn(
        "Yojam native host unavailable, falling back to yojam:// scheme"
      );
    }
  }

  // Detect Safari for correct sentinel in fallback
  const isSafari =
    typeof chrome !== "undefined" &&
    chrome.runtime?.getURL("/")?.startsWith("safari-web-extension://");
  const effectiveSentinel = isSafari
    ? "com.yojam.source.safari-extension"
    : sourceSentinel;

  // Fall back to opening a yojam:// URL in a throwaway tab.
  const url = buildYojamURL(targetURL, effectiveSentinel, container);
  const tab = await chrome.tabs.create({ url, active: false });
  setTimeout(() => chrome.tabs.remove(tab.id).catch(() => {}), 600);
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
    return resp?.ok ? resp.preview : null;
  } catch (_e) {
    return null;
  }
}
