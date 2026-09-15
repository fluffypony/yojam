import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const releaseScript = fileURLToPath(new URL("../../scripts/release.sh", import.meta.url));
const browsers = ["chrome", "firefox", "safari"];

function validate(overrides = {}, args = ["--check-extension-versions"]) {
  const directory = mkdtempSync("/tmp/yojam-release-versions-");
  try {
    mkdirSync(join(directory, "scripts"));
    const script = join(directory, "scripts/release.sh");
    copyFileSync(releaseScript, script);
    writeFileSync(join(directory, "project.yml"),
      'MARKETING_VERSION: "1.3.1"\nCURRENT_PROJECT_VERSION: "10"\n');
    for (const browser of browsers) {
      const contents = Object.hasOwn(overrides, browser)
        ? overrides[browser]
        : JSON.stringify({ manifest_version: 3, version: "1.3.1" });
      const manifestDirectory = join(directory, "Extensions", browser);
      mkdirSync(manifestDirectory, { recursive: true });
      if (contents !== undefined) {
        writeFileSync(join(manifestDirectory, "manifest.json"), contents);
      }
    }
    const env = { ...process.env };
    delete env.RS_TEAM_ID;
    const result = spawnSync("/bin/bash", [script, ...args], { encoding: "utf8", env });
    assert.equal(result.error, undefined);
    return result;
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

const version = value => JSON.stringify({ manifest_version: 3, version: value });

test("extension preflight accepts separate store versions without signing credentials", () => {
  const result = validate({ chrome: version("1.2.9"), firefox: version("1.3.2") });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /chrome extension: 1\.2\.9/);
  assert.match(result.stdout, /firefox extension: 1\.3\.2/);
  assert.match(result.stdout, /safari extension: 1\.3\.1/);
});

test("extension preflight accepts matching versions", () => {
  const result = validate();
  assert.equal(result.status, 0, result.stderr);
});

test("Safari must match the Mac release version", () => {
  const result = validate({ safari: version("1.3.2") });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Safari extension version 1\.3\.2 does not match app version 1\.3\.1/);
});

test("the normal release path also validates extension versions", () => {
  const result = validate({ safari: version("1.3.2") }, []);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Safari extension version 1\.3\.2 does not match/);
  assert.doesNotMatch(result.stderr, /RS_TEAM_ID/);
});

for (const browser of browsers) {
  test(`extension preflight requires a valid ${browser} manifest`, () => {
    for (const contents of [undefined, "", '{"version":"1.3.1",}', "[]", "null",
      '<?xml version="1.0"?><plist><dict><key>version</key><string>1.3.1</string></dict></plist>']) {
      const result = validate({ [browser]: contents });
      assert.notEqual(result.status, 0, `Accepted ${browser} manifest: ${contents}`);
      assert.match(result.stderr, new RegExp(`FAIL: .*${browser} extension manifest`));
    }
  });

  test(`extension preflight rejects invalid ${browser} version formats`, () => {
    for (const value of [undefined, null, 1, true, {}, [], "", "01.2", "1.00.2",
      "1.2.3.4.5", "1.3.2-beta", "1..2", "-1", "1.2\n", " 1.2", "1000000000"]) {
      const result = validate({ [browser]: version(value) });
      assert.notEqual(result.status, 0, `Accepted ${browser} version: ${JSON.stringify(value)}`);
      assert.match(result.stderr, new RegExp(`FAIL: ${browser} extension version must be a string`));
    }
  });
}

test("Chrome versions follow the store component limits", () => {
  for (const value of ["1", "0.1", "1.2.3", "65535.0.65535.1"]) {
    const result = validate({ chrome: version(value) });
    assert.equal(result.status, 0, result.stderr);
  }
  for (const value of ["0", "0.0.0.0", "65536", "1.65536.0.0"]) {
    const result = validate({ chrome: version(value) });
    assert.notEqual(result.status, 0, `Accepted Chrome version: ${value}`);
    assert.match(result.stderr, /Chrome extension version integers must be 0 to 65535/);
  }
});

test("Firefox permits the larger component range accepted by AMO", () => {
  for (const value of ["0", "1", "1.3.2", "65536", "999999999.0.1.999999999"]) {
    const result = validate({ firefox: version(value) });
    assert.equal(result.status, 0, result.stderr);
  }
});
