<p align="center">
  <img src="docs/screenshots/en/01-workflows.png" width="23%" alt="Workflow list" />
  &nbsp;
  <img src="docs/screenshots/en/03-config.png" width="23%" alt="Parameter form" />
  &nbsp;
  <img src="docs/screenshots/en/02-run.png" width="23%" alt="Run page" />
  &nbsp;
  <img src="docs/screenshots/en/07-gallery.png" width="23%" alt="Local gallery" />
</p>

<div align="center">

<h1>ComfyUI Pocket</h1>

<p><strong>Your ComfyUI server is already running — this app lets you pick parameters, submit jobs and collect results from your phone.</strong></p>

<p>Connect to your server, browse its workflows, turn the parameters you care about into a form, submit a job with one tap, watch the progress live and get the results back in your phone's album.</p>

<p>
  <a href="https://github.com/Volitasa/ComfyUI-MobilePocket/releases/latest"><b>⬇️ Download APK</b></a>
  ·
  <a href="#three-steps-to-your-first-image"><b>🚀 Quick start</b></a>
  ·
  <a href="#7-troubleshooting"><b>❓ Troubleshooting</b></a>
  ·
  <a href="#11-roadmap"><b>🗺️ Roadmap</b></a>
</p>

<p><a href="README.md">简体中文</a> ｜ <b>English</b></p>

<p>
  <img src="https://img.shields.io/badge/version-1.3.0-2ea043?style=flat-square" alt="version">
  <img src="https://img.shields.io/badge/platform-Android-3ddc84?style=flat-square&logo=android&logoColor=white" alt="platform">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/ComfyUI-compatible-8957e5?style=flat-square" alt="ComfyUI">
</p>

</div>

<p align="center"><i>Captured on an Android emulator: workflow list → parameter form → job progress → local gallery</i></p>

> Every screenshot in this document was taken from the app actually running on an Android emulator: `docs/screenshots/en` for the English UI, `docs/screenshots/zh` for the Chinese UI.

**The only prerequisite**: your phone can reach the machine that runs ComfyUI (same Wi-Fi LAN, or a tunnel / public mapping). As long as the server is up.

## Connect and go: what you no longer have to do

| The usual hassle | What this app does instead |
| --- | --- |
| Converting a canvas-saved workflow into API-format JSON before you can run it on a phone | **Don't convert it.** Workflows on the server — including the UI format the ComfyUI canvas saves — are parsed into a runnable structure inside the app: tap "parse" and run |
| Sending JSON files over to your phone | **Don't send anything.** Refresh and you get every workflow in the server's `userdata/workflows/` |
| Installing plugins, opening an SSH session, memorising node IDs | **None of that.** If you saved the workflow on your PC, the phone can see it. Installing [ComfyUI-AutoSaveAPI](https://github.com/Volitasa/ComfyUI-AutoSaveAPI) only adds an extra "ready to run" copy that skips the parse — it is **not required** |

## Core capabilities

1. **Connect and run** — type the server address and the workflow list appears; UI-format workflows are parsed into a runnable structure inside the app; local JSON can be imported too.
2. **Parameters become a form** — node parameters are detected automatically; tick what you want to tweak, give it an alias, and the run page renders the right control (text / seed / int / float / toggle / dropdown / image). **Model and sampler dropdowns are filled with the options that actually exist on the server**, so you can switch models without going back to the PC. The config page only shows what's already in your form; everything else lives in "Add parameters", grouped by purpose so even node-heavy workflows stay readable.
3. **Results land on your phone** — live WebSocket progress and five task states; outputs are downloaded into an on-device gallery (PNG metadata preserved, so you can drop them back into ComfyUI) and can be saved to your album; every history entry can be replayed with "Run again".

**One thing in the pipeline**: running workflows through RunningHub — see [Roadmap](#11-roadmap).

## Three steps to your first image

1. **Install the APK** → open it and go to **Settings → Server connections → Add**, type the address (e.g. `http://192.168.1.100:8188`) and save. The first connection activates automatically; the badge in the top bar turns green once you're connected.
2. **Workflows tab** → tap your workflow → the config page **has already picked a set of common parameters for you**; add missing ones from "Add parameters", give them memorable names → save. For UI format, tap "parse" first (the first time loads the server's frontend — a few seconds to a dozen).
3. **Tap "Generate"** → it jumps to History and you watch it go from "Queued" to "Completed" → tap the thumbnail to view it full size and save it to your album.

Want another take? Go back to History, tap **Run again** on that card — the form and every value are already in place.

---

## Contents

- [1. Full feature list](#1-full-feature-list)
- [2. Before you start](#2-before-you-start)
- [3. Install and connect for the first time](#3-install-and-connect-for-the-first-time)
- [4. UI tour](#4-ui-tour)
- [5. Feature guide](#5-feature-guide)
  - [5.1 Connection management](#51-connection-management)
  - [5.2 The three sources of a workflow](#52-the-three-sources-of-a-workflow)
  - [5.3 Parameter configuration panel](#53-parameter-configuration-panel)
  - [5.4 Run page](#54-run-page)
  - [5.5 Task tracking](#55-task-tracking)
  - [5.6 History and run-again](#56-history-and-run-again)
  - [5.7 Workflow snapshots](#57-workflow-snapshots)
  - [5.8 Gallery and saving to your album](#58-gallery-and-saving-to-your-album)
  - [5.9 Settings](#59-settings)
  - [5.10 In-app updates](#510-in-app-updates)
- [6. How the pieces fit together](#6-how-the-pieces-fit-together)
- [7. Troubleshooting](#7-troubleshooting)
- [8. Known limitations](#8-known-limitations)
- [9. Tech stack and project layout](#9-tech-stack-and-project-layout)
- [10. Development, testing and releases](#10-development-testing-and-releases)
- [11. Roadmap](#11-roadmap)

---

## 1. Full feature list

The three headline capabilities are at the top of this page; here is everything, with details in [5. Feature guide](#5-feature-guide).

| Feature | What it does |
| --- | --- |
| Multiple servers | Save any number of servers (home LAN / office), each with a **primary + backup address**; falls back automatically when the primary is unreachable |
| Three workflow sources | Server `_api.json` runs directly; server UI-format JSON is **parsed into the API structure inside the app**; local JSON files can be imported |
| Parameters become a form | Node parameters are recognised through a **data-driven rule table**; tick what to expose, give it an alias, and the run page renders the right control (text / seed / int / float / toggle / dropdown / image). The config page main view holds only selected parameters; everything else lives in "Add parameters", grouped by purpose, with search, expand-all/collapse-all and per-node select-all |
| Dropdowns with real option lists | On opening the run page, the app asks the server once; dropdowns for models (Checkpoint / UNET / CLIP / VAE / LoRA / ControlNet), samplers and schedulers are then filled with the **list that really exists on the server**, with a manual refresh in the top-right corner. If the model written in the workflow is missing there, it is flagged and submission is blocked |
| Live progress | Progress is pushed over WebSocket, showing the node currently executing plus a percentage; reconnects automatically and reconciles with the server, **including when the app returns to the foreground** |
| Five task states | Queued / Running / Completed / Failed / Interrupted, with the server's actual error message shown on failure |
| Run again | Every run freezes a snapshot, so any history entry can restore the exact form and values it was run with — one tap to run it again |
| History search & filter | Search history by workflow name, prompt text or parameter alias; filter by 5 statuses; each hit explains *why* it matched |
| Local gallery | Outputs are downloaded into the app sandbox with **original PNG metadata preserved** (droppable back into ComfyUI); full-screen viewer and video playback |
| Save to album | Choose between "original image with workflow" and "plain image with metadata stripped" |
| Chinese / English UI | Follow the system language or pin it to Chinese or English; persisted data never stores display strings, so switching languages never affects your history |
| In-app updates | Manually check GitHub Releases, download the APK and hand it to the system installer (works with private and public repos alike) |

---

## 2. Before you start

**Only one thing**: a running ComfyUI that your phone can reach. The app talks to it over HTTP and WebSocket and probes with `GET /system_stats` on startup (so the server needs to be up).

The plugin is **optional**: [ComfyUI-AutoSaveAPI](https://github.com/Volitasa/ComfyUI-AutoSaveAPI) additionally exports an `_api.json` when you **save** a workflow — the "ready to run" copy, which skips the in-app parse. **Everything works without it** — workflows you normally save on your PC already live in the server's `userdata/workflows/`, and the app lists and parses them.

The two JSON formats are good to know about; the app works out which path to take by itself:

| Format | What it looks like | How the app treats it |
| --- | --- | --- |
| **API format** (filename ends with `_api.json`) | Keyed by **node ID**, each entry has `class_type` and `inputs` | **Runs directly** (no parsing) |
| **UI format** (a normal `*.json`) | Top level is `nodes` / `links` arrays — what the ComfyUI canvas saves | **One tap on "parse"** and it runs (see [5.2](#52-the-three-sources-of-a-workflow)) |

---

## 3. Install and connect for the first time

1. Download the latest APK and install it (Android will ask you to allow installs from unknown sources).
2. Open the app, go to **Settings → Server connections → Add server**.
3. Fill in:
   - **Name**: for your own reference, e.g. "Home 4090"
   - **Primary address**: e.g. `http://192.168.1.100:8188`
   - **Backup address** (optional): e.g. a tunnel address. Tried automatically when the primary fails
4. Tap **Test connection**, then **Save**. The first connection becomes active automatically.
5. Back on the **Workflows** tab the status badge turns green once connected (it requires both a successful HTTP probe **and** an established WebSocket).

> Tip: on every launch the app first retries the last address that worked (fast path), and only falls back to the full primary/backup probing when that fails — so day-to-day opening feels instant.

---

## 4. UI tour

Four tabs at the bottom:

| Tab | What it's for |
| --- | --- |
| **Workflows** | Pick a workflow, configure parameters, open the run page. The top has a "Server / Local" switch |
| **History** | Every job you submitted: status, results, search, filters, run again, delete |
| **Gallery** | Everything downloaded to this device, in a grid |
| **Settings** | Language, server connections, workflow storage, snapshots, GitHub token, about & updates |

A **connection status badge** (server name + status dot) sits in the top bar; tapping it jumps straight to the server config page.

<p align="center">
  <img src="docs/screenshots/en/01-workflows.png" width="23%" />
  &nbsp;
  <img src="docs/screenshots/en/05-history.png" width="23%" />
  &nbsp;
  <img src="docs/screenshots/en/07-gallery.png" width="23%" />
  &nbsp;
  <img src="docs/screenshots/en/10-settings.png" width="23%" />
</p>

<p align="center"><i>The four tabs, left to right: Workflows / History / Gallery / Settings</i></p>

---

## 5. Feature guide

### 5.1 Connection management

Any number of server profiles, each with a primary and an optional backup address; the primary failing falls back to the backup.

**What you can do**

- Save as many server profiles as you like; exactly one is active at a time.
- Each profile has a primary and a backup address, probed in order, first one that answers wins.
- "Test connection" works on a profile without changing which one is active.
- Tap a card to make it active; the app re-probes and refreshes the workflow list.

**Key behaviours**

| Action | What happens |
| --- | --- |
| Switching servers | Clears the workflow list and the current workflow cache; **does not** touch history, gallery or local workflows |
| Deleting a server | Disconnects, and **also cleans up the parse cache belonging to that server** (those entries could never be validated again) |
| Disconnected | WebSocket retries every 3 seconds for as long as the profile is still active |
| Reconnect succeeds | Re-fetches the workflow list and reconciles every non-final task |

<p align="center">
  <img src="docs/screenshots/en/11-servers.png" width="45%" />
</p>

<p align="center"><i>Server config: tap a card to activate, pencil to edit, bin to delete</i></p>

### 5.2 The three sources of a workflow

This is the **first cornerstone** of the whole app. Workflows come from three places; they have different origins, so they support different operations:

```mermaid
flowchart LR
    A["Server _api.json<br/>just refresh"] --> D["Normalised to an API prompt<br/>node id → class_type + inputs"]
    B["Server UI JSON<br/>needs parsing"] -->|"WebView reuses the ComfyUI frontend"| D
    C["Local imported JSON<br/>your own file"] --> D
    D --> E["Config panel: tick the parameters to expose"]
    E --> F["Run page: fill in → POST /prompt"]
```

| Source | Where it lives | Regenerable? | Available actions |
| --- | --- | --- | --- |
| Server `_api.json` | Server only; the app stores just the parameter config and a content hash | Yes (refresh) | Refresh / reconfigure nodes / **save to local library** |
| Parsed server UI JSON | Parse result cached on device (key: server + filename) | Yes (parse again) | Parse / re-parse / **clear parse cache** (never "delete") |
| Local import | Stored in full on device | **No** (delete means gone) | Rename / reconfigure nodes / **delete** |

> Design principle: **deletable ⇔ re-obtainable from the source.** If the source can give it back, you don't get a "delete", you get a "re-sync". Only things that would be gone forever get full create/update/delete.

#### Server side: grouped by format

- **API workflows · ready to run**: tap to configure parameters or go straight to the run page.
- **UI workflows · need parsing**: parse manually the first time. Once parsed they are equivalent to API entries — configurable and runnable.
- **No plugin needed**: what the ComfyUI canvas normally saves *is* UI format, so one parse is all it takes. With AutoSaveAPI installed the same workflow appears twice — pick the `_api.json` copy to skip the parse step.

Each card shows a status:

| Status | Meaning | Visual |
| --- | --- | --- |
| Not configured / not parsed yet | No parameter config saved | Grey subtitle |
| N parameters configured | Ready; tapping goes to the run page | Normal |
| Content updated, please reconfirm | The workflow content on the server changed, old parameters may no longer fit | Card turns amber |
| Server has an update (UI workflow) | The UI JSON changed, you can re-parse | Card turns amber |

The second line of each card shows the **last run time** (from the local history; "Never run" if it hasn't). When you're hunting for a workflow, "which one did I run last" is often easier to recognise than the name. The list uses compact single-line cards — a screen fits about a dozen.

> **How does it know the server changed?** Every configured workflow stores a content hash. Refreshing re-fetches the content and compares, so server-side edits are detected instead of you silently running against stale parameters.

#### Local side: your own assets

- Tap **Import workflow JSON** to pick an API-format JSON from your phone (importing the same file twice reuses the same config instead of duplicating).
- The menu offers **rename**, **reconfigure nodes** and **delete** (deleting also drops its parameter config).
- Local workflows are **independent of any server** — they may or may not run on the currently connected server (models/plugins may differ), and the app makes no promise about that.

#### "Save to local library"

Any server workflow can be saved to the device at any time, becoming your private asset — for example when the server copy gets broken or deleted, you still have one.

<p align="center">
  <img src="docs/screenshots/en/01-workflows.png" width="45%" />
  &nbsp;
  <img src="docs/screenshots/en/14-local.png" width="45%" />
</p>

<p align="center"><i>Left: server side (grouped by API / UI format)　Right: local side (your assets + import entry)</i></p>

### 5.3 Parameter configuration panel

Pull node parameters out of the workflow and turn them into a phone form. Open it by tapping a **not-yet-configured** workflow, or choosing "reconfigure nodes" from any card menu.

**Two layers, each doing one job**

- **The main view only shows what's already in your form**: a header line "17 of 18 in your form", then a flat list — one row per parameter (alias + type and current value), with an × to remove it from the form. One screen, check it, save. Renaming or removing only changes the phone form, never the workflow itself.
- **"Add parameters" holds everything**: every parameter lives in this layer, **grouped by purpose** (Prompt / Sampling / Size / Model and weights / Fine control / Other nodes), with per-node collapsible cards. Search, bulk expand/collapse and per-node select-all all live here.

**What it does**

1. Walks every node in the workflow and asks the **built-in rule table** which parameters are worth exposing.
2. Decides the type: the **server's node specs** (`/object_info`) come first — dropdown, toggle or number is decided by them; when specs are unavailable it falls back to name/value inference and says so with a banner at the top.
3. Skips **link references** (values shaped like `["nodeId", 0]`) — those aren't yours to fill in.
4. Selected parameters go to the main view, the rest stay in "Add parameters" — **coverage is never narrowed away**: for nodes the rule table doesn't know, every fillable parameter is still listed (that's what covers community nodes and `LoadImage`'s upload box).

**Same-name nodes, told apart by wiring**: when a workflow has two `CLIPTextEncode` nodes (positive and negative prompts), the card header in "Add parameters" carries a hint — the one wired to the sampler's `positive` slot says "Positive conditioning", the `negative` one says "Negative conditioning"; model / LoRA loaders show **which asset they load** (e.g. `add_detail`). All of it is read from the workflow's own links and parameter values — the app doesn't guess.

**What's covered**: the rule table is grouped by *purpose*, not by class name (the same feature has different class names on different machines):

| Group | Covered nodes |
| --- | --- |
| Samplers | `KSampler`, `KSamplerAdvanced`, `SamplerCustom(Advanced)`, `BasicScheduler`, `KSamplerSelect` |
| Text / prompts | `CLIPTextEncode`, `Text Multiline`, `Text box`, `String Input`, `Text Input`, `PrimitiveStringMultiline`, `Text Concatenate` |
| Size / upscale | `EmptyLatentImage`, `EmptySD3LatentImage`, `EmptyFluxLatentImage`, `LatentUpscale(By)`, `ImageScaleBy`, `ImageUpscaleWithModel`, `UpscaleModelLoader` |
| Model loaders | `CheckpointLoaderSimple`, `UNETLoader`/`UnetLoaderGGUF*`, `CLIPLoader`/`CLIPLoaderGGUF`, `VAELoader`, `CLIPVisionLoader` |
| LoRA / patches | `LoraLoader`, `LoraLoaderModelOnly`, `ModelPatchLoader` |
| ControlNet | `ControlNetLoader`, `ControlNetApplyAdvanced`, `SetUnionControlNetType` |
| IPAdapter | `IPAdapter`, `IPAdapterFaceID`, `IPAdapterNoise`, `IPAdapterUnifiedLoaderFaceID`, `IPAdapterInsightFaceLoader` |
| Face swap | `ReActorFaceSwap` |
| Matting / mask compositing | `RMBG`, `FeatherMask`, `ImageCompositeMasked` |
| ControlNet preprocessors | `DWPreprocessor`, `DepthAnythingV2Preprocessor`, `DensePosePreprocessor`, `CannyEdgePreprocessor`, `TilePreprocessor`, `HEDPreprocessor` |

- **Covered nodes are narrowed to the few worth exposing**: a rule can list explicit candidate keys (e.g. ControlNet preprocessors keep only `resolution`, `RMBG` keeps model/sensitivity/process resolution), so a node with dozens of parameters doesn't flood the run page.
- **Uncovered nodes are not dropped**: the fallback rule lists **every fillable parameter** on the node (link references are skipped automatically) — that's what covers arbitrary community nodes without touching a line of code.
- **The trade-off is that the fallback ignores node complexity**: nodes with a huge parameter count (video-combine nodes, `ModelMerge*`) have no narrowing rule, so all their parameters show up at once — untick what you don't want on the "Add parameters" page.
- **Forced types**: parameters like `denoise`, `strength_*`, `mask_blur` are often integers in the JSON (`"denoise": 1`) but semantically fractional; they're forced to float, otherwise the phone keyboard can't type `0.5`.
- **Default ticked**: the rule's own defaults (e.g. `strength` on `ControlNetApplyAdvanced`) plus a high-frequency list (seed, prompt text, image, steps, CFG, sampler, scheduler, width/height, batch size, model names).

**Bulk actions on the "Add parameters" page** (handy when there's a lot to configure)

| Control | What it does |
| --- | --- |
| Search box (top of the page) | Filters by parameter name, alias or node name; **only the matching parameters are shown**, and matching groups auto-expand |
| Counter (e.g. `17/18 selected`) and Expand all / Collapse all | The counter shows how many parameters are exposed; expand/collapse **without touching selections** |
| Select all / Clear selection icon in a card header | Applies to **that card only**, separate from the expand hotspot |

**Default aliases**: text parameters prefer the node title you gave it in ComfyUI (e.g. "Base settings"); structured parameters use the built-in name ("Steps", "CFG scale", "Seed"). Aliases are **content you saved**, so they are never translated when you switch the UI language.

**The "Re-parse" button**: after the server workflow changes, re-parsing drops the old config and re-extracts parameters from the new structure (your previous selections and aliases are preserved where possible).

<p align="center">
  <img src="docs/screenshots/en/03-config.png" width="45%" />
  &nbsp;
  <img src="docs/screenshots/en/04-config-picker.png" width="45%" />
</p>

<p align="center"><i>Left: the main view holds only what's in your form, × removes a row　Right: "Add parameters" groups everything by purpose; same-name nodes are told apart by wiring</i></p>

> Saving the config takes you to the run page; the gear icon in the run page's top-right brings you back to the config panel. The two replace each other rather than stacking up routes.

### 5.4 Run page

Fill in the parameters and submit. Controls are rendered according to the configured type:

| Type | Control | Notes |
| --- | --- | --- |
| Text | Multi-line field | Prompts etc. |
| Seed | Number field + **random button** | Keeps the workflow's own value; never randomises behind your back |
| Int | Number field | Steps, width/height, batch size |
| Float | Number field | CFG, denoise |
| Toggle | Switch | Boolean parameters |
| Enum | Dropdown | Sampler, scheduler, model names, … Model and sampler dropdowns fetch the real list from the server (refresh in the top-right corner); other dropdowns keep just the value hard-coded in the workflow |
| Image | Pick image button + preview | A newly picked image is uploaded to the server before running; leaving it alone keeps the image already in the workflow |

Parameters stay grouped by node and are expanded by default.

**Model dropdowns are filled with what the server really has**: opening the run page asks the server once, so dropdowns for models (Checkpoint / UNET / CLIP / VAE / LoRA / ControlNet), samplers and schedulers list the models that actually exist there — install a new model on the PC and tap refresh in the top-right corner to pick it up. The scope is deliberately narrow: only these dropdowns fetch real options, and image upload parameters never do (they would become a list of server filenames and you could no longer upload a new image). If the model written in the workflow isn't on the server, it is flagged and submission is blocked instead of sending a task that is bound to fail; with no connection or a failed request, dropdowns fall back to "just the current value", exactly as before.

**What "Generate" does**

1. Validates that the current workflow data is ready and belongs to the right entry (so you can't submit the wrong workflow).
2. If an image parameter has a newly picked file, uploads it with `POST /upload/image` first.
3. Deep-copies the workflow JSON and writes the form values back into the corresponding nodes' `inputs`.
4. Submits with `POST /prompt`.
5. On success: **freezes a workflow snapshot**, writes a history entry, and switches to the **History** tab.

**Failures tell you why**, instead of a generic "submit failed": network timeouts, HTTP status codes, and the server's `node_errors` (which lists the offending node IDs).

**A mistyped number won't silently become empty**: each value goes through `num.tryParse`; if it fails to parse, the app falls back to the workflow's original value rather than submitting `null`.

<p align="center">
  <img src="docs/screenshots/en/02-run.png" width="45%" />
</p>

<p align="center"><i>Run page: controls rendered by type, with "Generate" pinned at the bottom</i></p>

### 5.5 Task tracking

Tasks have five states, with progress pushed live over WebSocket:

```mermaid
stateDiagram-v2
    [*] --> Queued
    Queued --> Running: execution starts
    Running --> Completed: outputs arrive
    Running --> Failed: execution error
    Running --> Interrupted: cancelled
    Completed --> [*]
    Failed --> [*]
    Interrupted --> [*]
```

| State | Triggered by | Display |
| --- | --- | --- |
| Queued | Just submitted, not picked up yet | Amber + "Waiting…" |
| Running | An execution event arrived | Amber + current node name + percentage bar |
| Completed | Output received | Green + thumbnail |
| Failed | Server returned an error | Red + **the actual error reason** |
| Interrupted | Cancelled, or the server doesn't know the task | Grey |

**Manual stop**: a queued / running task shows a **stop button** on its history card — it prefers ComfyUI's per-task cancel endpoint (`/api/jobs/{id}/cancel`) and falls back automatically on older servers, so you never have to wait out a bad run.

**Where progress comes from**: a WebSocket (`ws://<server>/ws?clientId=…`) pushes events in real time, including which node is running and the percentage. Node names prefer the title you saved in the config panel over a bare node ID.

**It survives crashes and disconnects**: on reconnect the app queries `/history` and `/queue` and corrects every task still marked queued/running into its real final state. Tasks found in neither are treated as "interrupted (the server may have restarted)" instead of spinning forever.

**Returning from the background doesn't leave stale progress**: Android may silently kill a backgrounded WebSocket (a half-open connection that never fires the disconnect callback, so auto-reconnect never starts). When the app comes back to the foreground it rebuilds the connection and reconciles once — and only if there actually is a pending task, so an idle app never bothers the server.

### 5.6 History and run-again

Each entry is a compact card: a status colour bar on the left, one line for the title and one for status + time, a thumbnail on the right (multiple images show a count badge); meaningful phase notes (e.g. an interruption caused by a server restart) get their own line. **Run again** / **Delete** sit in the top-right corner — delete still asks for confirmation, and a record whose snapshot is gone stays tappable and explains why instead of failing silently.

**Search and status filter**

- The search box spans the list above the cards and filters **live** (the history cap is 50 entries, so no debouncing needed).
- It matches the workflow's **display name** + the **parameter values submitted in that run** + parameter **aliases** (aliases require the snapshot to still exist; if it was deleted, matching degrades to values only).
- Multiple keywords are split on spaces; **all of them must hit the same field** — this avoids a record matching merely because "cat" is in the positive prompt and "windowsill" in the negative one.
- **Numbers are not matched**: searching `7` won't hit a record just because `cfg=7`, which would only add noise.
- Case-insensitive; an empty keyword returns everything unchanged.
- On a hit, the card shows a **match summary** explaining why (e.g. `CLIP text encode: …human…`). Matches by workflow name don't repeat the name.
- The status filter has 5 options: All / Running (queued + running merged) / Completed / Failed / Interrupted, and combines with the search.
- Two distinct empty states: "no matching records" vs "no records yet", so you never think your history was lost.

<p align="center">
  <img src="docs/screenshots/en/05-history.png" width="45%" />
  &nbsp;
  <img src="docs/screenshots/en/06-history-search.png" width="45%" />
</p>

<p align="center"><i>Left: default view with the status filter row　Right: searching "lora" matches 4 entries by workflow name</i></p>

**Run again** — one of the most useful things this app does:

- Every run freezes a **snapshot** (the workflow JSON plus the parameter config at the time), so any history entry can reconstruct the form it was run with.
- Tapping "Run again" rebuilds the form from the snapshot and **pre-fills the values you typed then** (prompt, seed, … — never randomised behind your back).
- If you later changed the exposed config so some old parameters no longer exist in the current form, it says exactly "N parameters could not be applied due to config changes" instead of dropping them silently.
- If the currently connected server **isn't** the one the job ran on, it warns first (models/plugins may differ and you may get "model not found"), and lets you decide.

**Delete** asks which kind you want:

- **Record only**: keep the images in the gallery.
- **Record and gallery images**: also remove the images already downloaded to this device (irreversible).

> Deleting a record does **not** delete its snapshot — a snapshot may be referenced by other records. Snapshot cleanup is manual, on the settings page.

### 5.7 Workflow snapshots

The foundation of "run again".

| Question | Answer |
| --- | --- |
| What is a snapshot | The "original workflow JSON + the node exposure config at that time" frozen by a run |
| Why bother | Decoupling from the server — even if that file is deleted or edited on the server, history entries can still re-run from the snapshot |
| When is it created | On every successful submission (reused as-is when the content is unchanged, with only the latest config synced) |
| Does changing the config create more | No. Snapshots are de-duplicated by **workflow content**, so editing the exposure config never invalidates existing records |
| How to clean up | Settings → Workflow snapshots; each entry shows how many records reference it, and can be deleted manually |

<p align="center">
  <img src="docs/screenshots/en/12-snapshots.png" width="45%" />
</p>

<p align="center"><i>Snapshot list: freeze time, size, source server and reference count</i></p>

### 5.8 Gallery and saving to your album

**Gallery**: a dedicated tab, a three-column grid of everything downloaded to this device. Tapping opens a full-screen viewer with pinch zoom, swipe between items, and per-image delete.

**Saving logic**:

- Images are read from the already-downloaded local file first (no re-download).
- For PNGs it asks first: **original image with workflow** (keeps the ComfyUI metadata, so you can drop it back into ComfyUI to reproduce) or **plain image (info stripped)**.
- Videos (mp4/webm/mov) are written to a temp file and then saved to the album.

**Automatic download**: after a successful generation the app downloads the output media into the local gallery directory with **the original PNG metadata preserved**, so you can view and save it even offline.

<p align="center">
  <img src="docs/screenshots/en/07-gallery.png" width="30%" />
  &nbsp;
  <img src="docs/screenshots/en/08-viewer.png" width="30%" />
  &nbsp;
  <img src="docs/screenshots/en/09-save-as.png" width="30%" />
</p>

<p align="center"><i>Gallery grid → full-screen viewer → the two choices when saving to the album</i></p>

### 5.9 Settings

| Entry | Purpose |
| --- | --- |
| **Language** | Follow system / Chinese (Simplified) / English; the choice is stored locally |
| **Server connections** | Add, edit and delete servers, test connections, switch the active one |
| **Workflow storage** | Everything saved on this device, grouped into "local assets / parse cache", with disk usage; local assets can be deleted, parse cache can only be cleared |
| **Workflow snapshots** | All snapshots, reference counts, source server, manual deletion |
| **GitHub access token** | Optional. Required for a private repository; a public one works without it (see below) |
| **About** | Version, check for updates |

**About the UI language**

- Defaults to following the system; a system language that is neither Chinese nor English falls back to **Chinese**, and you can also pin it manually in Settings.
- Persisted data **never stores any display text**: task states are stored as enum names (`queued`/`running`/`completed`/`failed`/`interrupted`), while dynamic content (node names, raw server errors) is stored separately; leftovers from older versions in Chinese are migrated on read.
- As a result, switching languages never affects your history: titles are re-rendered in the current language while parameter values, images and snapshots stay exactly as they were.
- The only things not translated are **content you named or configured yourself**: workflow titles, parameter aliases, model names and node names (which are English in ComfyUI anyway).

<p align="center">
  <img src="docs/screenshots/en/10-settings.png" width="30%" />
  &nbsp;
  <img src="docs/screenshots/en/13-language.png" width="30%" />
  &nbsp;
  <img src="docs/screenshots/zh/10-settings.png" width="30%" />
</p>

<p align="center"><i>Settings → language picker → the same page after switching to Chinese</i></p>

### 5.10 In-app updates

- **Manual only** (no background checks): tap "Check for updates" on the About page, which queries GitHub Releases and compares with the current version.
- When an update exists it shows the version, package size and release notes (Markdown markers are stripped), then "Download and install" runs a progress bar and hands the APK to the system installer.
- **Private and public repositories both work, with no code change**:
  - With no token the app queries anonymously. If the repo is **public**, updates are found and downloaded straight away.
  - If the repo is **private**, anonymous requests get a plain 404 from GitHub (not a 403), so you need a read-only token with Contents access. The token is **stored on device only** and never uploaded.
  - When a token expires or is revoked, the app **falls back to an anonymous retry** automatically — so if the repo switches from private to public, existing users keep getting updates without having to clear the token first (both the lookup and the download fall back).

---

## 6. How the pieces fit together

### How the data flows

```mermaid
flowchart TD
    subgraph S["Sources (three)"]
        A1["Server _api.json"]
        A2["Server UI JSON"]
        A3["Local imported JSON"]
    end
    P["Normalise: everything becomes an API prompt"]
    A1 --> P
    A2 -->|"WebView parser"| P
    A3 --> P
    P --> C["Config panel: tick exposures + set aliases"]
    C -->|"save config"| R["Run page: form rendered by type"]
    R -->|"POST /prompt"| T["Task manager"]
    T -->|"WebSocket events"| H["History (five states)"]
    T -->|"auto download"| G["Local gallery"]
    R -->|"frozen per run"| SN["Workflow snapshot"]
    SN -.->|"restore form + prefill"| R
    H -.->|"via snapshot"| SN
    G -->|"save"| AL["Phone album"]
```

### Three sources → one pipeline

All three paths normalise into **the same structure** (node ID → `{class_type, inputs}`), so the config panel and the run page need only **one** implementation instead of one per source. That's also why UI format must be parsed rather than run directly.

### Snapshots decouple "running" from "history"

```
one run ──▶ history entry (stores only snapshotId + params)
        └──▶ snapshot   (stores workflowJson + mappingConfig)

delete a record ──▶ the snapshot survives (other records may reference it)
run again       ──▶ restore the form from the snapshot + prefill from the record's params
```

So even if that workflow has since changed or been deleted on the server, "run again" still works — **your history never rots because the server moved on**.

### Three kinds of ownership, three lifecycles

| | Server workflows | Parse cache | Local assets | Snapshots | History | Gallery images |
| --- | --- | --- | --- | --- | --- | --- |
| Lives on | Server | Device | Device | Device | Device | Device files |
| Invalidated by server changes | Yes | Yes (prompts a re-parse) | No | **No** | No | No |
| Deletable | Not offered | "Clear" only | Yes | Yes | Yes | Yes |
| Limit | None | None | None | None (usage shown in settings) | Latest 50 | None |

### Behaviour at the edges, with multiple servers

- Switching servers clears the workflow list (local entries, gallery and local workflows are unaffected).
- Each task records **which server it belongs to**; reconciliation only touches tasks of the current server, so it never mislabels a job still running elsewhere as "interrupted".
- Running again against a different server warns you first and lets you decide.

---

## 7. Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| The badge stays red | Either the HTTP probe or the WebSocket failed. Check the server is running, the address/port is right, and the phone is on the same network. Tap the badge, then "Test connection" on the primary/backup addresses |
| "No workflows found" on the server side | No JSON files in `userdata/workflows/`. **Save a workflow once** in ComfyUI on your PC — **no plugin required**; AutoSaveAPI only adds an extra `_api.json` copy |
| Parsing a UI workflow fails / times out | Parsing loads the whole ComfyUI frontend; on a slow device it can take a dozen seconds. Confirm the phone can open that server's web UI normally, then retry with "Re-parse" |
| Parsing succeeds but reports "no dynamically editable parameters" | Every parameter is a **link reference** (or its value type can't be mapped to a control). Hit "Re-parse" in the config panel and try again; if it still fails, this workflow genuinely has nothing worth filling in on a phone |
| A card turned amber saying "content updated" | The workflow content on the server changed, so old parameters may not fit the new structure. Open it and reconfirm the config |
| Submitting returns HTTP 400 listing nodes | Server-side validation failed (commonly a missing model name or node type). Check the listed node IDs on your PC |
| A task is stuck at "Running" | A final event was missed while offline or backgrounded. Tap refresh in the History top bar to reconcile (reconnecting and returning to the foreground also reconcile) |
| Search can't find an old record | Three possibilities: ① older records stored no "submitted parameter values", so only the workflow name is searchable; ② parameter **aliases** need the snapshot to still exist — if it was deleted in settings, matching degrades to values only; ③ **numbers are not matched**, so searching `7` won't hit `cfg=7` |
| The "Add parameters" list goes empty after typing in search | Search is a **per-parameter filter**: only matching parameters are shown, and no match means "no matching parameter". The keyword must appear in a parameter name, alias or node name |
| Aliases are still Chinese after switching to English | Aliases are content saved at configuration time — your own data, not translated with the UI language. Just rename them in the config panel |
| "Repository not accessible" when checking updates | The repo is private; put a read-only PAT in Settings → GitHub access token. If the repo is already public and you still see this, the stored token is stale — clear it |
| Saving an image to the album fails | Album permission is required the first time |

---

## 8. Known limitations

These are real boundaries of the current version, not bugs:

- **Only model and sampler dropdowns fetch real server options**: other dropdowns (for example enums of third-party nodes) still contain just the value hard-coded in the workflow. **Image upload parameters deliberately do not** — otherwise they would turn into a list of server filenames and you could no longer upload a new image.
- **Real dropdown options depend on the current connection**: with no connection, or when the request fails, dropdowns fall back to "just the current value" — exactly the old behaviour, with no error. The list is fetched when the page opens, so a model you just installed on the PC needs a tap on the refresh button.
- **Numeric parameters have no min/max/step**: integers and floats are free-text fields with no range validation; a non-numeric entry falls back to the workflow's original value (it never submits an empty value).
- **Nodes with a huge parameter count have no narrowing rule**: video-combine nodes and `ModelMerge*` (30–66 parameters on a single node) only get the fallback, so every fillable parameter is listed in the config panel at once and you have to untick the ones you don't want.
- **Image parameters record only the server-side filename**, so if the server cleans out its input directory, image references in old records can break.
- **Search covers the latest 50 records only**: that's the history cap itself, and search is a plain local filter with no index; a much larger history would need a redesign.
- **Primarily Android**: in-app updates, album saving and APK installation are all Android implementations; other platforms compile but aren't fully verified.
- **No background update checks**; it's manual, on the About page.

---

## 9. Tech stack and project layout

**Tech stack**: Flutter · Riverpod (state) · http · web_socket_channel · shared_preferences · file_picker · webview_flutter · video_player · gal (album) · path_provider · package_info_plus · open_filex · flutter_localizations (i18n)

```
lib/
├── main.dart                 # Entry point: injects SharedPreferences, wires up localisation
├── theme.dart                # Semantic colours (primary/success/error/warning/neutral)
├── utils.dart                # Param type inference, hashing, display names, provider write scheduling
├── l10n/                     # String sources (app_zh.arb is the template, app_en.arb the English one)
├── models/                   # Data models
│   ├── workflow_node.dart    # Node parameter config (type/alias/options/current value)
│   ├── task_history.dart     # History entry (status enum + phase + snapshot ref + param snapshot)
│   ├── task_status.dart      # Task status/phase enums and migration of legacy Chinese data
│   ├── workflow_snapshot.dart# Workflow snapshot
│   ├── local_workflow.dart   # Local asset
│   ├── parsed_workflow.dart  # UI-workflow parse cache
│   ├── workflow_entry.dart   # Shared view for display names
│   └── release_info.dart     # GitHub Release info
├── providers/                # Riverpod state layer
│   ├── shared_preferences_provider # SharedPreferences injection point
│   ├── locale_provider       # UI language preference and resolution rules
│   ├── connection_provider   # Multiple servers + primary/backup probing (structured results)
│   ├── workflow_provider     # Workflow list, content, content-hash validation
│   ├── task_manager          # Submission, history persistence, reconciliation, gallery download
│   ├── ws_event_provider     # WebSocket channel and auto-reconnect
│   ├── snapshot_provider     # Snapshots
│   ├── local_workflow_provider / parsed_workflow_provider
│   └── update_provider / github_token_provider
├── services/
│   ├── workflow_api_converter # UI→API conversion script and result validation (pure, unit-testable)
│   ├── workflow_node_parser   # Node recognition rule table + param type resolution (pure, unit-testable)
│   ├── gallery_store          # Local gallery storage
│   ├── media_saver            # Single entry point for saving to the album
│   ├── png_metadata_stripper  # Strips PNG metadata
│   └── update_service         # GitHub Releases lookup and download
├── utils/
│   ├── task_display.dart     # Task status/phase → display text in the current language
│   └── history_search.dart   # History keyword search and status filter (pure, unit-testable)
└── ui/
    ├── main_screen.dart      # Bottom navigation shell
    ├── home/                 # Workflows: server side / local side
    ├── builder/              # Config panel / run page / WebView parse page
    ├── gallery/              # History / gallery / media viewer
    ├── settings/             # Settings hub (including language) and sub-pages
    └── widgets/              # Connection status badge
```

**Localisation**: strings live in `lib/l10n/*.arb` and `flutter gen-l10n` produces `AppLocalizations` on `flutter pub get` (see `l10n.yaml`). The default is to follow the system; a system language that is neither Chinese nor English falls back to Chinese, and the user can pin the language under "Settings → Language", stored in `comfy_ui_locale`.

No persisted data stores display text: task states are stored as enum names (`queued`/`running`/`completed`/`failed`/`interrupted`), while phases and dynamic content (node names, raw server errors) are stored separately; legacy Chinese data from older versions is migrated on read. Real screenshots of the English UI are in `docs/screenshots/en`.

---

## 10. Development, testing and releases

```bash
flutter pub get
flutter run          # develop
flutter analyze      # static analysis; should be clean before committing
flutter test         # unit and widget tests (currently 439 cases, all green)
```

Pure logic — parsing, search, language resolution — is extracted into functions that don't depend on `BuildContext` (`workflow_node_parser` / `history_search` / `task_display`), so it can be unit-tested directly; complex screens get widget tests.

**Docs and images in this repository**

| Path | Contents |
| --- | --- |
| `README.md` / `README_EN.md` | Chinese / English docs (cross-linked at the top) |
| `docs/screenshots/zh`, `docs/screenshots/en` | Real device screenshots (Android emulator) |
| `design/app_icon_1024.png` | App icon source |

**Release conventions**

- The version number is the APK's `versionName`, from `version: X.Y.Z+N` in `pubspec.yaml`, and **must match the git tag** (e.g. `v1.1.0`) or in-app updates will misjudge.
- Release flow: edit `pubspec.yaml` → commit → `git tag -a vX.Y.Z` → `git push origin main --follow-tags`.
- Release builds use the real signing key and never fall back to the debug signature (otherwise users can't overwrite-install). The signing config comes from `android/key.properties` locally, and from repository Secrets in CI via `.github/workflows/release.yml`.
- Pushing a tag makes GitHub Actions build the release APK and upload it to the Release.

---

## 11. Roadmap

One direction, **unscheduled and not promised** — listed for reference only:

| Direction | What it solves |
| --- | --- |
| **Run workflows on RunningHub** | Run the same workflows when you have no local GPU, or don't want to keep the machine at home switched on. It offers a ComfyUI-compatible way in; the goal is to treat it as "just another server" and reuse the existing connection and run flow |

Details and ordering are still open.

---

## Icon

The app uses a custom icon generated to the Android adaptive-icon spec: the background layer fills the full 108dp canvas and the foreground sits inside the central 72dp safe circle, so it never shows a bleed or gets cropped under circular, rounded-square or teardrop launcher masks. Source file: `design/app_icon_1024.png`.
