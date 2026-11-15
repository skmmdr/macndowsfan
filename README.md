# macndowsfan

Fan control and SMC temperature monitoring for Apple Macs running Windows via
Boot Camp. Built and verified on an **iMac14,2** (Late 2013 27", Core i7-4771,
GTX 780M) with Windows 10 Pro 19045.

The app is a Rust reimplementation of Macs Fan Control, with two frontends
sharing the same Rust SMC core:

* **Flutter UI** — bento dashboard with a live RPM gauge, temperature tiles
  with sparklines, constant/sensor fan curves, click-to-follow sensors, dark
  native window.
* **egui app** — lightweight fallback, plus `--probe` / `--selftest` CLI
  diagnostics.

## Install (recommended)

```powershell
.\dist\macndowsfan-setup-0.3.0.exe
```

Installs to `C:\Program Files\macndowsfan` and:

* adds Start Menu and Desktop shortcuts;
* registers **macndowsfan** in Apps & features (with uninstaller);
* adds `HKCU\...\CurrentVersion\Run\macndowsfan` so the app **starts with
  Windows**, hidden in the notification area (`--startup`);
* copies the signed `applesmc.sys` already on the machine into the install
  folder, creates the `AppleSMC` kernel service if it is missing (or points it
  at that local copy when Macs Fan Control was removed) and sets it to
  **AUTO_START**, so the app can open the SMC at login **without UAC**;
* starts the app when the installer finishes (interactive installs).

The uninstaller keeps settings by default and removes the `AppleSMC` service
only when it points at macndowsfan's own driver copy.

See [CHANGELOG.md](CHANGELOG.md) for release notes.

### Driver requirement

Neither UI ships a kernel driver. They talk to `\\.\APPLESMC`, the signed
`applesmc.sys` driver that **Macs Fan Control** installs. The installer reuses
that driver file when it is present, so Macs Fan Control itself can be
uninstalled afterwards. If the driver file is gone, install Macs Fan Control
once to restore it.

**If Macs Fan Control is still installed, quit it before running
macndowsfan.** It opens the SMC device exclusively, so both programs cannot run
at the same time.

## Portable run

```powershell
.\dist\macndowsfan.exe
```

Settings: `%APPDATA%\MacndowsFan\settings.json`, log:
`%APPDATA%\MacndowsFan\macndowsfan.log`, tray diagnostics:
`%APPDATA%\MacndowsFan\tray.log`.

Fan modes: Automatic, Constant speed (clamped to the fan's safe min/max) and
Sensor-based (start/full-speed temperatures with a live fan curve). Sensor
curves are re-evaluated **every second**.

### Fan profiles

The PROFILE row is a one-click preset selector. The selection is stored in
`settings.json`; changing the mode, sensor or a slider afterwards switches the
profile to **Custom**.

| Profile | Behavior |
|---------|----------|
| Auto | Firmware fan control |
| Quiet | Sensor curve, CPU proximity (TC0P) 65 → 90 °C |
| Balanced | Sensor curve, CPU proximity (TC0P) 55 → 85 °C |
| Gaming | Sensor curve, GPU core (TG0d) 65 → 85 °C |
| Max | Constant maximum RPM (2640) |
| Custom | Your own mode/sensor/temperatures |

At idle the Gaming profile leaves the fan at 1200 RPM; during a game the GPU
die temperature rises and the target ramps toward 2640 RPM.

## Tray and window behavior

* **Closing the window (X) hides it in the notification area.** The app keeps
  running and keeps applying the current fan profile.
* The tray icon menu has **Open macndowsfan**, **Restore automatic** and
  **Quit macndowsfan**. Left-clicking the icon reopens the window.
* The header also has a **Quit** button.
* **Quit** restores firmware fan control (while keeping the saved profile for
  the next launch), destroys the tray icon and exits.
* Only one instance runs. Launching `macndowsfan.exe` again (shortcut, Start
  Menu, `--startup`) brings the existing window back instead of starting a
  second copy that would fight over the SMC.
* The installer's startup entry uses `--startup`, so a login launch stays hidden
  in the tray. Run the app without that flag for a visible window.
* Windows may place a new tray icon in the notification overflow (the `^`
  chevron). Drag it onto the taskbar to keep it always visible.

## Compact always-on-top widget

The **Widget** button in the header turns the window into a small, frameless
panel that stays above other windows. It has no title bar: drag anywhere on
the panel to move it.

* large fan RPM with a fill bar against the fan's min/max range, plus the
  current target;
* the temperature of the sensor selected in the dropdown, coloured green /
amber / red by the same thresholds as the dashboard;
* a dot and an `AUTO` / `FIX <rpm>` / `SENSOR` label for the active fan mode;
* a fan picker appears when the Mac has more than one fan.

The top-right buttons cycle three sizes — **S** 280×118, **M** 330×136 and
**L** 390×160 — expand back to the dashboard, or hide to the notification
area. Expanding restores the dashboard to its previous size, position and
maximized state and turns always-on-top off. The size, chosen sensor and
panel position persist across restarts in
`%APPDATA%\MacndowsFan\widget_prefs.json`; without a saved sensor the widget
falls back to the one used by the fan's control profile.

The widget lives inside the main window rather than in a second process, so it
shares the single SMC session and keeps the fan profile running. It paints a
static gradient and rebuilds once per SMC sample, with no charts, animations or
timers of its own: measured on the iMac14,2 it used **~0.6 % of one core**,
against ~10 % for the full dashboard.

### Performance

* One SMC sample + one control tick per second (previously the UI sampled twice).
* The control sensor is smoothed (EMA) and the fan target uses a 30 RPM
  deadband, so it does not chase SMC noise or spam the target log.
* No always-on animations: the gauge/status update once per second instead of
  running at 60 fps forever.
* Measured on this i7-4771 iMac: about **1.7 % of one core** hidden in the tray
  and **2.3 %** with the window visible (was 52–62 % of one core).

## Build

### App (Flutter + Rust DLL)

Prerequisites on this machine (already installed):

* Flutter 3.47.9 at `%LOCALAPPDATA%\dev\flutter`
* Visual Studio Build Tools 2022 with the C++ desktop workload
* Rust MSVC toolchain (`rustup toolchain install stable-x86_64-pc-windows-msvc`)

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_flutter.ps1
```

Builds `macndowsfan_core.dll` with MSVC, runs `flutter build windows
--release`, copies the DLL next to the runner and assembles the portable bundle
in `dist\`. Add `-Run` to launch it.

The window is 1180×880 with a dark DWM title bar, the app icon from
`assets\macndowsfan.ico` and the native title **macndowsfan**.

### Installer

Uses NSIS 3.11 (portable copy in `%TEMP%\kilo\nsis\nsis-3.11`):

```powershell
& "$env:TEMP\kilo\nsis\nsis-3.11\makensis.exe" (Resolve-Path .\installer\macndowsfan.nsi).Path
Copy-Item .\installer\output\macndowsfan-setup-0.3.0.exe .\dist\ -Force
```

The script installs `dist\*`, creates shortcuts, writes the startup entry,
configures `AppleSMC` for boot start and registers the uninstaller.

### Icon

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\make_icon.ps1
```

Regenerates `assets\macndowsfan.ico` (16–256 px) and `assets\macndowsfan.png`,
then copy the ICO to `flutter_ui\windows\runner\resources\app_icon.ico` and
rebuild.

### egui app / diagnostics

Uses the GNU Windows target (no Visual Studio needed):

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Release
```

`build.ps1` adds MinGW-w64 binutils in
`%TEMP%\kilo\winlibs\mingw64\bin` to `PATH` (`dlltool` + `as` are needed by the
`windows` crate's `raw-dylib` output).

## Architecture

```
src/                 Rust
  smc.rs             APPLESMC IOCTL protocol, value codecs
  machine.rs         fan discovery, modes, targets, safety clamps
  sensors.rs         curated temperature key detection
  config.rs          %APPDATA% settings + log
  ffi.rs             C ABI (mf_*) used by Flutter
  lib.rs             shared core
  main.rs / app.rs   egui frontend + --probe / --selftest
flutter_ui/          Flutter UI (Dart, Windows runner)
installer/           NSIS script
assets/              app icon
scripts/             build_flutter.ps1, make_icon.ps1
dist/                portable app + installer
```

Flutter calls the DLL through `dart:ffi` (`flutter_ui/lib/core_ffi.dart`):

| Function | Purpose |
|----------|---------|
| `mf_create` / `mf_destroy` | open/close an SMC session |
| `mf_sample` | JSON snapshot: fans (RPM, target, min/max, forced), temperatures |
| `mf_get_settings` / `mf_apply` | load/apply the per-fan profile |
| `mf_restore_auto` | clear forced modes **and** reset the profile to Automatic |
| `mf_suspend` | clear forced modes but keep the profile (used on window close) |
| `mf_reconnect` | reopen `\\.\APPLESMC` after errors |
| `mf_free_string` | free returned UTF-8 strings |

## How the SMC is accessed

The IOCTL protocol and the `\\.\APPLESMC` device were recovered from
`applesmc.sys` (CrystalBit Solutions, signed) and `MacsFanControl.exe`:

| IOCTL        | Input                          | Output                       |
|--------------|--------------------------------|------------------------------|
| `0x00220000` | `u32 key, u8 size`             | up to 32 data bytes          |
| `0x00220004` | `u32 key, u8 size, u8 data[]`  | 1 status byte                |
| `0x00220008` | `u32 index`                    | 4 key characters             |
| `0x0022000C` | `u32 key`                      | `u8 size, u8 type[4], u8 attrs` |
| `0x00220020` | —                              | 1 byte (init/wake)           |

iMac14,2 uses a single fan (`Main`) and the global `FS! ` forced bitmask.
Fan keys: `FNum`, `F<i>ID`, `F<i>Ac`, `F<i>Mn`, `F<i>Mx`, `F<i>Tg`; per-fan
`F<i>Md` is used on Macs that have it. If a counted fan's per-fan mode key
cannot be verified, the app reports an error rather than assuming a shared key. Encodings: `fpe2` (14.2 fixed point),
`flt ` (big-endian IEEE-754), `sp78` (8.8 signed temperatures).

### Temperature sensor audit (iMac14,2)

A full 632-key SMC scan (`scripts/scan_smc_temps.ps1`, run with the app closed)
identified 23 valid temperature keys:

* CPU: `TC0P` CPU area, cores `TC0c`/`TC1c`/`TC2c`/`TC3c`, package `TCXc`,
  graphics `TCGc`, uncore `TCSc`;
* GPU: `TG0P` GPU area, `TG0d` GPU core, `TG0D`/`TG0E`/`TG0F` GPU secondary
  1–3;
* `TM0P`–`TM3P` RAM slots 1–4, `TA0P` room air, `Tp2H` power supply,
  `TH1A`/`TH1B` drive bay 1/2, `TL0P` screen panel, `Tb0P` Thunderbolt.

The UI shows these friendly names, keeps the raw key underneath, and explains
each sensor in the card tooltip (hover a card).

Key case matters: the CPU cores are lowercase `TC0c`…`TC3c`; the uppercase
`TC0C` keys do not exist on this model. `TC0E`, `TC0F`, `TH0P` and several
other `TH*` keys exist but return unpopulated values (−7/−26/−127 °C) and are
filtered. The runtime filter also rejects anything outside 0…110 °C.

Cross-check: `TG0d` (GPU die) reads ~55 °C while `nvidia-smi` reports 54 °C;
`TG0P` (GPU proximity) is a few degrees below. `TG0D`/`TG0E`/`TG0F` are
different GPU sensors (≈61–65 °C), so their labels are intentionally neutral.

## Diagnostics

```powershell
.\target\debug\macndowsfan.exe --probe      # writes %APPDATA%\MacndowsFan\probe.txt
.\target\debug\macndowsfan.exe --selftest   # 1500 RPM for 6 s, then Automatic
```

`--probe --stop-mfc --elevate` force-closes Macs Fan Control and dumps the SMC
state when its tray icon is hard to reach.

## Safety

* Manual control requires finite, positive SMC-reported min/max limits and a
  supported target key. If these cannot be verified, the app refuses to force
  that fan; reconnect after the SMC is available.
* All fans counted by `FNum` must have their mode restored and verified before
  Quit reports success. If `FNum` cannot be read, the app cannot confirm that
  firmware control has been restored.
* Forced fan targets are checked against the SMC on each control tick and
  reapplied if they drift from the last commanded value.
* Closing the window only hides it to the tray and keeps the active profile.
  Use **Quit** (tray or header) to restore Automatic fan control.
* If the control sensor is unavailable or returns an invalid reading, sensor
  mode commands maximum fan speed until a valid reading returns.
* Quit reports a failure and keeps the app running if it cannot confirm that
  firmware control was restored. Restore the SMC connection and retry.
* Upgrades and uninstall require the app to be quit from its tray menu first;
  the installer does not force-kill it. Previously installed uninstallers may
  still use the old force-kill behavior.
* If the process is killed (Task Manager), a forced target can remain in the
  SMC. Reboot or reopen the app and choose Automatic.
* Forcing fans bypasses firmware thermal policy — use sane values.

## License

MIT. Not affiliated with Crystalidea. The project does not bundle or
redistribute Macs Fan Control or `applesmc.sys`; the installer may copy the
signed driver already present on the machine into its own folder so the SMC
service keeps working after Macs Fan Control is removed.
