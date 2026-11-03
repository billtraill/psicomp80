// Run a COMP80 session without a browser, for testing the emulator against
// MAME.  node web/tools/session.js <rom> <steps file> [32k]
// The steps file is in the format of lisp/tests/*.txt: each line is typed
// (\r = Return, \b = Backspace, ^ = RS), "#wait <s>" waits, "#screen" prints
// the screen, "#load <file> <addr>" (or "#bin") copies a file into memory,
// "#ready" waits for the cursor (or, in BURP, which has none,
// until it is waiting for a key).  A line ending in \r is typed once FORTH
// or LISP is waiting for a line (its cursor is showing); the time it waited
// is printed if over a second.  NOWAIT=1 turns that off, as
// in forth/test_forth.lua.
"use strict";
const fs = require("fs");
const path = require("path");
global.Z80 = require("../src/z80.js").Z80;
const { COMP80, CLOCK } = require("../src/comp80.js");
const D = require("../build/data.js");

const [rom, file, mem] = process.argv.slice(2);
const m = new COMP80(D.fonts);
m.powerOn(Buffer.from(D.roms[rom], "base64"), rom, mem === "32k");
const CURS = { forth: 0x1da0, lisp: 0x0c12, basic: 0x1da0, logo: 0x1a60, focal: 0x0c08,
  pilot: 0x1da0, zasm: 0x1da0, prolog: 0x0c0e, vtl: 0x1da0, mouse: 0x1da0, befunge: 0x1da0, sheet: 0x0c02, trac: 0x0c06, pl0: 0x1da0, bf: 0x1da0 }[rom];
const waitingLine = () => CURS === undefined ? m.waitingForKey() : m.mem[m.mem[CURS] | (m.mem[CURS + 1] << 8)] === 0x1f && m.waitingForKey();

const sec = () => m.cycles / CLOCK;
const step = (s) => m.run(Math.round(s * CLOCK));
const screen = () => {
  console.log("+" + "-".repeat(64) + "+");
  for (const l of m.screenText()) console.log("|" + l + "|");
  console.log("+" + "-".repeat(64) + "+");
};
function type(text) {
  for (const ch of text) {
    const t0 = sec();
    // wait until the machine wants a key, or half a second for a key meant
    // to stop a running program
    while (!m.waitingForKey() && sec() - t0 < 0.5) step(0.002);
    while (!m.key(ch.charCodeAt(0))) { step(0.005); if (sec() - t0 > 600) throw new Error("stuck typing " + text); }
    step(0.02);
  }
}

step(1.5);
for (const line of fs.readFileSync(file, "utf8").split("\n")) {
  if (line === "") continue;
  const w = line.match(/^#wait\s+([\d.]+)/);
  if (w) { step(parseFloat(w[1])); continue; }
  if (line === "#screen") { screen(); continue; }
  const ld = line.match(/^#(?:load|bin)\s+(\S+)\s+([0-9A-Fa-f]+)/);
  if (ld) { m.mem.set(fs.readFileSync(path.resolve(path.dirname(file), ld[1])), parseInt(ld[2], 16)); continue; }
  if (line.startsWith("#snap") || line.startsWith("#dump")) continue;
  if ((line.endsWith("\\r") && !process.env.NOWAIT) || line === "#ready") {
    const t0 = sec();
    while (!waitingLine()) { step(0.01); if (sec() - t0 > 900) throw new Error("never ready for " + line); }
    if (sec() - t0 > 1) console.log(`--- busy ${(sec() - t0).toFixed(1)}s`);
    step(0.2);
  }
  if (line === "#ready") continue;
  type(line.replace(/\\r/g, "\r").replace(/\\b/g, "\b"));
  step(0.3);
}
