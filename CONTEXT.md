# CONTEXT.md — mileage-expense-tracker-893
# Read this first at the start of every session.

## What this repo is
Standalone add-on for cognito-s3-stack-893. Tracks vehicle mileage and expenses with OCR receipt scanning.

## Architecture decisions
- **Auth**: Cognito from shared base stack (no Amplify SDK — raw URLSession + Cognito SRP for iOS)
- **base_outputs.json**: Read via BASE_OUTPUTS_PATH env var (not relative path, not copied)
- **met_outputs.json**: Written to repo root by deploy.sh, gitignored. Also gitignored inside Xcode target.
- **Separate repos**: This app is standalone, not nested inside cognito-s3-stack-893
- **Stack + resource names**: All derived from `idPrefix` (parsed from base `public_bucket` name) — no hardcoded names, no same-account collisions

## Repo family
- `cognito-s3-stack-893` — forkable base (Cognito + S3 + IAM), deploy first
- `mileage-expense-tracker-893` — this repo ✅ complete
- `music-player-893` — not created yet

## Backend status ✅ Complete + Deployed
- `backend/bin/app.ts` — derives `idPrefix` from `base_outputs.json`, stack name = `MileageExpenseStack-{idPrefix}`
- `backend/lib/met-stack.ts` — all resource names use `idPrefix` prefix (tables, bucket, API, groups)
- `backend/lib/base-outputs.ts` — TypeScript type for base_outputs.json
- `backend/lambda/vehicles/` — CRUD
- `backend/lambda/trips/` — CRUD
- `backend/lambda/expenses/` — CRUD + presigned S3 URLs
- `backend/lambda/ocr/` — S3 trigger → Textract
- `backend/scripts/deploy.sh` — derives idPrefix via grep, shows resource summary before confirm, writes met_outputs.json to repo root

## Deployed values (test893)
- Stack: MileageExpenseStack-test893
- API: https://1a6uphz606.execute-api.us-east-1.amazonaws.com/prod/
- User Pool: us-east-1_9v0zP2VID
- App Client: 1rr1jpp7651pttbr9fjmkai00d
- Identity Pool: us-east-1:e852387e-bd32-4c67-9fa9-2362c85a8e0a
- Receipts bucket: met893-receipts
- Tables: met893-vehicles, met893-trips, met893-expenses

## iOS status ✅ Complete
SwiftUI, MVVM, raw URLSession + Cognito SRP (no Amplify)

### Files
- `Config/AppConfig.swift` — loads met_outputs.json from bundle, zero hardcoded values
- `Config/AppColors.swift` — full design system
- `Models/Models.swift` — Vehicle, Trip, Expense, OCR types, all API request bodies. Uses decodeIfPresent for safe decoding of fields DynamoDB may omit.
- `Services/AuthService.swift` — Cognito SRP, Keychain token storage, auto-refresh
- `Services/NetworkService.swift` — generic GET/POST/PUT/DELETE with JWT injection
- `Services/LocationManager.swift` — CoreLocation GPS tracking, real-time distance
- `Services/CameraImagePicker.swift` — camera + photo library picker
- `Services/ReceiptScanner.swift` — on-device Vision OCR (amount, date, merchant)
- `Services/ReceiptUploader.swift` — pre-signed S3 PUT flow
- `Views/ContentView.swift` — auth gate, tab bar
- `Views/LoginView.swift` — email/password, Cognito SRP
- `Views/VehiclesView.swift` — list, add, edit, delete
- `Views/TripsView.swift` — list, add (GPS + odometer), delete. 3-step trip flow.
- `Views/ExpensesView.swift` — list, add (with receipt OCR), edit, delete
- `Views/SettingsView.swift` — CSV export (trips), app info, sign out

### Key patterns
- `met_outputs.json` bundled in Xcode target → AppConfig reads it at startup
- `met_outputs.example.json` committed at repo root and inside Xcode folder
- No Amplify, no third-party auth libs
- All views use MVVM with `@StateObject` ViewModels

## Known issues fixed this session
- `Models.swift` — added `init(from:)` with `decodeIfPresent` on Vehicle, Trip, Expense, OCRData. DynamoDB omits undefined fields entirely; Swift's default Codable decoder throws on missing non-optional fields.
- `deploy.sh` REPO_ROOT — was `${SCRIPT_DIR}/..` (resolves to `backend/`), fixed to `${BACKEND_DIR}/..` (resolves to repo root)
- Stack + resource names were hardcoded — now all derived from `idPrefix`

## For forkers / new deployments
1. Fork + clone `cognito-s3-stack-893`
2. `cp base/bin/config.example.ts base/bin/config.ts` — fill in unique `id`, email
3. `cd base && ./scripts/deploy.sh` → creates `CognitoS3BaseStack-{id}`, writes `base_outputs.json`
4. Fork + clone `mileage-expense-tracker-893`
5. `BASE_OUTPUTS_PATH=/path/to/base_outputs.json ./backend/scripts/deploy.sh` → creates `MileageExpenseStack-{id}`, writes `met_outputs.json`
6. Drag `met_outputs.json` into Xcode target (check Copy if needed + target membership)
7. Build and run

## Fork test status (forktest2)
- Base stack: `CognitoS3BaseStack-forktest2` ✅ deployed
- MET stack: `MileageExpenseStack-forktest2` ✅ deployed
- met_outputs.json: written to fork repo root ✅
- iOS Option B test: in progress — open fork Xcode project, add met_outputs.json, build

## Next session — start here
1. Read this file
2. If fork iOS test not completed: open fork Xcode project, add met_outputs.json, create Cognito user, build + run
3. Clean up forktest2 AWS stacks when done (see destroy commands in cognito-s3-stack-893/CONTEXT.md)
4. Start `music-player-893` standalone repo
