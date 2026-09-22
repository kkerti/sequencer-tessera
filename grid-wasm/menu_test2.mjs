// drive into the GEN submenu (deeper level), exercise scroll + GEN NOW action.
// Event handshake: every harness event bumps RC and prints an EV line, so the
// test polls the output textarea per event -- no timing guesses.
import { chromium } from 'playwright';
import { readFileSync } from 'fs';
const code = readFileSync('/tmp/opencode/seq3_menu_ev.lua', 'utf-8');
const init = code.match(/-- INIT START\n([\s\S]*?)-- INIT END/)[1].trim();
const loop = code.match(/-- LOOP START\n([\s\S]*?)-- LOOP END/)[1].trim();
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();
await page.goto('http://localhost:8080/grid-wasm/index.html');
await page.waitForFunction(() => { const o = document.getElementById('output'); return o && o.value.indexOf('hello') !== -1; }, { timeout: 15000 });
await page.evaluate(([i, l]) => {
  document.getElementById('init_script').value = i;
  document.getElementById('loop_script').value = l;
  reloadScript();
}, [init, loop]);
await page.waitForTimeout(300);
const evCount = async () => await page.evaluate(() =>
  document.getElementById('output').value.split('\n').filter(l => l.startsWith('EV')).length);
const waitEv = async (n) => {
  for (let i = 0; i < 40; i++) { if (await evCount() >= n) return; await page.waitForTimeout(50); }
  const outp = await page.evaluate(() => document.getElementById('output').value);
  console.log('[FAIL] tail:', outp.split('\n').slice(-12).join(' | '));
  console.log('[FAIL] luaerr:', JSON.stringify(await page.evaluate(() => Module.ccall('getLuaError','string',[],[]))));
  console.log('[FAIL] pressed:', JSON.stringify(await page.evaluate(() => ({ p2: gridState.pressed[2], evt: gridState.eventIndex + ':' + gridState.eventValue }))));
  throw new Error('event not delivered');
};
const press = async (i) => {
  const n = await evCount();
  await page.evaluate((k) => pressButton(k), i);
  await waitEv(n + 1);
  await page.evaluate((k) => releaseButton(k), i);
  await waitEv(n + 2);
};
const enc = async (d) => {
  const n = await evCount();
  await page.evaluate((d) => { d > 0 ? document.getElementById('encUp').click() : document.getElementById('encDown').click(); }, d);
  await waitEv(n + 1);
};
const snap = async (n) => {
  await page.waitForTimeout(120);
  await (await page.$('#canvas')).screenshot({ path: `/tmp/opencode/mt2_${n}.png` });
  console.log('shot', n, '| luaerr:', JSON.stringify(await page.evaluate(() => Module.ccall('getLuaError','string',[],[]))));
};

await press(2);                                    // enter LANE 1
for (let k = 0; k < 8; k++) await press(1);        // -> GEN row (9th, scrolled)
await snap('0_gen_row');
await press(2);                                    // enter GEN submenu
await snap('1_gen_menu');
await enc(+1);                                     // KIND gamut -> euclid (HITS replaces SPREAD on re-enter)
await press(3); await press(2);                    // back out, re-enter -> rebuilt node
await snap('1b_gen_euclid');
for (let k = 0; k < 3; k++) await press(1);        // -> HITS row
await enc(+1);                                     // HITS 4 -> 5
await snap('2_hits');
for (let k = 0; k < 4; k++) await press(1);        // -> GEN NOW (last row, scrolls)
await press(2);                                    // GEN NOW
await snap('3_gen_now');
await browser.close();
