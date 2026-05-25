# CONTEXT.md — mileage-expense-tracker-893
# Read this first at the start of every session.

## What this repo is
Standalone, forkable mileage and expense tracker. Deploy your own AWS backend against any Cognito User Pool — no dependency on cognito-s3-stack-893 required, but compatible with it. iOS app display name: **MilesExpenses**.

## Architecture decisions
- **Auth**: Raw URLSession + Cognito SRP — no Amplify SDK anywhere
- **Config**: `met_outputs.json` baked into iOS app bundle at build time — zero hardcoded values
- **idPrefix**: Drives all resource names — derived from `base_outputs.json` public_bucket OR set via `ID_PREFIX` env var override
- **Idempotent deploy**: `deploy.sh` checks for existing Cognito app client and API Gateway before CDK runs — never recreates stateful resources
- **CDK import pattern**: When resources exist, CDK imports them via ID (`fromRestApiAttributes`, direct client ID reference) — no recreation risk
- **Standalone**: Not nested inside cognito-s3-stack-893

## Repo family
- `cognito-s3-stack-893` — forkable base stack (optional dependency)
- `mileage-expense-tracker-893` — this repo ✅ complete
- `music-player-893` — not created yet

## Deploy modes
### Option A — Standalone (any Cognito User Pool)
```bash
ID_PREFIX=yourname \
USER_POOL_ID=us-east-1_XXXXXXXXX \
AWS_REGION=us-east-1 \
  ./backend/scripts/deploy.sh
```

### Option B — With cognito-s3-stack-893
```bash
BASE_OUTPUTS_PATH=/path/to/cognito-s3-stack-893/base_outputs.json \
  ./backend/scripts/deploy.sh
```

## deploy.sh idempotency
1. Checks `{id}-met-client` on User Pool → creates only if missing → passes `MET_CLIENT_ID` to CDK
2. Checks `{id}-mileage-expense-api` → if found, fetches root resource ID → passes `MET_API_ID` + `MET_API_ROOT_ID` to CDK
3. CDK imports existing resources via ID — never recreates them
4. On first deploy CDK creates both; on all subsequent deploys both are imported
5. Writes `met_outputs.json` to repo root after deploy

## Backend status ✅ Complete + Deployed
- `backend/bin/app.ts` — supports env var overrides (ID_PREFIX/USER_POOL_ID/AWS_REGION) + base_outputs.json fallback
- `backend/lib/met-stack.ts` — accepts metClientId/metApiId/metApiRootId props; imports or creates accordingly
- `backend/lib/base-outputs.ts` — TypeScript type for base_outputs.json
- `backend/lambda/vehicles/` — CRUD
- `backend/lambda/trips/` — CRUD
- `backend/lambda/expenses/` — CRUD + presigned S3 URLs
- `backend/lambda/ocr/` — S3 trigger → Textract
- `backend/scripts/deploy.sh` — idempotent pre-checks, env var overrides, writes met_outputs.json

## Deployed values — apps-893 (current active deployment on us-east-1_Iijv2ET6V)
- Stack:           MileageExpenseStack-apps-893
- API Gateway:     n5154qou80 — https://n5154qou80.execute-api.us-east-1.amazonaws.com/prod/
- User Pool:       us-east-1_Iijv2ET6V
- App Client:      1d0mnj8j3o26hih4sjdomub19t (apps-893-met-client)
- Identity Pool:   us-east-1:cd8da7d7-bfb5-48c8-bcaf-1021020185b6
- Receipts bucket: apps-893-met-receipts
- Tables:          apps-893-met-vehicles, apps-893-met-trips, apps-893-met-expenses

## Old deployed values — met893 (deprecated, on dlivFriendsDev)
- Stack:           MileageExpenseStack-met893 (old root-level stack, stale)
- API Gateway:     1a6uphz606
- User Pool:       us-east-1_9v0zP2VID (dlivFriendsDev) — wrong pool
- App Client:      1rr1jpp7651pttbr9fjmkai00d
- Identity Pool:   us-east-1:e852387e-bd32-4c67-9fa9-2362c85a8e0a
- Receipts bucket: met893-receipts (data retained, not migrated yet)
- Tables:          met893-vehicles, met893-trips, met893-expenses (data retained, not migrated yet)

## Redeploy command (apps-893 active deployment)
```bash
cd /Users/ltm893/Dev/projects/apps-893/mileage-expense-tracker-893/backend
AWS_PROFILE=dliv-admin \
ID_PREFIX=apps-893 \
USER_POOL_ID=us-east-1_Iijv2ET6V \
AWS_REGION=us-east-1 \
  ./scripts/deploy.sh
```

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

## TripsView ✅ Complete
- `TrackingMode` enum: GPS / Odometer / Both — shown as tappable cards on step 1
- GPS mode: live CoreLocation tracking, skip odometer fields
- Odometer mode: start + end reading, skip GPS step, manual date picker
- Both mode: GPS tracking + odometer fields + comparison section
- List rows: compact — date, miles, purpose (if set) only
- Tap row → sheet with read view + Edit button → inline edit → Save/Cancel
- Swipe to delete

## SummaryView ✅ Complete
- `DateRangeFilter` enum: This Month / Last 30 Days / Last 90 Days / This Year / All Time
- Horizontal pill selector — updates all cards reactively
- Mileage card: total miles, trip count, avg mi/trip, per-vehicle bar chart
- Expenses card: total / vehicle / general pills, by-category bar chart
- Export card: trips, expenses, or combined CSV for the active filter period

## App Icon ✅ Complete
- Speedometer gauge — navy background, teal arc, amber needle, no text
- Source SVG: `Assets.xcassets/AppIcon.appiconset/met_icon_source.svg`
- Regenerate PNGs: `for size in 20 29 40 58 60 76 80 87 120 152 167 180 1024; do rsvg-convert -w $size -h $size "$SVG" -o "$OUT/icon_${size}.png"; done`

## Known fixes applied
- `MileageTracker893App.swift` — removed `UITableViewCell.appearance().backgroundColor = surface` from `applyAppearance()` — setting this globally breaks `.keyboardType` on all TextFields inside SwiftUI Form/List by interfering with the UIKit responder chain; decimal/number pads were rendering as phone pad instead
- `Models.swift` — `decodeIfPresent` on all fields — DynamoDB omits undefined fields
- `deploy.sh` REPO_ROOT — fixed to `${BACKEND_DIR}/..`
- Stack + resource names — all derived from idPrefix
- `SummaryView.swift` — added missing `import Combine`, `ShareSheet` wrapper, `DateRangeFilter`
- `met-stack.ts` — CDK import pattern for app client + API Gateway (never recreates)
- `bin/app.ts` — env var override mode (ID_PREFIX/USER_POOL_ID/AWS_REGION) bypasses base_outputs.json
- `api.url` TS error — `IRestApi` doesn't expose `.url`; reconstructed from known API ID + region

## Stale files to clean up (root-level CDK — superseded by backend/)
- `/lib/met-stack.ts` — old stack with hardcoded pool ID
- `/bin/app.ts` — old CDK entry
- `/bin/config.ts` — hardcoded values
- `/cdk.json` — root-level CDK config
These are safe to delete — `backend/` is the authoritative CDK stack.

## Data migration (not yet done)
Existing data in `met893-*` tables uses Cognito sub values from `dlivFriendsDev`.
New stack (`dliv893-*`) uses `dlivFriendsProd` — different sub values, data not visible.
Old tables and bucket retained. Migration is a future task.

## For forkers
1. Clone this repo
2. Run `deploy.sh` with either Option A (your own pool) or Option B (cognito-s3-stack-893)
3. Open `ios/MileageTracker893/MileageTracker893.xcodeproj`
4. Drag `met_outputs.json` into Xcode target (Copy if needed + target membership)
5. Create Cognito user via aws CLI
6. `⇧⌘K` clean, `⌘B` build, `⌘R` run

## Next steps
1. Copy new `met_outputs.json` into Xcode + rebuild iOS app against dliv893 stack
2. Test login with `ltm893@icloud.com` against `dlivFriendsProd`
3. Clean up stale root-level CDK files (`/lib`, `/bin`, `/cdk.json`)
4. Consider data migration from `met893-*` to `dliv893-*` tables
5. Move on to MusicPlayer — same portability pattern
