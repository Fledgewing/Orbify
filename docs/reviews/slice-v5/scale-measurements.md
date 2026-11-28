# Width-normalized scale measurements

Pixels are measured in the original approved crop and actual native capture, before gallery resizing. Error compares `(native size / native width)` with `(approved size / approved width)`. Capitals exclude descenders; forms with only digits use their full digit ink height.

| Sample | Approved px / width | Native px / width | Difference |
|---|---:|---:|---:|
| Goal year | 43 / 824 | 71 / 1404 | -3.09% |
| Goal label | 30 / 824 | 51 / 1404 | -0.23% |
| Goal numeric field | 29 / 824 | 48 / 1404 | -2.86% |
| Goal Off | 30 / 824 | 52 / 1404 | +1.73% |
| Goal Save | 29 / 824 | 49 / 1404 | -0.84% |
| Launcher hero capital K | 25 / 702 | 50 / 1404 | +0.00% |
| Launcher tile capital O | 16 / 702 | 32 / 1404 | +0.00% |
| Status row capital N | 19 / 702 | 37 / 1404 | -2.63% |
| Crash summary Worker.run | 29 / 824 | 50 / 1404 | +1.19% |
| Numeric field width | 132 / 824 | 225 / 1404 | +0.04% |
| Numeric field height | 102 / 824 | 180 / 1404 | +3.57% |
| Launcher hero height | 253 / 702 | 506 / 1404 | +0.00% |
| Launcher tile height | 150 / 702 | 300 / 1404 | +0.00% |

The shared roles are in `CompanionStyle.kt`. Round 2 Settings and checklist use the common readable roles, with no Activity-specific downscale. Their body minimum is enforced by CompanionTypeScaleTest; this table retains the approved status/crash/goal scale samples. System chrome and synthetic content are excluded from these text measurements.
