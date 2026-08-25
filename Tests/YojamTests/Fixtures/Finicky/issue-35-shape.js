// A compact, original fixture for the configuration shapes reported in issue 35.
export default {
  defaultBrowser: "Safari",
  options: {
    checkForUpdates: true,
  },
  handlers: [
    {
      match: (url, options) =>
        options.opener?.bundleId === "com.example.password-manager",
      browser: "Safari",
    },
    {
      match: (url) => url.host.startsWith("meet.example.test"),
      browser: (url) => ({
        name: "Google Chrome",
        profile: "Work",
        args: [
          "--app-id=example-app-id",
          `--app-launch-url-for-shortcuts-menu-item=${url.toString()}`,
        ],
      }),
    },
    {
      match: /^https?:\/\/calendar\.example\.test\/events\/.*$/,
      browser: "Google Chrome",
    },
  ],
};
