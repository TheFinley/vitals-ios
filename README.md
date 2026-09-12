# Vitals — native iOS app

SwiftUI + SwiftData + HealthKit + Swift Charts. iOS 17+. No third-party dependencies.

## Put it on your iPhone

1. Open `Vitals.xcodeproj` in Xcode (double-click it).
2. Click the **Vitals** project in the sidebar → **Signing & Capabilities** tab → set **Team** to your Apple ID (add it under Xcode → Settings → Accounts if it isn't there). A free Apple ID works; the bundle id is `com.piumal.vitals` — change it if Xcode says it's taken.
3. Plug in your iPhone (or use Wi-Fi debugging), pick it in the device menu at the top, press **Run** (⌘R).
4. First run on the phone: Settings → General → VPN & Device Management → trust your developer certificate. Free-account builds expire after 7 days — just press Run again to refresh.
5. In the app: allow **Health** access when asked. That's it — food lookup is free and needs no account.

## What's inside

| File | Purpose |
|---|---|
| `Vitals/Models.swift` | `Meal`, `FoodItem`, `WeighIn` (SwiftData), `Profile`, `Targets` maths (BMI, Mifflin–St Jeor, deficit, macros, DRI references) |
| `Vitals/HealthKitManager.swift` | Reads steps, active/basal energy, resting HR, sleep, weight, height, DOB, sex. Writes every logged meal (14 nutrients) and weigh-ins back to Apple Health |
| `Vitals/FoodDatabase.swift` | Bundled table of ~110 everyday / Portuguese / Sri Lankan foods (per-100 g USDA-style values, typical portions) |
| `Vitals/FoodLookup.swift` | Free lookup path: on-device Vision classifier for photos, barcode detection, USDA FoodData Central client, Open Food Facts client, deterministic text parser, optional Apple on-device model (iOS 26) for name normalisation and the coach |
| `Vitals/BarcodeScanner.swift` | Live barcode scanner (VisionKit) |
| `Vitals/ClaudeService.swift` | Optional paid path: raw Messages API client (`claude-opus-5`) used only if a key is entered in Settings + Keychain wrapper |
| `Vitals/FoodLogView.swift` | Food tab: camera / photo library / text lookup / manual entry, review sheet, calorie ring, macros, meals by slot, nutrient grid |
| `Vitals/TodayView.swift` | Today tab: Apple Health tiles, energy balance, 14-day chart |
| `Vitals/TargetsView.swift` | Targets tab: BMI scale, BMR/TDEE (Watch-measured or formula), calorie target, macro split, weigh-in log + chart, reference-intake table |
| `Vitals/CoachView.swift` | Rule-based eat/skip observations from the last 7 days, Claude coach, everyday swaps |
| `Vitals/SettingsView.swift` | API key, Health status, how estimates work |

## Cost
Free by default. Photo recognition runs on the phone (Apple Vision); nutrients come from the bundled table, the USDA FoodData Central public API (demo key ≈ 30 lookups/hour; a free personal key removes that) and Open Food Facts for barcodes. Adding an Anthropic API key in Settings is optional and switches photo/text lookups to Claude (≈ 3–8 ¢ per photo).

Energy expenditure defaults to the Apple Watch's measured 30-day average (active + resting) when available, otherwise BMR × activity factor. Calorie targets never drop below BMR or 1,500 kcal.
