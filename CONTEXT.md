# CONTEXT.md — mileage-expense-tracker-893
# Read this first at the start of every session.

## What this repo is
Standalone add-on for cognito-s3-stack-893. Tracks vehicle mileage and expenses with OCR receipt scanning.

## Architecture decisions
- **Auth**: Cognito from shared base stack (no Amplify SDK — raw URLSession + Cognito SRP for iOS)
- **base_outputs.json**: Read via BASE_OUTPUTS_PATH env var (not relative path, not copied)
- **met_outputs.json**: Written to repo root by deploy.sh, gitignored. Also gitignored inside Xcode target.
- **Separate repos**: This app is standalone, not nested inside cognito-s3-stack-893

## Repo family
- `cognito-s3-stack-893` — forkable base (Cognito + S3 + IAM), deploy first
- `mileage-expense-tracker-893` — this repo ✅ complete
- `music-player-893` — not created yet

## Backend status ✅ Complete + Deployed
- `backend/lib/met-stack.ts` — CDK stack
- `backend/bin/app.ts` — entry point, reads BASE_OUTPUTS_PATH
- `backend/lambda/vehicles/` — CRUD
- `backend/lambda/trips/` — CRUD
- `backend/lambda/expenses/` — CRUD + presigned S3 URLs
- `backend/lambda/ocr/` — S3 trigger → Textract
- `backend/scripts/deploy.sh` — deploy + write met_outputs.json

## iOS status ✅ Complete
SwiftUI, MVVM, raw URLSession + Cognito SRP (no Amplify)

### Files
- `Config/AppConfig.swift` — loads met_outputs.json from bundle, zero hardcoded values
- `Config/AppColors.swift` — full design system
- `Models/Models.swift` — Vehicle, Trip, Expense, OCR types, all API request bodies
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
- `met_outputs.example.json` committed → shows forkers the schema
- No Amplify, no third-party auth libs
- All views use MVVM with `@StateObject` ViewModels

## For forkers / new deployments
1. Deploy `cognito-s3-stack-893` → get `base_outputs.json`
2. `BASE_OUTPUTS_PATH=/path/to/base_outputs.json ./backend/scripts/deploy.sh`
3. Copy `met_outputs.example.json` → `met_outputs.json`, fill in values from deploy output
4. Add `met_outputs.json` to the Xcode target (drag into Xcode, check "Copy if needed")
5. Build and run

## Next session — start here
1. Read this file
2. This project is complete — move on to `music-player-893` or fork testing
