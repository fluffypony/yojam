/**
 * Yojam Bridge - Shared URL routing logic for browser extensions.
 * Builds yojam://route URLs and handles transport to the main app.
 */

/**
 * Build a yojam:// URL for routing a link to the main app.
 * @param {string} targetURL - The URL to route.
 * @param {string} sourceSentinel - The source app sentinel identifier.
 * @returns {string} The yojam:// URL.
 */
export function buildYojamURL(targetURL, sourceSentinel) {
  const params = new URLSearchParams({
    url: targetURL,
    source: sourceSentinel,
  });
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
export async function sendToYojam(targetURL, sourceSentinel) {
  // Try native messaging first (Chrome/Firefox only)
  if (typeof chrome !== "undefined" && chrome.runtime?.sendNativeMessage) {
    try {
      await chrome.runtime.sendNativeMessage("org.yojam.host", {
        action: "route",
        url: targetURL,
        source: sourceSentinel,
      });
      return;
    } catch (_e) {
      // Native host not installed — fall through to yojam:// scheme.
      console.warn(
        "Yojam native host unavailable, falling back to yojam:// scheme"
      );
    }
  }

  // Fall back to opening a yojam:// URL in a throwaway tab.
  const url = buildYojamURL(targetURL, sourceSentinel);
  const tab = await chrome.tabs.create({ url, active: false });
  setTimeout(() => chrome.tabs.remove(tab.id).catch(() => {}), 600);
}
