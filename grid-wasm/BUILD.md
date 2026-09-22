# grid-wasm — VM binaries: how to rebuild

`index.js` / `index.wasm` are gitignored; they are built from the Intech
firmware repo ([grid-fw](https://github.com/intechstudio/grid-fw)), whose `wasm/`
target compiles the real device Lua VM (Lua 5.5) + LCD renderer to WebAssembly.
No Docker or ESP toolchain needed — only emsdk, cmake, xxd, git.

The harness VM carries a local patch (`grid-fw-wasm-main.patch`) against
`wasm/main.c` — upstream caps BOTH script chunk buffers at 2048 bytes
(strcpy overflow on larger screens) and starts Lua with a 200 KB heap / 2048
allocation blocks, which is not enough for screen scripts that inline the
layout system. The patch (harness-only; the device VM is untouched):

- `grid_lua_init_script` / `grid_lua_loop_script`: 2048 -> 16384 bytes each
- `LUA_MEM_SIZE`: 200000 -> 2097152
- `ta_init` heap blocks: 2048 -> 8192
- adds `getLuaError()` / `getLuaOutput()` exports (Lua errors are stored in an
  internal string and otherwise invisible from the page)

## Rebuild

```sh
git clone --depth 1 https://github.com/intechstudio/grid-fw.git
git clone --depth 1 https://github.com/emscripten-core/emsdk.git
cd emsdk && ./emsdk install latest && ./emsdk activate latest && source emsdk_env.sh
cd ../grid-fw
git apply <path-to>/grid-wasm/grid-fw-wasm-main.patch
./lua_build.sh                # converts embedded Lua scripts to C headers
./wasm_build.sh               # emcmake + cmake; outputs wasm/build/index.{html,js,wasm}
cp wasm/build/index.js wasm/build/index.wasm <this repo>/grid-wasm/
```

## Test

```sh
cd <repo root> && python3 -m http.server 8080
cd grid-wasm
node screenshot.mjs ../sequencer-2/screens/seq2_screen.lua 128 shot.png   # smoke test
node menu_test.mjs    # seq3 menu GUI regression (requires seq3_menu_ev.lua, see below)
node menu_test2.mjs
```

The menu tests run against an EV-instrumented build of the generated screen
(each harness event prints an `EV` line, which the tests poll as a per-event
handshake). Regenerate it from `sequencer-3/ui/seq3_menu.lua` by appending a
`print('EV', ...)` after `local i = grid.event_index` in the loop block.

Note: the page-level readiness race is handled in `index.html` /
`screenshot.mjs` — `Module.ccall` exists before the wasm VM finishes booting;
wait for the `hello, world!` boot print instead.