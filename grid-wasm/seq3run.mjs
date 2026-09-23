// seq3run.mjs -- run the sequencer-3 GUI screen with the real core in the
// grid-wasm harness.
//
// The wasm VM's only JS->Lua channel is loadScript(init, loop) with ~2 KB
// strings, but the VM persists across calls and has `load()`. So: push each
// module's source into a global table as escaped string chunks (one
// loadScript call each), then run the screen file whose init installs a
// require shim over the module table.
//
// Usage: node seq3run.mjs <screen.lua> [out.png] [--keep]
// Requires: python3 -m http.server 8080 running from the repo root.

import { chromium } from 'playwright';
import { readFileSync, readdirSync } from 'fs';

const args = process.argv.slice(2);
const screenFile = args[0] || '../sequencer-3/screens/seq3_gui.lua';
const outFile = args.find(a => a.endsWith('.png')) || 'seq3.png';
const verbose = args.includes('--verbose');

// module name -> file. Names match the sources' require() calls.
//
// Default is the mock set: the full core's bytecode does not fit the harness
// VM heap alongside the GUI (see SCREENS.md). Pass --real to attempt the full
// core (may abort with "Out of memory" — recorded limitation).
const withReal = args.includes('--real');
const MODULES = withReal ? [
    ['engine',    '../sequencer-3/src/core/engine.lua'],
    ['sources',   '../sequencer-3/src/core/sources.lua'],
    ['scales',    '../sequencer-3/src/core/scales.lua'],
    ['lane',      '../sequencer-3/src/core/lane.lua'],
    ['transport', '../sequencer-3/src/core/transport.lua'],
    ['generate',  '../sequencer-3/src/core/generate.lua'],
    ['layout_core', '../layout-system/layout_core.lua'],
] : [
    ['layout_core', '../layout-system/layout_core.lua'],
];
const guiDir = new URL('../sequencer-3/gui/', import.meta.url).pathname;
try {
    for (const f of readdirSync(guiDir).filter(f => f.endsWith('.lua'))) {
        MODULES.push([f.replace(/\.lua$/, ''), '../sequencer-3/gui/' + f]);
    }
} catch { /* gui/ may not exist yet */ }

// JS string -> Lua double-quoted literal (safe for any bytes).
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

// Strip comments (heap in the VM is tight; comments are pure ballast).
// Char-scan per line, string-aware (" and ' with \-escapes).
function stripComments(src) {
    return src.split('\n').map(line => {
        let out = '', q = null;
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (q) {
                out += c;
                if (c === '\\') { out += line[++i] ?? ''; continue; }
                if (c === q) q = null;
            } else if (c === '"' || c === "'") { q = c; out += c; }
            else if (c === '-' && line[i + 1] === '-') break;
            else out += c;
        }
        return out.replace(/\s+$/, '').replace(/^\s+/, '');
    }).filter(l => l.length > 0).join('\n');
}

// Split a module source into Lua string chunks <= CHUNK bytes, each its own
// loadScript call. loadScript only STORES a script and the VM runs it on the
// next frame, so every chunk ends with a print() handshake the runner waits
// for before issuing the next call. 1600 raw bytes keeps the escaped init
// well under the ~2 KB budget (escapes can expand ~4x for control-heavy text;
// Lua sources are tame).
const CHUNK = 1600;
function chunked(name, src) {
    const calls = [];
    let first = true;
    for (let i = 0; i < src.length; i += CHUNK) {
        const piece = src.slice(i, i + CHUNK);
        const tag = name + ':' + i;
        const last = i + CHUNK >= src.length;
        // Pieces collect into a per-name array (never concatenated: the VM
        // heap cannot hold a ~20 KB source string). The last chunk installs
        // the module via load(reader): the reader hands out one piece per
        // call AND DROPS it, so pieces and the building bytecode never coexist.
        const tail = last
            ? ` local arr=MA[${luaStr(name)}] __C=__C or {} local ix=0 local f,e=load(function() ix=ix+1 local p=arr[ix] arr[ix]=nil return p end,${luaStr(name)},"t") __C[${luaStr(name)}]=f if not f then print("CMFAIL ${name} " .. tostring(e)) else print("CM ${name}") end MA[${luaStr(name)}]=nil collectgarbage()`
            : ` print("CD ${tag}")`;
        const init = (first
            ? `MA=MA or {} MA[${luaStr(name)}]={} `
            : ``)
            + `MA[${luaStr(name)}][#MA[${luaStr(name)}]+1]=${luaStr(piece)}` + tail;
        calls.push([init, '', (last ? 'CM ' + name : 'CD ' + tag)]);
        first = false;
    }
    return calls;
}

const screenCode = readFileSync(screenFile, 'utf-8');
const m = screenCode.match(/-- INIT START\n([\s\S]*?)-- INIT END/);
const l = screenCode.match(/-- LOOP START\n([\s\S]*?)-- LOOP END/);
if (!m || !l) { console.error('screen file needs -- INIT START/END and -- LOOP START/END'); process.exit(1); }

const calls = [];
let chunkOrdinal = 0;
for (const [name, file] of MODULES) {
    const src = stripComments(readFileSync(new URL(file, import.meta.url).pathname, 'utf-8'));
    const cs = chunked(name, src);
    // The VM heap is ~75 KB of Lua objects with a ~47 KB firmware baseline:
    // GC between chunk pushes keeps the transient string garbage in check.
    const withGc = cs.map(([init, loop, h], i) => {
        chunkOrdinal++;
        const gc = (chunkOrdinal % 5 === 0) ? ' collectgarbage()' : '';
        return [init + gc, loop, h];
    });
    calls.push(...withGc);
}
console.log(`preloading ${MODULES.length} modules in ${calls.length} loadScript calls`);

async function attempt(n) {
    const browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    let pendingResolve = null, pendingTag = null;
    page.on('console', msg => {
        const t = msg.text();
        if (pendingResolve && t === pendingTag) {
            const r = pendingResolve; pendingResolve = null; pendingTag = null; r();
            return;
        }
        const noisy = t.startsWith('grid_') || t.includes('font') || t.includes('stbtt') ||
            t === 'hello, world!' || t === 'hello world!' ||
            t.includes('requestAnimationFrame') || t.includes('Loaded screen manifest') ||
            t.startsWith('loadScript len') || t === 'LUA UI INIT FAILED: callback not registered' ||
            (!verbose && t.startsWith('CD ')) || t.includes('willReadFrequently');
        if (verbose || !noisy) console.log('[lua]', t.slice(0, 300));
    });

    await page.goto('http://localhost:8080/grid-wasm/index.html');
    await page.waitForFunction(
        () => typeof Module !== 'undefined' && typeof Module.ccall === 'function',
        { timeout: 15000 }
    );

    for (const [init, loop, handshake] of calls) {
        await page.evaluate(([i, lo]) => {
            Module.ccall('loadScript', 'void', ['string', 'string'], [i, lo]);
        }, [init, loop]);
        if (handshake) {
            pendingTag = handshake;
            await Promise.race([
                new Promise(resolve => { pendingResolve = resolve; }),
                new Promise((_, reject) => setTimeout(() => {
                    if (pendingTag === handshake) { pendingTag = null; pendingResolve = null; }
                    reject(new Error('handshake timeout: ' + handshake));
                }, 3000)),
            ]);
        }
    }
    await page.waitForTimeout(200);

    // probe: which modules compiled? does host have its methods?
    await page.evaluate(() => {
        Module.ccall('loadScript', 'void', ['string', 'string'],
            [`local ks = {} for k, v in pairs(__C or {}) do ks[#ks + 1] = k end table.sort(ks) print("PROBE compiled: " .. table.concat(ks, ","))
__L = __L or {}
local function req(n)
  if not __L[n] then __L[n] = __C[n]() end
  return __L[n]
end
require = req
local ok, e = pcall(function()
  req("layout_core") req("widgets")
  local h = req("host")
  return tostring(h._buildOverview) .. " / " .. tostring(h._refresh)
end)
print("PROBE host: " .. tostring(ok) .. " " .. tostring(e))`, '']);
    });
    await page.waitForTimeout(300);

    // final call: through the page's own path so buildControlScript()
    // injects the `grid` globals the loop needs.
    await page.evaluate(([i, lo]) => {
        document.getElementById('init_script').value = i;
        document.getElementById('loop_script').value = lo;
        document.getElementById('loadScriptButton').click();
    }, [m[1].trim(), l[1].trim()]);

    await page.evaluate(() => { if (Module.resumeMainLoop) Module.resumeMainLoop(); });
    await page.waitForTimeout(1500);
    await (await page.$('#canvas')).screenshot({ path: outFile });
    console.log('Saved:', outFile);
    await browser.close();
    return true;
}

(async () => {
    for (let n = 1; n <= 4; n++) {
        try { await attempt(n); return; } catch (e) {
            console.log('attempt ' + n + ' failed: ' + String(e).split('\n')[0].slice(0, 120));
        }
    }
    process.exit(1);
})();
