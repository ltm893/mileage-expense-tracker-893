# CONTEXT.md — mileage-expense-tracker-893
# Read this first at the start of every session.

## What this repo is
Standalone add-on for cognito-s3-stack-893. Tracks vehicle mileage and expenses with GPS trip tracking, receipt OCR scanning, and CSV export. iOS app display name: **MilesExpenses**.

## Architecture decisions
- **Auth**: Cognito from shared base stack — raw URLSession + Cognito SRP, no Amplify
- **base_outputs.json**: Read via BASE_OUTPUTS_PATH env var
- **met_outputs.json**: Written to repo root by deploy.sh, gitignored
- **idPrefix**: Derived from `base_outputs.json` `public_bucket` name (e.g. `test893-public` → `test893`) — drives all resource names, no hardcoding, no collisions
- **Standalone**: Not nested inside cognito-s3-stack-893

## Repo family
- `cognito-s3-stack-893` — forkable base, deploy first
- `mileage-expense-tracker-893` — this repo ✅ complete
- `music-player-893` — not created yet

## Backend status ✅ Complete + Deployed
- `backend/bin/app.ts` — derives idPrefix, stack = `MileageExpenseStack-{idPrefix}`
- `backend/lib/met-stack.ts` — all resource names prefixed with idPrefix
- `backend/lib/base-outputs.ts` — TypeScript type for base_outputs.json
- `backend/lambda/vehicles/` — CRUD
- `backend/lambda/trips/` — CRUD
- `backend/lambda/expenses/` — CRUD + presigned S3 URLs
- `backend/lambda/ocr/` — S3 trigger → Textract
- `backend/scripts/deploy.sh` — derives idPrefix via grep, resource summary before confirm, writes met_outputs.json to repo root

## Deployed values (test893)
- Stack: MileageExpenseStack-test893
- API: https://1a6uphz606.execute-api.us-east-1.amazonaws.com/prod/
- User Pool: us-east-1_9v0zP2VID
- App Client: 1rr1jpp7651pttbr9fjmkai00d
- Identity Pool: us-east-1:e852387e-bd32-4c67-9fa9-2362c85a8e0a
- Receipts bucket: met893-receipts (note: original stack used hardcoded names)
- Tables: met893-vehicles, met893-trips, met893-expenses

## iOS status ✅ Complete
SwiftUI, MVVM, raw URLSession + Cognito SRP (no Amplify)
Display name: `MilesExpenses` (set via `CFBundleDisplayName` in Info.plist)

### Files
- `Config/AppConfig.swift` — loads met_outputs.json from bundle, zero hardcoded values
- `Config/AppColors.swift` — full design system
- `Models/Models.swift` — Vehicle, Trip, Expense — uses decodeIfPresent for safe decoding
- `Services/AuthService.swift` — Cognito SRP, Keychain, auto-refresh
- `Services/NetworkService.swift` — generic GET/POST/PUT/DELETE + JWT
- `Services/LocationManager.swift` — CoreLocation GPS, real-time distance
- `Services/CameraImagePicker.swift` — camera + photo library
- `Services/ReceiptScanner.swift` — Vision framework OCR (amount, date, merchant)
- `Services/ReceiptUploader.swift` — presigned S3 PUT
- `Views/ContentView.swift` — auth gate, tab bar (Summary / Trips / Expenses / Vehicles / Settings)
- `Views/LoginView.swift` — Cognito SRP login
- `Views/VehiclesView.swift` — list, add, edit, delete
- `Views/TripsView.swift` — list (tap to edit sheet, swipe to delete), add with GPS/Odometer/Both mode picker
- `Views/ExpensesView.swift` — list (tap to edit sheet, swipe to delete), add with receipt OCR
- `Views/SummaryView.swift` — dashboard stats + date-range filter + CSV export
- `Views/SettingsView.swift` — app info, sign out

## TripsView ✅ Complete (updated 2026-05-02)
- `TrackingMode` enum: GPS / Odometer / Both — shown as tappable cards on step 1
- GPS mode: live CoreLocation tracking, skip odometer fields
- Odometer mode: start + end reading, skip GPS step, manual date picker
- Both mode: GPS tracking + odometer fields + comparison section
- List rows: compact — date, miles, purpose (if set) only
- Tap row → sheet with read view + Edit button → inline edit → Save/Cancel
- Swipe to delete
- `TripDetailView` — read/edit all fields: date, vehicle, purpose, notes, odometer start/end, GPS distance

## SummaryView ✅ Complete (updated 2026-05-02)
- `DateRangeFilter` enum: This Month / Last 30 Days / Last 90 Days / This Year / All Time
- Horizontal pill selector — updates all cards reactively, no extra API call
- Mileage card: total miles, trip count, avg mi/trip, per-vehicle bar chart
- Expenses card: total / vehicle / general pills, by-category bar chart
- Empty-state messages when no data in selected period
- Export card: trips, expenses, or combined CSV for the active filter period
- Filenames include period slug (e.g. `trips_this_month_2026-05-02.csv`)
- `ShareSheet` (`UIViewControllerRepresentable`) included in this file

## App Icon ✅ Complete (2026-05-02)
- Speedometer gauge design — navy background, teal arc, amber needle, no text
- Source SVG: `Assets.xcassets/AppIcon.appiconset/met_icon_source.svg`
- PNGs generated via `rsvg-convert` for all required sizes (20→1024)
- `Contents.json` wired to `icon_1024.png` for all three slots (light / dark / tinted)
- Regenerate PNGs: `for size in 20 29 40 58 60 76 80 87 120 152 167 180 1024; do rsvg-convert -w $size -h $size "$SVG" -o "$OUT/icon_${size}.png"; done`

## Fork test — COMPLETE ✅
- Deployed `CognitoS3BaseStack-forktest2` + `MileageExpenseStack-forktest2` on same AWS account
- Built iOS app against forktest2 backend — login + expense creation confirmed working
- Proved zero-collision add-on pattern works end-to-end
- forktest2 stacks destroyed after test

## Known fixes applied
- `Models.swift` — `decodeIfPresent` on all fields — DynamoDB omits undefined fields, Swift default Codable throws
- `deploy.sh` REPO_ROOT — fixed to `${BACKEND_DIR}/..` (was resolving to `backend/` not repo root)
- Stack + resource names — all derived from idPrefix, nothing hardcoded
- Deploy scripts — config read via grep not node -e, pre-confirmation resource summary added
- `SummaryView.swift` — added missing `import Combine`, `ShareSheet` wrapper, `DateRangeFilter`

## For forkers
1. Fork + clone `cognito-s3-stack-893`, set `config.ts`, run `deploy.sh` → `base_outputs.json`
2. Fork + clone this repo
3. `BASE_OUTPUTS_PATH=/path/to/base_outputs.json ./backend/scripts/deploy.sh` → `met_outputs.json`
4. Open `ios/MileageTracker893/MileageTracker893.xcodeproj`
5. Drag `met_outputs.json` into Xcode target (Copy if needed + target membership)
6. Create Cognito user via aws CLI
7. `⇧⌘K` clean, `⌘B` build, `⌘R` run

## Next session — start here
1. Read this file
2. Project is complete and pushed to `dev` — next project is `music-player-893`
