// The page: runs the machine in real time (or flat out), draws the screen,
// takes keys, and types in the examples.
"use strict";
(function () {
  const D = C80DATA;
  const b64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
  const ROMS = { burp: b64(D.roms.burp), forth: b64(D.roms.forth), lisp: b64(D.roms.lisp) };
  const ROM_NAMES = { burp: "BURP", forth: "FORTH", lisp: "LISP" };
  // FORTH and LISP keep the address of their cursor here; it shows _ (1Fh)
  // while they wait for a line.
  const CURS = { forth: 0x1da0, lisp: 0x0c12 };
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
        if (r.done) { tasks = tasks.filter((x) => x !== t); if (t === script) endScript(); break; }
        t.pred = r.value;
      }
    }
  }

  const after = (s) => { const at = m.cycles + s * CLOCK; return () => m.cycles >= at; };

  // One key: wait until the machine is waiting for one (or half a second,
  // so a key can still stop a running program), then press it.
  function* typeKey(c) {
    const t0 = m.cycles;
    yield () => m.waitingForKey() || m.cycles - t0 > CLOCK / 2;
    yield () => m.key(c);
    yield after(0.02);
  }
  function* typeText(text) {
    for (const ch of text) yield* typeKey(ch === "\n" ? 13 : ch.toUpperCase().charCodeAt(0));
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
  function sourceLines(text, lisp) {
    return text.split("\n").map((l) => l.replace(/\s+$/, ""))
      .filter((l) => l.trim() !== "" && !(lisp && /^\s*;/.test(l)));
  }

  function* userKeys() {
    for (;;) {
      yield () => keyQueue.length > 0;
      yield* typeKey(keyQueue.shift());
    }
  }

  function* exampleSteps(ex) {
    yield after(1.0);
    for (const s of ex.steps) {
      if (s.fs) { yield* typeKey(0x1c); yield after(0.3); }
      else if (s.keys) { yield* typeText(s.keys); yield after(0.3); }
      else if (s.bin) m.mem.set(b64(D.bins[s.bin]), s.at);
      else if (s.source) {
        const lines = sourceLines(D.sources[s.source], s.source.endsWith(".lsp"));
        for (let i = 0; i < lines.length; i++) {
          status = `Typing ${s.source}: line ${i + 1} of ${lines.length}`;
          yield* typeLine(lines[i]);
        }
      }
      else if (s.line) { status = "Typing " + s.line.trim(); yield* typeLine(s.line); }
      else if ("fast" in s) scriptFast = s.fast;
    }
  }

  function* pasted(text) {
    const lines = sourceLines(text, m.romName === "lisp");
    for (let i = 0; i < lines.length; i++) {
      status = `Typing line ${i + 1} of ${lines.length}`;
      if (CURS[m.romName] !== undefined) yield* typeLine(lines[i]);
      else { yield* typeText(lines[i] + "\r"); yield after(0.2); }
    }
  }

  function startScript(gen, label) {
    stopScript();
    script = addTask(gen, label);
    status = label;
    document.body.classList.add("busy");
  }
  function stopScript() {
    if (script) tasks = tasks.filter((t) => t !== script);
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

  // ---------------------------------------------------------------- machine

  function power(rom) {
    stopScript();
    keyQueue.length = 0;
    m.powerOn(ROMS[rom], rom, $("mem").value === "32");
    for (const r of document.querySelectorAll("input[name=rom]")) r.checked = r.value === rom;
    store.set("rom", rom);
    document.title = "COMP80 Emulator";
    $("romname").textContent = ROM_NAMES[rom];
  }

  function press(c) {
    if (script) stopScript();
    if (c === 0x1b) { keyQueue.length = 0; m.key(0x1b); return; }
    keyQueue.push(c);
  }

  function runExample(id) {
    const ex = EXAMPLES.find((e) => e.id === id);
    power(ex.rom || m.romName);
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
  $("btn-type").addEventListener("click", () => {
    const text = $("paste").value;
    if (text.trim()) { startScript(pasted(text), "Typing your program"); canvas.focus({ preventScroll: true }); }
  });

  // Examples: one card each, grouped by language.
  for (const ex of EXAMPLES) {
    const list = $("ex-" + ex.lang);
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
    list.appendChild(card);
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
