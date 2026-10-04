// seq3mem.mjs -- the seq-3 memory ladder in the grid-wasm VM.
//
// Streams the real sequencer-3/dist bundles into the VM in the order the
// device loads them and prints collectgarbage("count") after every stage, so
// "how far does the engine get, and with how much room" is one command.
//
//   GUI (default):  START: seq3 -> seq3e -> seq3ui -> ensure/demo -> status
//                   view + 96 pulses; FIRST PRESS: seq3s (screen) -> key + draw
//                   -> seq3x + Shred + Random -> 96 more pulses
//                   -> seq3p (persist) + save a slot -> free-heap probe
//   --headless:     seq3 -> seq3e -> seq3h -> ensure -> 96 pulses -> report
//                   -> free-heap probe
//
// Calibration (wasm-harness-memory-calibration): the VM has at least ~20 KB
// less than the device. A PASS here is strong evidence a build fits the
// device; a FAIL proves nothing about it. The `free` stage measures the real
// free heap after the run (1 KB allocations until refusal).
//
// Usage: node seq3mem.mjs [--headless] [--verbose]
// Requires: python3 -m http.server 8080 running from the repo root.
//
// Exit 0 when every stage passes, 1 when one fails (OOM or error).

import { chromium } from 'playwright';
import { readFileSync } from 'fs';

const args = process.argv.slice(2);
const headless = args.includes('--headless');
const verbose = args.includes('--verbose');
const CHUNK = 600;     // raw source bytes per loadScript (2 KB cap incl. preamble)
const DIST = '../sequencer-3/dist/';

function luaStr(s) {
    let out = '"';
    for (let i = 0; i < s.length; i++) {
        const c = s[i], code = s.charCodeAt(i);
        if (c === '\\') out += '\\\\';
        else if (c === '"') out += '\\"';
        else if (c === '\n') out += '\\n';
        else if (c === '\r') out += '\\r';
        else if (c === '\t') out += '\\t';
        else if (code < 32) out += '\\' + code;
        else out += c;
    }
    return out + '"';
}

// Every Lua snippet reports through one tagged line: "ST <tag> <ok|FAIL> ...".
// KB is the live heap after a full collect (what is resident), PRE the count
// before it (what the stage left as garbage on top).
const KB = 'local pre=collectgarbage("count") collectgarbage() local kb=collectgarbage("count")';
function stage(tag, body) {
    return `local ok,e=pcall(function() ${body} end) ${KB} `
        + `print("ST ${tag} "..(ok and "ok" or "FAIL").." "..string.format("%.1f",kb).." "..string.format("%.1f",pre).." "..(ok and "" or tostring(e)))`;
}

// Stream one bundle as indexed pieces (idempotent, so a re-sent call after a
// dropped one cannot duplicate), then compile it with a reader that drops
// each piece as it hands it out. Compiling is its own stage: the device also
// compiles a bundle before running its body.
function bundleCalls(name) {
    const src = readFileSync(new URL(DIST + name + '.lua', import.meta.url).pathname, 'utf-8');
    const calls = [];
    let n = 0;
    for (let i = 0; i < src.length; i += CHUNK, n++) {
        const tag = `CD ${name}:${n}`;
        calls.push([`MA=MA or {} MA[${luaStr(name)}]=MA[${luaStr(name)}] or {} `
            + `MA[${luaStr(name)}][${n + 1}]=${luaStr(src.slice(i, i + CHUNK))} collectgarbage() print(${luaStr(tag)})`, tag]);
    }
    calls.push([stage(`compile:${name}`,
        `local arr=MA[${luaStr(name)}] local ix=0 `
        + `local f,err=load(function() ix=ix+1 local p=arr[ix] arr[ix]=nil return p end,${luaStr('=' + name)},"t") `
        + `MA[${luaStr(name)}]=nil if not f then error(err) end __C[${luaStr(name)}]=f`), `ST compile:${name}`]);
    return { calls, bytes: src.length };
}

// The bundles capture `_host=require` at load; this one hands out a compiled
// bundle's return table (running its body exactly once, like the device).
const PRELUDE = stage('vm', `
__C={} __L={}
require=function(n)
  local m=__L[n] if m then return m end
  local f=__C[n] if not f then error("bundle not streamed: "..tostring(n)) end
  __C[n]=nil m=f() __L[n]=m return m
end
SENT=0 SEND=function() SENT=SENT+1 end
LCD={draw_rectangle_filled=function() end,draw_rectangle=function() end,
  draw_text_fast=function() end,draw_swap=function() end}`);

// How much heap is really free at this point: grab 1 KB strings until the VM
// refuses. Measured 2026-10-04: ~8 KB free at 108.8 KB resident, so the VM's
// effective ceiling is ~117 KB, NOT the ~130 KB where "Out of memory" prints.
const PROBE = stage('free', 'local t,n={},0 pcall(function() for i=1,200 do t[i]=string.rep("x",1000-24)..i n=i end end) t=nil collectgarbage() FREE=n print("FREE "..n)');

const plan = [];
const sizes = {};
function add(code) { plan.push([code, code.match(/print\("(ST [^ ]+)/)[1]]); }
function stream(name) { const b = bundleCalls(name); sizes[name] = b.bytes; plan.push(...b.calls); }

add(PRELUDE);
stream('seq3');
add(stage('run:seq3', 'require("seq3")'));
stream('seq3e');
add(stage('run:seq3e', 'require("seq3e")'));
if (headless) {
    stream('seq3h');
    add(stage('run:seq3h', 'RX=require("seq3h").headless'));
    add(stage('ensure', 'RX.ensure()'));
    add(stage('pulses96', 'for i=1,96 do RX.handle(0xF8,SEND) end print("SENT "..SENT)'));
    add(stage('report', 'RX.report()'));
    add(PROBE);
} else {
    // app START: what the first MIDI byte (and the timer) compile
    stream('seq3ui');
    add(stage('run:seq3ui', 'UI=require("seq3ui") RX=UI.midi_rx'));
    add(stage('ensure+demo', 'RX.ensure()'));
    add(stage('status+96', 'RX.ui(LCD) RX.handle(0xFA,SEND) for i=1,96 do RX.handle(0xF8,SEND) end RX.ui(LCD) print("SENT "..SENT)'));
    // first control press: the screen bundle
    stream('seq3s');
    add(stage('key+draw', 'RX.key(1) RX.ui(LCD)'));
    stream('seq3x');
    add(stage('shred', 'RX.key(7) RX.ui(LCD)'));
    add(stage('random', 'RX.key(3) RX.ui(LCD)'));
    add(stage('pulses96', 'for i=1,96 do RX.handle(0xF8,SEND) end RX.ui(LCD) print("SENT "..SENT)'));
    // save: io.open is stubbed with a write-counting sink, so this runs the
    // device save path (saveSlot) without a filesystem
    stream('seq3p');
    add(stage('persist', 'local P=require("seq3p").persist local n=0 io=io or {} io.open=function() return {write=function() n=n+1 end,close=function() end} end local r=P.saveSlot(1) print("SAVE "..tostring(r).." writes "..n)'));
    add(PROBE);   // last: the probe itself fragments the heap for what follows
}

async function run() {
    const browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    const results = [];
    let waiting = null, oomWarn = 0, free = null;
    page.on('console', msg => {
        const t = msg.text();
        if (waiting && t.startsWith(waiting.tag)) { const w = waiting; waiting = null; w.resolve(t); return; }
        if (t.startsWith('ST ')) { results.push(t); return; }
        if (/Out of memory/.test(t)) { oomWarn++; return; }
        if (t.startsWith('FREE ')) { free = +t.slice(5); return; }
        if (verbose || /memory|error|SENT|SAVE|^L\d|seq3/i.test(t)) console.log('[lua]', t.slice(0, 200));
    });
    await page.goto('http://localhost:8080/grid-wasm/index.html');
    await page.waitForFunction(() => typeof Module !== 'undefined' && typeof Module.ccall === 'function',
        { timeout: 15000 });

    const send = code => page.evaluate(c => Module.ccall('loadScript', 'void', ['string', 'string'], [c, '']), code);
    let failed = null, peak = 0;
    for (const [code, tag] of plan) {
        let line = null;
        for (let attempt = 0; attempt < 4 && line === null; attempt++) {
            const p = new Promise(resolve => { waiting = { tag: tag + (tag.startsWith('CD') ? '' : ' '), resolve }; });
            await send(code);
            line = await Promise.race([p, new Promise(r => setTimeout(() => r(null), 3000))]);
            if (line === null) {
                waiting = null;
                // a stage that died mid-run (OOM) prints nothing: re-sending
                // a stage would run it twice, so only chunk pushes retry
                if (!tag.startsWith('CD')) break;
            }
        }
        if (tag.startsWith('CD')) {
            if (line === null) { failed = `${tag}: no handshake (VM dead?)`; break; }
            continue;
        }
        if (line === null) { failed = `${tag}: no reply (VM out of memory?)`; console.log(`${tag.slice(3).padEnd(16)} DEAD`); break; }
        const [, name, status, kb, pre, ...err] = line.split(' ');
        const warn = oomWarn ? `  [${oomWarn}x VM "Out of memory", recovered]` : '';
        oomWarn = 0;
        peak = Math.max(peak, +kb);
        const extra = name.startsWith('compile:') ? `  (${sizes[name.slice(8)]} B source)` : '';
        console.log(`${name.padEnd(16)} ${status.padEnd(4)} ${kb.padStart(6)} KB  (pre-gc ${pre})${extra}${status === 'FAIL' ? '  ' + err.join(' ') : ''}${warn}`);
        if (status === 'FAIL') { failed = `${name}: ${err.join(' ')}`; break; }
    }
    await browser.close();
    console.log('');
    console.log(`max resident ${peak.toFixed(1)} KB` + (free === null ? '' : `, free heap after the run ~${free} KB`));
    if (failed) { console.log('FAIL at ' + failed); process.exit(1); }
    console.log(headless ? 'PASS (headless ladder)' : 'PASS (text-GUI ladder)');
}

run().catch(e => { console.error(e); process.exit(1); });
