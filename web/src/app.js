// The page: runs the machine in real time (or flat out), draws the screen,
// takes keys, and types in the examples.
"use strict";
(function () {
  const D = C80DATA;
  const b64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
  const ROMS = Object.fromEntries(Object.entries(D.roms).map(([k, v]) => [k, b64(v)]));
  const ROM_NAMES = { burp: "BURP", forth: "FORTH", lisp: "LISP", basic: "BASIC", logo: "Logo",
    chip8: "CHIP-8", focal: "FOCAL", pilot: "PILOT", zasm: "ZASM", prolog: "Prolog",
    vtl: "VTL-2", mouse: "Mouse", befunge: "Befunge", sheet: "CALC", trac: "TRAC", pl0: "PL/0", bf: "BF",
    ed: "ED", db: "FILE", adv: "QUEST", apl: "APL" };
  // These are under "Other": a menu by the ROM switch, one tab of help and
  // one group of examples, so the rows of buttons stay short.
  const OTHER = ["vtl", "mouse", "befunge", "sheet", "trac", "pl0", "bf", "ed", "db", "adv", "apl"];
  // The languages that read a line keep the address of their cursor here; it
  // shows _ (1Fh) while they wait for one.  BURP and CHIP-8 have none.
  const CURS = { forth: 0x1da0, lisp: 0x0c12, basic: 0x1da0, logo: 0x1a60, focal: 0x0c08,
    pilot: 0x1da0, zasm: 0x1da0, prolog: 0x0c0e,
    vtl: 0x1da0, mouse: 0x1da0, befunge: 0x1da0, sheet: 0x0c02, trac: 0x0c06, pl0: 0x1da0, bf: 0x1da0,
    ed: 0x1da0, db: 0x1da0, adv: 0x1da0, apl: 0x0c38 };
  const $ = (id) => document.getElementById(id);
  const canvas = $("screen"), ctx = canvas.getContext("2d"), img = ctx.createImageData(384, 320);
  const m = new COMP80(D.fonts);

  const store = {
    get(k, d) { try { return localStorage.getItem("c80." + k) || d; } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem("c80." + k, v); } catch (e) { /* not kept */ } },
  };

  // ---------------------------------------------------------------- tasks
  // A task is a generator that yields predicates: it carries on once the
  // predicate is true.  The machine runs in 1 ms slices and the tasks are
  // looked at between slices.

  let tasks = [];
  let script = null;            // the example or pasted program being typed
  let scriptFast = false, fast = false;
  let status = "";
  const keyQueue = [];

  function addTask(gen, name) { const t = { gen, pred: null, name }; tasks.push(t); return t; }
  function pump() {
    for (const t of tasks.slice()) {
      for (let n = 0; n < 1000 && (t.pred === null || t.pred()); n++) {
        const r = t.gen.next();
        if (r.done) { tasks = tasks.filter((x) => x !== t); if (t === script) { endScript(); listingState("Typed in"); } break; }
        t.pred = r.value;
      }
    }
  }

  const after = (s) => { const at = m.cycles + s * CLOCK; return () => m.cycles >= at; };

  // One key: wait until the machine is waiting for one (or half a second,
  // so a key can still stop a running program; patient waits as long as it
  // takes), then press it.
  function* typeKey(c, patient) {
    const t0 = m.cycles;
    yield () => m.waitingForKey() || (!patient && m.cycles - t0 > CLOCK / 2);
    yield () => m.key(c);
    yield after(0.02);
  }
  function* typeText(text, patient) {
    for (const ch of text) yield* typeKey(ch === "\n" ? 13 : ch.toUpperCase().charCodeAt(0), patient);
  }
  // Waiting for a key, and still waiting a moment later.
  function* idle() {
    yield () => m.waitingForKey();
    for (;;) {
      const t0 = m.cycles;
      yield after(0.3);
      if (m.waitingForKey() && m.cycles - t0 >= 0.3 * CLOCK) return;
      yield () => m.waitingForKey();
    }
  }
  function waitingLine() {
    const a = CURS[m.romName];
    if (a === undefined) return m.waitingForKey();
    return m.mem[m.mem[a] | (m.mem[a + 1] << 8)] === 0x1f && m.waitingForKey();
  }
  function* typeLine(text) {
    yield waitingLine;
    yield after(0.05);
    yield* typeText(text + "\r");
  }
  // Which lines of a file are typed: not blank lines, nor LISP and Prolog
  // comments.  ZASM's files keep their blank lines, as one ends ASM.
  const COMMENT = { lisp: /^\s*;/, prolog: /^\s*%/, pl0: /^\s*\{/ };
  const SOURCE_LANG = { lsp: "lisp", pl: "prolog", txt: "zasm", pl0: "pl0" };
  const typed = (lang) => (l) => lang === "zasm" || (l.trim() !== "" && !(COMMENT[lang] && COMMENT[lang].test(l)));
  function sourceLines(text, lang) {
    const lines = text.replace(/\s+$/, "").split("\n").map((l) => l.replace(/\s+$/, ""));
    return lines.filter(typed(lang));
  }
  const fileLang = (name) => SOURCE_LANG[name.split(".").pop()];

  function* userKeys() {
    for (;;) {
      yield () => keyQueue.length > 0;
      yield* typeKey(keyQueue.shift());
    }
  }

  function* exampleSteps(ex) {
    const patient = ex.rom === "burp";
    yield after(1.0);
    for (const [n, s] of ex.steps.entries()) {
      if (s.fs) { listingMark(n); yield* typeKey(0x1c); yield after(0.3); }
      else if (s.keys) { listingMark(n); status = "Typing " + s.keys.trim(); yield* typeText(s.keys, patient); yield after(0.3); }
      else if (s.ready) { listingState("Waiting for the computer"); yield* idle(); }
      else if (s.bin) m.mem.set(b64(D.bins[s.bin]), s.at);
      else if (s.source) {
        const lines = sourceLines(D.sources[s.source], fileLang(s.source));
        for (let i = 0; i < lines.length; i++) {
          status = `Typing ${s.source}: line ${i + 1} of ${lines.length}`;
          listingMark(n + "." + i);
          yield* typeLine(lines[i]);
        }
      }
      else if (s.line) { listingMark(n); status = "Typing " + s.line.trim(); yield* typeLine(s.line); }
      else if ("fast" in s) scriptFast = s.fast;
    }
  }

  // BURP takes a program with LOAD: each line ends with a space and Return,
  // the last with a colon.
  function* pasted(text) {
    const lines = sourceLines(text, m.romName);
    if (m.romName === "burp") {
      status = "Typing LOAD";
      yield* typeText("LOAD ", true);
      for (let i = 0; i < lines.length; i++) {
        status = `Typing line ${i + 1} of ${lines.length}`;
        yield* typeText(lines[i].trim() + (i === lines.length - 1 ? " :" : " \r"), true);
      }
      yield* idle();
      return;
    }
    for (let i = 0; i < lines.length; i++) {
      status = `Typing line ${i + 1} of ${lines.length}`;
      if (CURS[m.romName] !== undefined) yield* typeLine(lines[i]);
      else { yield* typeText(lines[i] + "\r", true); yield* idle(); }
    }
  }

  function startScript(gen, label) {
    stopScript();
    script = addTask(gen, label);
    status = label;
    document.body.classList.add("busy");
  }
  function stopScript() {
    if (script) { tasks = tasks.filter((t) => t !== script); listingState("Stopped"); }
    script = null;
    scriptFast = false;
    endScript();
  }
  function endScript() {
    script = null;
    scriptFast = false;
    status = "";
    document.body.classList.remove("busy");
  }

  // ---------------------------------------------------------------- listing
  // Under the screen while an example runs: everything it types, a row per
  // line, with the line being typed marked.  The rows are keyed by step
  // number, and step.line for the lines of a source file.

  const listing = { rows: new Map(), cur: null };
  function showListing(ex) {
    const rows = [];
    const add = (key, text, cls) => rows.push({ key, text, cls });
    ex.steps.forEach((s, n) => {
      if (s.fs) add(n, "FS", "key");
      else if (s.keys) for (const l of s.keys.split("\r")) {
        if (l.trim() === "^") add(n, "RS", "key");
        else if (l.trim()) add(n, l.trimEnd());
      }
      else if (s.line) add(n, s.line);
      else if (s.bin) {
        const at = s.at.toString(16).toUpperCase();
        if (ex.file) for (const l of D.sources[ex.file].split("\n")) add(null, l, "src");
        else add(null, `(${s.bin}.bin, copied into memory at ${at})`, "note");
      }
      else if (s.source) {
        const keep = typed(fileLang(s.source));
        let i = 0;
        for (const l of D.sources[s.source].replace(/\s+$/, "").split("\n")) {
          const t = keep(l.replace(/\s+$/, ""));
          add(t ? n + "." + i++ : null, l, t ? "src" : "src skip");
        }
      }
    });
    const pre = $("listing-code");
    pre.textContent = "";
    listing.rows.clear();
    listing.cur = null;
    for (const r of rows) {
      const el = document.createElement("span");
      el.className = "ln" + (r.cls ? " " + r.cls : "");
      el.textContent = r.text;
      pre.appendChild(el);
      if (r.key !== null && !listing.rows.has(String(r.key))) listing.rows.set(String(r.key), el);
    }
    pre.scrollTop = 0;
    $("listing-title").textContent = ex.title;
    listingState("Typing");
    $("listing").hidden = false;
  }
  function listingMark(key) {
    const el = listing.rows.get(String(key));
    if (!el || $("listing").hidden) return;
    if (listing.cur) listing.cur.classList.remove("cur");
    el.classList.add("cur");
    listing.cur = el;
    listingState("Typing");
    // keep the line in view inside the listing, without scrolling the page
    const pre = $("listing-code");
    if (el.offsetTop < pre.scrollTop || el.offsetTop + el.offsetHeight > pre.scrollTop + pre.clientHeight)
      pre.scrollTop = el.offsetTop - pre.clientHeight / 3;
  }
  function listingState(text) { $("listing-state").textContent = text; }
  function hideListing() { $("listing").hidden = true; }

  // ---------------------------------------------------------------- machine

  // What "Type in a program" says, for each ROM.
  const PASTE_HELP = {
    burp: ["Paste the lines of a BURP program, each starting with its line number. They are typed in with LOAD, a line at a time, waiting for BURP between lines; then type RUN and the first line number, and a space. Enter BURP first (RS at READY).",
      "10 FOR A=1 STEP 1 UNTIL 5\n20 LET R=A ROOT\n30 PRINT A0 R6\n40 NEXT A\n50 END"],
    forth: ["Paste a FORTH program, or monitor commands. It is typed a line at a time, waiting for FORTH between lines. Enter FORTH first (RS at READY).",
      ": SQUARES 11 1 DO I DUP * . LOOP ;\nSQUARES"],
    lisp: ["Paste a LISP program, or monitor commands. It is typed a line at a time, waiting for LISP between lines; comments are left out. Enter LISP first (RS at READY).",
      "(DEFUN SQ (X) (* X X))\n(SQ 7)"],
    basic: ["Paste a BASIC program, or monitor commands. It is typed a line at a time, waiting for BASIC between lines; numbered lines go into the program. Enter BASIC first (RS at READY), and type RUN to run it.",
      "10 FOR I=1 TO 10\n20 PRINT I, I*I\n30 NEXT I\nRUN"],
    logo: ["Paste a Logo program, or monitor commands. It is typed a line at a time, waiting for Logo between lines; TO ... END definitions can run over many lines. Enter Logo first (RS at READY).",
      "TO SQUARE :S\nREPEAT 4 [FD :S RT 90]\nEND\nREPEAT 8 [SQUARE 30 RT 45]"],
    chip8: ["Paste monitor commands, such as LOAD 0E00 followed by a program’s bytes in hex and @. FS goes back to the monitor first; RS then runs the program at 0E00.",
      "LOAD 0E00 00E0 6010 …@"],
    focal: ["Paste a FOCAL program or commands. It is typed a line at a time, waiting for FOCAL between lines. Numbered lines go into the program; GO runs it. Enter FOCAL first (RS at READY).",
      "1.1 FOR I=1,10; TYPE I, FSQT(I), !\nGO"],
    pilot: ["Paste a PILOT program, or monitor commands. It is typed a line at a time, waiting for PILOT between lines. Numbered lines go into the program; then type RUN. Enter PILOT first (RS at READY).",
      "10 T:WHAT IS YOUR NAME?\n20 A:$N\n30 T:HELLO, $N!\nRUN"],
    zasm: ["Paste ZASM commands or ASM lines. They are typed a line at a time, waiting for ZASM between lines, blank lines too. Enter ZASM first (RS at READY). Numbers are hex and start with a digit (0FF); a blank line ends ASM.",
      "ASM 1000\nLD A,41\nLD (8040),A\nRET\n\nG 1000"],
    prolog: ["Paste a Prolog program, or monitor commands. It is typed a line at a time, waiting for Prolog between lines; comments are left out. Enter Prolog first (RS at READY). Clauses end with a full stop; queries start ?- .",
      "LIKES(MARY,WINE).\nLIKES(JOHN,X) :- LIKES(MARY,X).\n?- LIKES(JOHN,W)."],
    vtl: ["Paste a VTL-2 program, or monitor commands. It is typed a line at a time, waiting for VTL-2 between lines; numbered lines go into the program. Enter VTL-2 first (RS at READY), then 0 lists it and #=1 runs it.",
      "10 I=1\n20 ?=I*I\n30 I=I+1\n40 #=(I<11)*20\n#=1"],
    mouse: ["Paste a Mouse program, or monitor commands. It is typed a line at a time, waiting for Mouse between lines; numbered lines go into the program, then type RUN. Enter Mouse first (RS at READY).",
      "10 1 N: ( N. 11 < & N. N. * ! \" \" N. 1 + N: ) $$\nRUN"],
    befunge: ["Paste Befunge commands. They are typed a line at a time, waiting for Befunge between lines: Y X TEXT puts TEXT on line Y of the playfield from column X; then RUN. Type ' = ; for ^ _ \\, and I ) ( for | ` ~. Enter Befunge first (RS at READY).",
      "CLEAR\n0 0 \"!IH\">:#,=@\nRUN"],
    sheet: ["Paste lines to type into the sheet, a line at a time, waiting for CALC between lines. Each goes into the marked cell: a number, a formula (+A1*B2, @SUM(A1...A5)) or a label; >B3 moves, /U copies the cell above. Enter CALC first (RS at READY).",
      ">A1\n12\n30\n+A1*A2"],
    trac: ["Paste a TRAC program, or monitor commands. It is typed a line at a time, waiting for TRAC between lines; nothing runs until the meta character ' ends the input. Enter TRAC first (RS at READY).",
      "#(DS,AA,CAT)'\n#(PS,##(CL,AA))'"],
    pl0: ["Paste a PL/0 program, or monitor commands. It is typed a line at a time, waiting for PL/0 between lines; numbered lines go into the program. Enter PL/0 first (RS at READY), and type RUN to compile and run it.",
      "10 VAR I;\n20 BEGIN I := 1;\n30 WHILE I <= 10 DO BEGIN ! I * I; I := I + 1 END\n40 END.\nRUN"],
    bf: ["Paste a BF program as numbered lines, or monitor commands. It is typed a line at a time, waiting for BF between lines; then type RUN, SHOW or STEP. Enter BF first (RS at READY).",
      "10 ++++++++[>++++++++<-]>+.\nSHOW"],
    ed: ["Paste ED commands and text, typed a line at a time, waiting for ED between lines. A, I and C take lines until one that is just a full stop. Enter ED first (RS at READY).",
      "A\nHELLO\nWORLD\n.\n,N"],
    db: ["Paste FILE commands, a line at a time, waiting for FILE between lines: FIELDS NAME,TOWN,AGE once, then ADD SMITH,LEEDS,42 for each card, then LIST, FIND, SORT BY, COUNT, SUM or SHOW. Enter FILE first (RS at READY).",
      "FIELDS NAME,AGE\nADD ANN,34\nADD BOB,29\nSORT BY AGE\nLIST"],
    adv: ["Paste the lines of a QUEST world (ROOM, EXIT, OBJ, FIX, ON), or commands. They are typed a line at a time, waiting for QUEST between lines; then type PLAY. Enter QUEST first (RS at READY).",
      "ROOM HALL A DUSTY HALL.\nROOM YARD A SUNNY YARD.\nEXIT HALL N YARD\nEXIT YARD S HALL\nOBJ LAMP HALL AN OLD LAMP.\nPLAY"],
    apl: ["Paste APL lines, or monitor commands. They are typed a line at a time, waiting for APL between lines, and each line’s value is printed. Enter APL first (RS at READY).",
      "3 4 RHO IOTA 12\n+/ IOTA 10"],
  };

  function power(rom) {
    stopScript();
    hideListing();
    keyQueue.length = 0;
    m.powerOn(ROMS[rom], rom, $("mem").value === "32");
    for (const r of document.querySelectorAll("input[name=rom]")) r.checked = r.value === rom;
    $("rom-other").value = OTHER.includes(rom) ? rom : "";
    store.set("rom", rom);
    document.title = "COMP80 Emulator";
    $("romname").textContent = ROM_NAMES[rom];
    $("paste-help").textContent = PASTE_HELP[rom][0];
    $("paste").placeholder = PASTE_HELP[rom][1];
  }

  function press(c) {
    if (script) stopScript();
    if (c === 0x1b) { keyQueue.length = 0; m.key(0x1b); return; }
    keyQueue.push(c);
  }

  function runExample(id) {
    const ex = EXAMPLES.find((e) => e.id === id);
    power(ex.rom || m.romName);
    showListing(ex);
    startScript(exampleSteps(ex), "Starting " + ex.title);
    canvas.focus({ preventScroll: true });
    if (window.matchMedia("(max-width: 60rem)").matches) canvas.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  // ---------------------------------------------------------------- main loop

  let last = performance.now(), rate = 0, rateCycles = 0, rateTime = 0;
  function frame(now) {
    const wall = now - last;
    const dt = Math.min(wall, 250);   // catch up after a slow frame, but not after a long pause
    last = now;
    const turbo = fast || scriptFast;
    const start = performance.now(), c0 = m.cycles;
    const budget = dt * CLOCK / 1000;
    while (turbo ? performance.now() - start < 14 : m.cycles - c0 < budget) {
      m.run(4000);
      pump();
    }
    rateCycles += m.cycles - c0; rateTime += wall;
    if (rateTime > 500) { rate = rateCycles / rateTime * 1000 / CLOCK; rateCycles = 0; rateTime = 0; }
    m.render(img.data);
    ctx.putImageData(img, 0, 0);
    $("status").textContent = status || (m.cpu.halted ? "Waiting for a key" : "Running");
    $("speed").textContent = rate ? `${rate >= 10 ? Math.round(rate) : rate.toFixed(1)}× real speed` : "";
    requestAnimationFrame(frame);
  }

  // ---------------------------------------------------------------- keyboard

  function hostKey(e) {
    if (e.metaKey || e.altKey) return;
    let c = null;
    if (e.key === "Enter") c = 13;
    else if (e.key === "Backspace") c = 8;
    else if (e.key === "Escape") c = 0x1b;
    else if (e.ctrlKey && (e.key === "\\" || e.code === "Backslash")) c = 0x1c;
    else if (!e.ctrlKey && e.key.length === 1) {
      c = e.key.toUpperCase().charCodeAt(0);
      if (c < 0x20 || c > 0x5f) c = null;
    }
    if (c === null) return;
    e.preventDefault();
    press(c);
  }
  canvas.addEventListener("keydown", hostKey);
  canvas.addEventListener("pointerdown", () => canvas.focus());

  // The typing box, for phones and tablets: take what is typed and clear it.
  const kbd = $("kbd");
  kbd.addEventListener("beforeinput", (e) => {
    if (e.inputType === "deleteContentBackward") press(8);
    else if (e.inputType === "insertLineBreak" || e.inputType === "insertParagraph") press(13);
    else if (e.data) for (const ch of e.data) { const c = ch.toUpperCase().charCodeAt(0); if (c >= 0x20 && c <= 0x5f) press(c); }
    e.preventDefault();
  });
  kbd.addEventListener("keydown", (e) => { if (e.key === "Enter") { e.preventDefault(); press(13); } });

  // ---------------------------------------------------------------- controls

  for (const r of document.querySelectorAll("input[name=rom]")) r.addEventListener("change", () => power(r.value));
  $("rom-other").addEventListener("change", () => { if ($("rom-other").value) power($("rom-other").value); });
  $("mem").addEventListener("change", () => { store.set("mem", $("mem").value); power(m.romName); });
  $("btn-rs").addEventListener("click", () => { press(0x1e); canvas.focus(); });
  $("btn-fs").addEventListener("click", () => { press(0x1c); canvas.focus(); });
  $("btn-reset").addEventListener("click", () => { press(0x1b); canvas.focus(); });
  $("btn-power").addEventListener("click", () => { power(m.romName); canvas.focus(); });
  $("btn-fast").addEventListener("click", () => {
    fast = !fast;
    $("btn-fast").setAttribute("aria-pressed", String(fast));
  });
  $("btn-stop").addEventListener("click", () => stopScript());
  $("listing-close").addEventListener("click", hideListing);
  $("btn-type").addEventListener("click", () => {
    const text = $("paste").value;
    if (text.trim()) { startScript(pasted(text), "Typing your program"); canvas.focus({ preventScroll: true }); }
  });

  // Examples: one card each, grouped by language on the Examples tab, and
  // again on each language's page.
  function exampleCard(ex) {
    const card = document.createElement("article");
    card.className = "ex";
    const src = ex.file ? D.sources[ex.file]
      : ex.steps.filter((s) => s.line || s.keys).map((s) => s.line || s.keys).join("\n");
    card.innerHTML = `<div class="exhead"><h4></h4><button type="button" class="run">Run</button></div>
      <p class="extext"></p>${ex.keys ? '<p class="exkeys"></p>' : ""}
      <details><summary></summary><pre><code></code></pre></details>`;
    card.querySelector("h4").textContent = ex.title;
    card.querySelector(".extext").textContent = ex.text;
    if (ex.keys) card.querySelector(".exkeys").textContent = ex.keys;
    card.querySelector("summary").textContent = ex.file ? "Show " + ex.file : "Show what gets typed";
    card.querySelector("code").textContent = src;
    card.querySelector(".run").addEventListener("click", () => runExample(ex.id));
    card.querySelector(".run").setAttribute("aria-label", "Run " + ex.title);
    return card;
  }
  for (const ex of EXAMPLES) {
    $("ex-" + ex.lang).appendChild(exampleCard(ex));
    $("exl-" + ex.lang).appendChild(exampleCard(ex));
  }

  // Tabs
  const tabs = Array.from(document.querySelectorAll("[role=tab]"));
  function showTab(id, focus) {
    for (const t of tabs) {
      const on = t.dataset.tab === id;
      t.setAttribute("aria-selected", String(on));
      t.tabIndex = on ? 0 : -1;
      $("panel-" + t.dataset.tab).hidden = !on;
      if (on && focus) t.focus();
    }
  }
  tabs.forEach((t, i) => {
    t.addEventListener("click", () => showTab(t.dataset.tab));
    t.addEventListener("keydown", (e) => {
      const d = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
      if (d) { e.preventDefault(); showTab(tabs[(i + d + tabs.length) % tabs.length].dataset.tab, true); }
    });
  });
  // The Other tab shows one language at a time.
  function showOther(lang) {
    for (const b of document.querySelectorAll("#other-nav button")) b.setAttribute("aria-pressed", String(b.dataset.lang === lang));
    for (const s of document.querySelectorAll("#panel-other .sub")) s.hidden = s.id !== "other-" + lang;
  }
  for (const b of document.querySelectorAll("#other-nav button")) b.addEventListener("click", () => showOther(b.dataset.lang));
  showOther(OTHER[0]);
  document.addEventListener("click", (e) => {
    const a = e.target.closest("a[data-goto]");
    if (a) { e.preventDefault(); showTab(a.dataset.goto); $("panel-" + a.dataset.goto).scrollIntoView({ block: "nearest" }); }
  });
  const hash = location.hash.replace("#", "");
  showTab(tabs.some((t) => t.dataset.tab === hash) ? hash : "examples");

  // For testing from the console: c80.advance(s) runs s seconds of the
  // machine and the typing, however slowly the page is drawing.
  window.c80 = {
    machine: m, runExample, power,
    advance(s) { const end = m.cycles + s * CLOCK; while (m.cycles < end) { m.run(4000); pump(); } },
    get busy() { return script !== null; },
  };

  $("mem").value = store.get("mem", "5");
  power(ROMS[store.get("rom", "burp")] ? store.get("rom", "burp") : "burp");
  addTask(userKeys(), "keys");
  requestAnimationFrame(frame);
})();
