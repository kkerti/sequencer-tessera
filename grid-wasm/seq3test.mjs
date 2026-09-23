// seq3test.mjs -- run the seq-3 GUI, drive the faceplate controls, and
// screenshot each state. Usage: node seq3test.mjs [outdir]
import { chromium } from 'playwright';
import { readFileSync, readdirSync, writeFileSync } from 'fs';

const OUT = process.argv[2] || '/var/folders/j9/8qjrwyp932b28x4cgx2z797w0000gn/T/opencode/seq3gui';

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
    const browser = await chromium.launch({ headless: true });
    for (let attempt = 1; attempt <= 4; attempt++) {
        const page = await browser.newPage();
        const allMsgs = [];
        let aborted = null;
        page.on('console', msg => {
            const t = msg.text();
            allMsgs.push(t);
            if (t.startsWith('Aborted')) aborted = t;   // VM dead: frames frozen
            if (t.startsWith('DBG') || t.startsWith('PROBE') || t.includes('ready') || t.includes('ERR') ||
                t.includes('CMFAIL') || t.includes('memory')) console.log('[lua]', t.slice(0, 200));
        });
        await page.goto('http://localhost:8080/grid-wasm/index.html');
        await page.waitForFunction(() => typeof Module !== 'undefined' && typeof Module.ccall === 'function', { timeout: 15000 });
        try {
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
            await page.waitForTimeout(200);
            await page.evaluate(([i, lo]) => {
                document.getElementById('init_script').value = i;
                document.getElementById('loop_script').value = lo;
                document.getElementById('loadScriptButton').click();
            }, [m[1].trim(), l[1].trim()]);
            await page.evaluate(() => { if (Module.resumeMainLoop) Module.resumeMainLoop(); });
            await page.waitForTimeout(1200);

            async function shot(name) {
                if (aborted) {
                    console.log('SKIPPED', name, '-- VM dead:', aborted);
                    return;
                }
                await (await page.$('#canvas')).screenshot({ path: `${OUT}/${name}.png` });
                console.log('saved', name);
            }
            const key = async (i, hold = 150) => {
                const el = page.locator(`.ctrl[data-index="${i}"]`);
                await el.dispatchEvent('pointerdown');
                await page.waitForTimeout(hold);
                await el.dispatchEvent('pointerup');
                await page.waitForTimeout(400);
            };
            await shot('s1_overview');
            await key(1); await shot('s2_focus');           // View -> Focus
            const encUp = page.locator('#encUp');
            await encUp.click(); await page.waitForTimeout(300);
            await encUp.click(); await page.waitForTimeout(500);
            await shot('s3_focus_pitch_edited');
            await key(13); await shot('s4_focus_param2');   // enc press -> velocity
            await encUp.click(); await page.waitForTimeout(500);
            await shot('s5_vel_edited');
            await key(1); await shot('s6_overview_again');  // View -> Overview
            await key(0); await shot('s7_config_globals');  // Config from Overview
            await key(1); await shot('s8_back_overview');   // View backs out
            await key(1); await shot('s9_focus');
            await key(10); await shot('s10_lane2');         // BTN 10 -> lane 2 (trig 4x4)
            await browser.close();
            writeFileSync(process.argv[3] || '/var/folders/j9/8qjrwyp932b28x4cgx2z797w0000gn/T/opencode/seq3gui/console.log', allMsgs.join('\n'));
            if (aborted) {
                console.log('FAILED: VM aborted (' + aborted + ') — later screenshots are frozen frames. ' +
                    'Known heap-ceiling instability, see sequencer-3/docs/SCREENS.md §7.');
                process.exitCode = 1;
            } else {
                console.log('DONE');
            }
            return;
        } catch (e) {
            console.log('attempt ' + attempt + ' failed: ' + String(e).split('\n')[0].slice(0, 120));
            await browser.close();
        }
    }
    process.exit(1);
})();