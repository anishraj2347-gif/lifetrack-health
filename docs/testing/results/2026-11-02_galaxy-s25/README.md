# Frame timing — Samsung Galaxy S25, 2 Nov 2026

- **Phone:** Samsung Galaxy S25 (SM-S931B), Android 17
- **Build:** patient 1.42.3, profile mode, demo tools on, sample family (ten people)
- **Run:** `integration_test/scroll_perf_test.dart` via `flutter drive --profile --no-dds`
  (Field Test Kit A1), from the Windows PC
- **Budget:** 16.7 ms per frame (60 Hz). "Over budget" counts frames whose build or raster time
  went past it.

| Action | Frames | Build avg / 90th / worst (ms) | Raster avg / 90th / 99th (ms) | Over budget |
|---|---:|---|---|---|
| Scrolling all five tabs (`scroll_tabs`) | 1,265 | 1.17 / 2.13 / 17.31 | 3.33 / 5.77 / 22.12 | 2 build, 17 raster (1.5%) |
| Switching tabs, two rounds (`switch_tabs`) | 82 | 3.74 / 7.30 / 17.49 | 10.73 / 21.82 / 34.39 | 1 build, 13 raster (17%) |

**Reading.** Scrolling stays within budget for 98.5% of frames. Tab switches are slower to draw:
the first frames of a newly shown tab exceed the budget about one time in six, on the raster
(GPU) side rather than in building widgets — likely the shared glass blur and photos drawn for
the first time. A polish item, not a defect.

**Found on the way:** an error when a finger lifted after its card had left the screen, fixed in
1.42.3 (`test/ui/pressable_test.dart`).

Raw summaries: `scroll_tabs.frame_summary.json`, `switch_tabs.frame_summary.json`.

## Manual checks (Field Test Kit A2)

| # | Check | Result |
|---|---|---|
| 1 | Installs; opens behind the phone lock | Pass — 1.42.3 release, new signing key |
| 6 | Share with the doctor app; doctor sees it | Pass — doctor DMC-36629 (sample doctor) enrolled from LifeTrack Clinic 1.8.0 on the phone over USB (`adb reverse`), approved on the Windows PC's server; share from patient 1.42.3 (demo) arrived |
| 11 | Screenshot is blocked (normal, non-demo build) | Pass |

Only one phone so far; the week-8 plan calls for 2–3 phones of different makers and ages.
