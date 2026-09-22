// seq3 menu regression: root -> lane -> edit -> dims-dependency -> back -> lane2
// Event handshake: polls the EV line count per event (no timing guesses).
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
  throw new Error('event not delivered; tail: ' + outp.split('\n').slice(-3).join(' | '));
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
  await (await page.$('#canvas')).screenshot({ path: `/tmp/opencode/mt_${n}.png` });
  console.log('shot', n, '| luaerr:', JSON.stringify(await page.evaluate(() => Module.ccall('getLuaError','string',[],[]))));
};

await snap('0_root');
await press(2);                     // enter LANE 1
await snap('1_lane1');
await enc(+1);                      // TYPE note -> mod (SCALE/ROOT rows vanish)
await snap('2_type_mod');
await press(1);                     // cursor -> DIMS
await enc(+1);                      // 16x1 -> 8x2 (LEN/ADV -> XADV/YADV)
await snap('3_dims_8x2');
await press(3);                     // back to root
await snap('4_root_back');
await press(1); await press(2);     // LANE 2 -> enter (fresh state, CHAN 2)
await snap('5_lane2');
await browser.close();
