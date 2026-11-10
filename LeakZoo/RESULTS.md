# Kết quả LeakZoo

Sinh bởi `scripts/zoo-autorun.sh` lúc 2026-11-10 10:07: commit `c87acb7`, Xcode 26.2, iPhone 17 Pro, iOS 26.3.
Mỗi scenario được mở rồi đóng (`--autorun`, `TLEAK_MODE=log`), rồi so report của TLeakDetector
và log `deinit` của LeakZoo với [expected.json](expected.json).

**20/20 scenario khớp.**

| Case | Scenario | Mong đợi | Thực tế | Kết quả |
|---|---|---|---|---|
| Z01 | Closure property captures self | `leak_cycle`: báo leak | `Z01ClosurePropertyViewController` screen sau pop | ✅ |
| Z02 | Strong delegate | `leak_cycle`: báo leak | `Z02StrongDelegateViewController` screen sau dismiss | ✅ |
| Z03 | UIAction captures self | `leak_cycle`: báo leak | `Z03ButtonActionViewController` screen sau pop | ✅ |
| Z04 | Removed child keeps itself alive | `leak_cycle`: báo leak | `Z04ChildClosureViewController` screen sau removeFromParent | ✅ |
| Z05 | Sibling cycle on popToRoot | `leak_cycle`: báo leak | `Z05Level2ViewController` screen sau pop<br>`Z05Level3ViewController` screen sau pop | ✅ |
| Z06 | Combine sink captures self | `leak_cycle`: báo leak | `Z06CombineSinkViewController` screen sau dismiss | ✅ |
| Z07 | Timer never invalidated | `leak_rooted`: báo leak | `Z07TimerViewController` screen sau pop | ✅ |
| Z08 | Notification observer never removed | `leak_rooted`: báo leak | `Z08NotificationObserverViewController` screen sau dismiss | ✅ |
| Z09 | Task on endless AsyncStream | `leak_rooted`: báo leak | `Z09StreamTaskViewController` screen sau pop | ✅ |
| Z10 | Static registry holds screen | `leak_rooted`: báo leak | `Z10StaticRegistryViewController` screen sau dismiss | ✅ |
| Z11 | Closure with weak self | `no_leak`: không báo | không báo | ✅ |
| Z12 | Task cancelled on disappear | `no_leak`: không báo | không báo | ✅ |
| Z13 | Timer invalidated on disappear | `no_leak`: không báo | không báo | ✅ |
| Z14 | asyncAfter delays release | `no_leak`: không báo | không báo | ✅ |
| Z15 | Child added and removed | `no_leak`: không báo | không báo | ✅ |
| Z16 | Plain popToRoot | `no_leak`: không báo | không báo | ✅ |
| Z17 | Cached screen, allowlisted | `allowed`: không báo | không báo | ✅ |
| Z18 | Kept screen, opted out | `allowed`: không báo | không báo | ✅ |
| Z19 | Known leak, suppressed | `leak_suppressed`: chỉ log | `Z19SuppressedLeakViewController` chỉ log (suppressed) | ✅ |
| Z20 | Careless container, budget 1 | `leak_budget`: báo vượt budget | `Z20CarelessChildViewController` vượt budget | ✅ |

## Lệch đã chấp nhận

- Leak `leak_cycle` và `leak_rooted` đều được báo với `kind: screen`. Đúng thiết kế: `kind` là điều quan sát được,
  còn nguyên nhân (cycle hay rooted) sẽ là trường riêng khi có graph ở S3–4. Xem ADR 003.
- Z05: cycle giữa hai màn hình được báo thành hai report, mỗi màn một report.
