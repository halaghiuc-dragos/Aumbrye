import assert from "node:assert/strict";
import test from "node:test";
import {
  findPatchNoteContent,
  findWikiContent,
  patchNoteContentPath,
  wikiContentPath,
} from "../src/content/content-paths.ts";

test("content URLs are canonical encoded single segments", () => {
  assert.equal(wikiContentPath("controls"), "/wiki/controls");
  assert.equal(patchNoteContentPath("0.6.0"), "/patch-notes/0.6.0");
  assert.equal(wikiContentPath("guide name"), "/wiki/guide%20name");
  assert.equal(wikiContentPath("../private"), undefined);
  assert.equal(patchNoteContentPath("folder\\note"), undefined);
});

test("fixture routes resolve exactly and missing or malformed segments stay not-found", () => {
  const pages = [{ slug: "controls", title: "Controls" }];
  const notes = [{ slug: "launch", version: "0.6.0" }];
  assert.equal(findWikiContent(pages, "controls"), pages[0]);
  assert.equal(findWikiContent(pages, "missing"), undefined);
  assert.equal(findWikiContent(pages, "a/b"), undefined);
  assert.equal(findPatchNoteContent(notes, "launch"), notes[0]);
  assert.equal(findPatchNoteContent(notes, "0.6.0"), notes[0]);
  assert.equal(findPatchNoteContent(notes, "unknown"), undefined);
});
