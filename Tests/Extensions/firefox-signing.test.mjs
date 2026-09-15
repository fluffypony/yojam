import assert from "node:assert/strict";
import { chmodSync, copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

function runSigning({ pending = false } = {}) {
  const directory = mkdtempSync("/tmp/yojam-firefox-signing-");
  try {
    const source = join(directory, "dist/firefox");
    mkdirSync(source, { recursive: true });
    writeFileSync(join(source, "manifest.json"), '{"version":"1.3.2"}');
    const script = join(directory, "sign-firefox.sh");
    copyFileSync(new URL("../../Extensions/sign-firefox.sh", import.meta.url), script);
    const previousPackage = Buffer.from("previous signed package");
    const output = join(directory, "dist/yojam-firefox.xpi");
    writeFileSync(output, previousPackage);
    const returnedPackage = join(directory, "returned.xpi");
    const archive = spawnSync("python3", ["-c", "import sys,zipfile\nwith zipfile.ZipFile(sys.argv[1], 'w') as z: z.writestr('META-INF/mozilla.rsa', 'test signature fixture')", returnedPackage]);
    assert.equal(archive.status, 0, archive.stderr?.toString());

    const calls = join(directory, "calls.jsonl");
    const npm = join(directory, "npm");
    writeFileSync(npm, `#!/usr/bin/env node
const fs = require("node:fs"), path = require("node:path");
const args = process.argv.slice(2);
fs.appendFileSync(process.env.YOJAM_SIGNING_CALLS, JSON.stringify(args) + "\\n");
if (args.includes("sign") && process.env.YOJAM_SIGNING_PENDING !== "true") {
  const destination = args[args.indexOf("--artifacts-dir") + 1];
  fs.copyFileSync(process.env.YOJAM_SIGNING_PACKAGE, path.join(destination, "signed.xpi"));
}
`);
    chmodSync(npm, 0o755);
    const result = spawnSync("/bin/bash", [script], {
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${directory}:${process.env.PATH}`,
        WEB_EXT_API_KEY: "test-key",
        WEB_EXT_API_SECRET: "test-secret",
        YOJAM_SIGNING_CALLS: calls,
        YOJAM_SIGNING_PACKAGE: returnedPackage,
        YOJAM_SIGNING_PENDING: String(pending),
      },
    });
    assert.equal(result.error, undefined);
    return {
      result,
      calls: readFileSync(calls, "utf8").trim().split("\n").map(JSON.parse),
      package: readFileSync(output),
      previousPackage,
      returnedPackage: readFileSync(returnedPackage),
    };
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

test("Firefox signing uses public validation and the listed channel", () => {
  const run = runSigning();
  assert.equal(run.result.status, 0, run.result.stderr);
  assert.equal(run.calls.length, 2);
  const [lint, sign] = run.calls;
  assert.ok(lint.includes("lint"));
  assert.ok(!lint.includes("--self-hosted"));
  assert.ok(sign.includes("sign"));
  assert.equal(sign[sign.indexOf("--channel") + 1], "listed");
  for (const args of run.calls) {
    assert.ok(!args.includes("test-key"));
    assert.ok(!args.includes("test-secret"));
  }
  assert.deepEqual(run.package, run.returnedPackage);
});

test("a pending Firefox review preserves the previous signed package", () => {
  const run = runSigning({ pending: true });
  assert.notEqual(run.result.status, 0);
  assert.match(run.result.stderr, /Mozilla has not returned a signed XPI/);
  assert.deepEqual(run.package, run.previousPackage);
});
