// screenshot.mjs -- load a screen .lua file and screenshot the canvas
// Usage: node screenshot.mjs [lua-file] [slider-value] [output.png]
// Defaults: screens/pattern.lua, slider=128, screenshot.png
//
// Prerequisites: python3 -m http.server 8080 running from project root

import { chromium } from 'playwright';
import { readFileSync } from 'fs';

const luaFile = process.argv[2] || '../screens/pattern.lua';
const sliderVal = parseInt(process.argv[3] || '128');
const outFile = process.argv[4] || 'screenshot.png';

const code = readFileSync(luaFile, 'utf-8');
let initCode = '';
let loopCode = '';

const initMatch = code.match(/-- INIT START\n([\s\S]*?)-- INIT END/);
const loopMatch = code.match(/-- LOOP START\n([\s\S]*?)-- LOOP END/);

if (initMatch && loopMatch) {
    initCode = initMatch[1].trim();
    loopCode = loopMatch[1].trim();
} else {
    console.error('Could not find -- INIT START/END and -- LOOP START/END markers');
    process.exit(1);
}

// Mirror the harness's buildControlScript() so screen init code that reads
// uiControlDown/uiControlPressed/etc doesn't crash on nil indexing.
function luaIdxArr(n) {
    const parts = [];
    for (let i = 0; i < n; i++) parts.push(`[${i}]=0`);
    return '{' + parts.join(',') + '}';
}
const sliderInit =
    `sliderValue=${sliderVal}\n` +
    `uiEncoderIndex=8\n` +
    `uiEncoderDelta=0\n` +
    `uiEncoderTicks=0\n` +
    `uiLastEventIndex=-1\n` +
    `uiLastEventDelta=0\n` +
    `uiControlDown=${luaIdxArr(13)}\n` +
    `uiControlPressed=${luaIdxArr(13)}\n` +
    `uiControlReleased=${luaIdxArr(13)}\n`;
console.log(`File: ${luaFile} | Init: ${initCode.length}b | Loop: ${loopCode.length}b | Slider: ${sliderVal}`);

if (initCode.length > 2040) {
    console.warn(`WARNING: Init code is ${initCode.length} bytes, exceeds ~2048 byte WASM limit!`);
}

(async () => {
    const browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();

    page.on('console', msg => {
        const t = msg.text();
        if (t.includes('error') || t.includes('Error') || t.includes('FAIL')) {
            console.log('[ERR]', t);
        }
    });

    await page.goto('http://localhost:8080/grid-wasm/index.html');
    await page.waitForFunction(
        () => typeof Module !== 'undefined' && typeof Module.ccall === 'function',
        { timeout: 15000 }
    );

    await page.evaluate(([i, l]) => {
        Module.ccall('loadScript', 'void', ['string', 'string'], [i, l]);
    }, [sliderInit + initCode, loopCode]);

    await page.waitForTimeout(1500);

    // Check output for init confirmation
    const output = await page.evaluate(() => document.getElementById('output').value);
    const lines = output.split('\n').filter(l =>
        !l.startsWith('grid_') && !l.startsWith('spacemono') && !l.startsWith('stbtt') &&
        !l.startsWith('hello') && !l.startsWith('LUA UI') && !l.startsWith('Canvas2D') &&
        !l.startsWith('loadScript') && l.trim()
    );
    const unique = [...new Set(lines)];
    if (unique.length > 0) {
        console.log('Lua output:', unique.slice(0, 5).join(' | '));
    }

    await (await page.$('#canvas')).screenshot({ path: outFile });
    console.log(`Saved: ${outFile}`);

    await browser.close();
})();
