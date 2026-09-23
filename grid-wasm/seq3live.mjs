// seq3live.mjs -- open a HEADED browser with the seq-3 GUI running for
// interactive use: module preloader + screen, then leave the browser open.
// The faceplate controls (keys, encoder, screen buttons) drive the GUI.
// Usage: node seq3live.mjs   (Ctrl-C to quit)
import { chromium } from 'playwright';
import { readFileSync, readdirSync } from 'fs';

// module name -> file. Names match the sources' require() calls.
const MODULES = [['layout_core', '../layout-system/layout_core.lua']];
const guiDir = new URL('../sequencer-3/gui/', import.meta.url).pathname;
for (const f of readdirSync(guiDir).filter(f => f.endsWith('.lua'))) {
    MODULES.push([f.replace(/\.lua$/, ''), '../sequencer-3/gui/' + f]);
}

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

function stripComments(src) {
    return src.split('\n').map(line => {
        let out = '', q = null;
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (q) { out += c; if (c === '\\') { out += line[++i] ?? ''; continue; } if (c === q) q = null; }
            else if (c === '"' || c === "'") { q = c; out += c; }
            else if (c === '-' && line[i + 1] === '-') break;
            else out += c;
        }
        return out.replace(/\s+$/, '').replace(/^\s+/, '');
    }).filter(l => l.length > 0).join('\n');
}

const CHUNK = 1600;
function chunked(name, src) {
    const calls = [];
    let first = true;
    for (let i = 0; i < src.length; i += CHUNK) {
        const piece = src.slice(i, i + CHUNK);
        const tag = name + ':' + i;
        const last = i + CHUNK >= src.length;
        const tail = last
            ? ` local arr=MA[${luaStr(name)}] __C=__C or {} local ix=0 local f,e=load(function() ix=ix+1 local p=arr[ix] arr[ix]=nil return p end,${luaStr(name)},"t") __C[${luaStr(name)}]=f if not f then print("CMFAIL ${name} " .. tostring(e)) else print("CM ${name}") end MA[${luaStr(name)}]=nil collectgarbage()`
            : ` print("CD ${tag}")`;
        const init = (first ? `MA=MA or {} MA[${luaStr(name)}]={} ` : ``)
            + `MA[${luaStr(name)}][#MA[${luaStr(name)}]+1]=${luaStr(piece)}` + tail;
        calls.push([init, '', (last ? 'CM ' + name : 'CD ' + tag)]);
        first = false;
    }
    return calls;
}

const screenCode = readFileSync(new URL('../sequencer-3/screens/seq3_gui.lua', import.meta.url), 'utf-8');
const m = screenCode.match(/-- INIT START\n([\s\S]*?)-- INIT END/);
const l = screenCode.match(/-- LOOP START\n([\s\S]*?)-- LOOP END/);

(async () => {
    const browser = await chromium.launch({ headless: false });
    const page = await browser.newPage();
    page.on('console', msg => {
        const t = msg.text();
        if (t.includes('ready') || t.includes('ERR') || t.includes('CMFAIL')) console.log('[lua]', t.slice(0, 200));
    });
    await page.goto('http://localhost:8080/grid-wasm/index.html');
    await page.waitForFunction(() => typeof Module !== 'undefined' && typeof Module.ccall === 'function', { timeout: 15000 });

    for (const [name, file] of MODULES) {
        const src = stripComments(readFileSync(new URL(file, import.meta.url).pathname, 'utf-8'));
        for (const [init, , tag] of chunked(name, src)) {
            await page.evaluate(([i2]) => { Module.ccall('loadScript', 'void', ['string', 'string'], [i2, '']); }, [init]);
            await new Promise(res => {
                const to = setTimeout(res, 2500);
                page.once('console', function h(msg) {
                    if (msg.text() === tag || msg.text().startsWith('CMFAIL')) { clearTimeout(to); res(); }
                    else page.once('console', h);
                });
            });
        }
    }
    await page.evaluate(([i, lo]) => {
        document.getElementById('init_script').value = i;
        document.getElementById('loop_script').value = lo;
        document.getElementById('loadScriptButton').click();
    }, [m[1].trim(), l[1].trim()]);
    await page.evaluate(() => { if (Module.resumeMainLoop) Module.resumeMainLoop(); });
    console.log('seq-3 GUI live — use the faceplate controls in the browser.');
})();