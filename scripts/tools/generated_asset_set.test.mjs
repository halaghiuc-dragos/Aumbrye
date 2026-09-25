import test from "node:test";
import assert from "node:assert/strict";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { publishGeneratedAssetSet } from "./generated_asset_set.mjs";

function fixture() {
  const root = mkdtempSync(join(tmpdir(), "aumbrye-generated-set-test-"));
  const tools = join(root, "tools");
  const inputs = join(root, "inputs");
  mkdirSync(tools);
  mkdirSync(inputs);
  const generatorPath = join(tools, "generator.mjs");
  const sourcePath = join(inputs, "catalog.json");
  const manifestPath = join(tools, ".generated-manifest.json");
  writeFileSync(generatorPath, "// generator fixture\n");
  writeFileSync(sourcePath, '{"source":true}\n');
  writeFileSync(manifestPath, "{}\n");
  return { root, generatorPath, sourcePath, manifestPath };
}

function publish(f, outputs, force = false) {
  return publishGeneratedAssetSet({
    repoRoot: f.root,
    manifestPath: f.manifestPath,
    generatorPath: f.generatorPath,
    sourcePaths: [f.sourcePath],
    seed: 91,
    outputs,
    force,
  });
}

test("complete set is validated before any destination is published", () => {
  const f = fixture();
  const first = join(f.root, "content", "first.json");
  const second = join(f.root, "content", "second.json");
  assert.throws(() => publish(f, [
    { path: first, buffer: Buffer.from('{"valid":true}\n') },
    { path: second, buffer: Buffer.from("not-json\n") },
  ]), SyntaxError);
  assert.equal(existsSync(first), false);
  assert.equal(existsSync(second), false);
});

test("invalid binary audio prevents every output in the set from publishing", () => {
  const f = fixture();
  const jsonPath = join(f.root, "content", "before.ogg");
  const invalidAudioPath = join(f.root, "content", "invalid.ogg");
  assert.throws(() => publish(f, [
    { path: jsonPath, buffer: Buffer.concat([Buffer.from("OggS"), Buffer.alloc(24)]) },
    { path: invalidAudioPath, buffer: Buffer.from("not an ogg stream") },
  ]), /invalid container header/);
  assert.equal(existsSync(jsonPath), false);
  assert.equal(existsSync(invalidAudioPath), false);
});

test("invalid PNG prevents every output in the set from publishing", () => {
  const f = fixture();
  const jsonPath = join(f.root, "content", "before.json");
  const pngPath = join(f.root, "content", "icon.png");
  assert.throws(() => publish(f, [
    { path: jsonPath, buffer: Buffer.from('{"valid":true}\n') },
    { path: pngPath, buffer: Buffer.from("not a png") },
  ]), /invalid header/);
  assert.equal(existsSync(jsonPath), false);
  assert.equal(existsSync(pngPath), false);
});

test("manual bytes are preserved unless force is explicit and override is recorded", () => {
  const f = fixture();
  const outputPath = join(f.root, "content", "asset.json");
  mkdirSync(join(f.root, "content"));
  writeFileSync(outputPath, '{"authored":true}\n');
  const candidate = { path: outputPath, buffer: Buffer.from('{"generated":true}\n') };
  assert.throws(() => publish(f, [candidate]), /unregistered\/manual asset/);
  assert.equal(readFileSync(outputPath, "utf8"), '{"authored":true}\n');
  publish(f, [candidate], true);
  const manifest = JSON.parse(readFileSync(f.manifestPath, "utf8"));
  assert.equal(manifest["content/asset.json"].manualOverride, true);
  assert.equal(manifest["content/asset.json"].seed, 91);
});

test("dry run validates ownership and candidate bytes without publishing outputs or manifest", () => {
  const f = fixture();
  const outputPath = join(f.root, "content", "dry.json");
  const result = publishGeneratedAssetSet({
    repoRoot: f.root,
    manifestPath: f.manifestPath,
    generatorPath: f.generatorPath,
    sourcePaths: [f.sourcePath],
    outputs: [{ path: outputPath, buffer: Buffer.from('{"dry":true}\n') }],
    dryRun: true,
  });
  assert.deepEqual(result, ["content/dry.json"]);
  assert.equal(existsSync(outputPath), false);
  assert.equal(readFileSync(f.manifestPath, "utf8"), "{}\n");
});

test("owned output sets publish atomically and retain provenance for every path", () => {
  const f = fixture();
  const one = join(f.root, "content", "one.json");
  const two = join(f.root, "content", "two.json");
  const published = publish(f, [
    { path: one, buffer: Buffer.from('{"one":1}\n') },
    { path: two, buffer: Buffer.from('{"two":2}\n') },
  ]);
  assert.deepEqual(published, ["content/one.json", "content/two.json"]);
  const manifest = JSON.parse(readFileSync(f.manifestPath, "utf8"));
  assert.equal(manifest["content/one.json"].generator, "tools/generator.mjs");
  assert.equal(manifest["content/one.json"].sources["inputs/catalog.json"].length, 64);
  assert.equal(manifest["content/two.json"].outputSha256.length, 64);
  assert.equal(manifest["content/two.json"].manualOverride, false);
  assert.equal(readFileSync(one, "utf8"), '{"one":1}\n');
  assert.equal(readFileSync(two, "utf8"), '{"two":2}\n');
});
