# gfx_testkit

Headless `gfx_*` stubs for testing [EigenScript](https://github.com/InauguralSystems/EigenScript)
UI code without a window. Load it before `lib/ui.eigs` (or any code that
draws) and every draw call lands in a recorder you can count and assert on.

It replaces the stub block that was copy-pasted into about 19 test files
across six repos (EigenScript#2170 census, `hq/reports/app-census-2170.md`
§7). This repo is `eigs-gfx-testkit`; the package name is `gfx_testkit`.

```eigenscript
load_file of "gfx_testkit.eigs"
load_file of "lib/ui.eigs"

gfx_testkit_record of true
render of [root, 0, 0]
gfx_testkit_expect of ["clip", 2]          # throws unless exactly 2
print of (gfx_testkit_calls of "text")      # args of every gfx_text call
```

## Consume

```sh
eigenscript --pkg add InauguralSystems/gfx_testkit https://github.com/InauguralSystems/eigs-gfx-testkit v0.1.0
```

This clones into `eigs_modules/gfx_testkit/` and pins the commit in
`eigs.lock.json`. Commit `eigs.json` and `eigs.lock.json`; CI reproduces the
tree with `eigenscript --pkg install` and checks it with
`eigenscript --pkg verify`.

**Load it; don't import it.** The stubs only work as global definitions
that shadow the `gfx_*` builtins for whatever is loaded after them.
`import gfx_testkit` would put them in a namespace, where `lib/ui.eigs`
never sees them.

**How the path resolves.** Write `load_file of "gfx_testkit.eigs"` from any
test file in the project. `load_file` and `import` share one resolution
chain: after the test file's own directory, the runtime walks up from that
directory looking for `eigs_modules/gfx_testkit/gfx_testkit.eigs` and stops
at the first directory with an `eigs.json`, the project root. So a test in
`test/` or `tests/sub/` finds the package without a `../`. (The
project-root form, `load_file of "eigs_modules/gfx_testkit/gfx_testkit.eigs"`,
also resolves.) A file named `gfx_testkit.eigs` next to the test would win
over the package, as any project file does.

**It is a test-only dependency**, but `eigs.json` has no way to say so
today: it goes in `deps` like any other package, and only test files load
it. The gap is filed upstream as [EigenScript#2213](https://github.com/InauguralSystems/EigenScript/issues/2213).

## What it stubs

| Call | Behaviour |
|---|---|
| `gfx_open`, `gfx_close`, `gfx_clear`, `gfx_rect`, `gfx_rrect`, `gfx_line`, `gfx_point`, `gfx_circle`, `gfx_text`, `gfx_present` | Counted; logged as `[kind, args]` while recording is on. `gfx_open` returns 1, the rest null. |
| `gfx_clip` | As above, and the current clip is kept (`gfx_clip of null` clears it). |
| `gfx_poll` | The next queued event whose frame has been reached, else null. |
| `gfx_delay` | Advances the frame counter by one. No time passes. |
| `gfx_ticks` | A clock that adds a step per call (default: first call 1000, then +1000). |
| `gfx_text_width`, `gfx_text_height` | The 5x7 bitmap-font math (`len * 6 * scale`, `7 * scale`), or null with metrics off. |
| `win_key` | The next queued EigenOS key code, else -1. |

Every stub takes one parameter, so any call shape binds: `gfx_rect of
[x, y, w, h, r, g, b]`, `gfx_clip of null` and `gfx_delay of 8` all work.

## API

| Function | Does |
|---|---|
| `gfx_testkit_record of on` | Start (`true`) or stop logging. Off by default. Counting is always on. |
| `gfx_testkit_count of kind` | Calls of one stub since the last reset (`"rect"`, `"poll"`, `"text_width"`, ...). |
| `gfx_testkit_expect of [kind, n]` | Returns true, or throws `gfx_testkit: expected n kind call(s), got m`. |
| `gfx_testkit_calls of kind` | The args of each logged call of that kind, in order. |
| `gfx_testkit_log of []` | Every logged `[kind, args]` pair. |
| `gfx_testkit_clip of []` | The clip rect last set, or null. |
| `gfx_testkit_ticks of [start, step]` | Configure the clock. `step` 0 makes it constant at `start`. |
| `gfx_testkit_metrics of on` | Text metrics on (default) or off. Call it **before** loading `lib/ui.eigs`: the toolkit probes once, at load, and with metrics off it takes its own fallback. |
| `gfx_testkit_feed of [frame, event]` | Queue an event for `gfx_poll` once `frame` delays have passed. Feed in frame order. |
| `gfx_testkit_key of code` | Queue a key code for `win_key`. |
| `gfx_testkit_reset of []` | Forget calls, log, clip, tape, keys and frames, and restart the clock. Settings are kept. |

State lives in one global dict, `GFXTK`; `GFXTK_OUTPUT_KINDS` lists the
logged kinds.

## Per-consumer settings

The union of the six consumers' stub behaviour, and what each needs:

| Consumer | Its stub block | Special requirement | Setting |
|---|---|---|---|
| liferaft, eddy, EigenRegex | `test_viz_ui.eigs`, `test_explorer_ui.eigs`, `test_s12_tester_ui.eigs` | Clock +1000 per call; deterministic bitmap metrics | none (the defaults) |
| DeslanStudio | 11 `tests/test_*_view.eigs` and friends | Clock must advance (+500) so two clicks are never read as a double-click; a gated recorder (`DRAW.on`); no metric stubs, so the toolkit's fallback | `gfx_testkit_ticks of [0, 500]`, `gfx_testkit_record of true`, `gfx_testkit_metrics of false` |
| EigenScript | `tests/test_ui.eigs` | Gated recorder off by default, clip recorded; constant clock 1000; bitmap metrics | `gfx_testkit_ticks of [1000, 0]` |
| EigenOS | `tools/*_twin_hosted.eigs` | Frame-keyed `gfx_poll` tape stepped by `gfx_delay`; `win_key` queue returning -1 when empty; a clock with its own step (+50) | `gfx_testkit_feed`, `gfx_testkit_key`, `gfx_testkit_ticks of [0, 50]` |

Not in this package, because they are not gfx: DeslanStudio's `audio_*`
stubs (`tests/test_shell.eigs`) and EigenOS's `task_*` scheduler stubs
(`desktop_twin_hosted.eigs`). They stay in those tests.

What a stub cannot see: anything the C renderer does. These stubs prove
control flow and structure; only decoding real pixels (`gfx_read`, the
xwd glyph decoders) proves what the user sees (EigenScript#599).

## Develop

```sh
eigenscript tests/test_gfx_testkit.eigs   # unit tests, every stub
bash tests/test_smoke.sh                  # consumer-shaped: eigs_modules + real lib/ui.eigs
bash tests/plant_drop.sh                  # each stub planted to drop its call; tests must go red
bash tools/check_tmp_eigs_json.sh         # TMP plants mention eigs.json (EigenScript #1106)
```

CI builds EigenScript from source and runs all four on every push and PR.

## Publish

A release is a git tag (`v0.1.0`); consumers' lockfiles pin the commit.
Cut a new tag rather than moving one.

## License

MIT, see [LICENSE](LICENSE).
