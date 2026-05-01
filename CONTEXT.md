# CONTEXT.md — mileage-expense-tracker-893
# Read this first at the start of every session.

## What this repo is
Standalone add-on for cognito-s3-stack-893. Tracks vehicle mileage and expenses with GPS trip tracking, receipt OCR scanning, and CSV export.

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
- `Views/ContentView.swift` — auth gate, tab bar
- `Views/LoginView.swift` — Cognito SRP login
- `Views/VehiclesView.swift` — list, add, edit, delete
- `Views/TripsView.swift` — list, add (GPS + odometer 3-step), delete
- `Views/ExpensesView.swift` — list, add (receipt OCR), edit, delete
- `Views/SettingsView.swift` — CSV export, app info, sign out

## Fork test — COMPLETE ✅
- Deployed `CognitoS3BaseStack-forktest2` + `MileageExpenseStack-forktest2` on same AWS account
- Built iOS app against forktest2 backend — login + expense creation confirmed working
- Proved zero-collision add-on pattern works end-to-end
- forktest2 stacks destroyed after test

## Known fixes applied this session
- `Models.swift` — `decodeIfPresent` on all fields — DynamoDB omits undefined fields, Swift default Codable throws
- `deploy.sh` REPO_ROOT — fixed to `${BACKEND_DIR}/..` (was resolving to `backend/` not repo root)
- Stack + resource names — all derived from idPrefix, nothing hardcoded
- Deploy scripts — config read via grep not node -e, pre-confirmation resource summary added

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
2. Project is complete — next is `music-player-893`
