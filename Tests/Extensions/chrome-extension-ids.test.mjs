import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const validator = fileURLToPath(new URL("../../scripts/validate-chrome-extension-ids.sh", import.meta.url));
const firstID = "abcdefghijklmnopabcdefghijklmnop";
const secondID = "p".repeat(32);

function validate(contents) {
  const directory = mkdtempSync("/tmp/yojam-chrome-id-test-");
  const resource = join(directory, "Chrome extension IDs.json");
  try {
    if (contents !== undefined) writeFileSync(resource, contents);
    const result = spawnSync("/bin/bash", [validator, resource], { encoding: "utf8" });
    assert.equal(result.error, undefined);
    return result;
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

test("release validation accepts one or several canonical Chrome IDs", () => {
  for (const ids of [[firstID], [firstID, secondID]]) {
    const result = validate(JSON.stringify(ids));
    assert.equal(result.status, 0, result.stderr);
  }
});

test("release validation rejects a missing Chrome ID resource", () => {
  const result = validate(undefined);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Required Chrome extension ID resource is missing/);
});

for (const [name, value] of [
  ["empty array", []],
  ["object", { id: firstID }],
  ["string", firstID],
  ["null root", null],
  ["null entry", [null]],
  ["boolean entry", [true]],
  ["number entry", [123]],
  ["nested array", [[firstID]]],
  ["object entry", [{ id: firstID }]],
  ["empty ID", [""]],
  ["short ID", ["a".repeat(31)]],
  ["long ID", ["a".repeat(33)]],
  ["uppercase ID", ["A".repeat(32)]],
  ["letter outside a to p", ["q".repeat(32)]],
  ["digit", ["a".repeat(31) + "1"]],
  ["space", [" " + firstID]],
  ["trailing newline", [firstID + "\n"]],
  ["invalid second ID", [firstID, "not-an-extension-id"]],
]) {
  test(`release validation rejects ${name}`, () => {
    const result = validate(JSON.stringify(value));
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /^FAIL:/);
  });
}

test("release validation rejects malformed JSON and non-JSON property lists", () => {
  for (const contents of ["", `[\"${firstID}\"`, `[\"${firstID}\",]`,
    `<?xml version="1.0"?><plist version="1.0"><array><string>${firstID}</string></array></plist>`]) {
    const result = validate(contents);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /nonempty JSON array/);
  }
});

test("bundle validation invokes the required Chrome ID check", () => {
  const script = readFileSync(new URL("../../scripts/validate-bundle.sh", import.meta.url), "utf8");
  assert.match(script, /\/bin\/bash "\$\(dirname "\$0"\)\/validate-chrome-extension-ids\.sh" \\\n\s*"\$APP\/Contents\/Resources\/chrome-extension-ids\.json"/);
});
