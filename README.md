# mileage-expense-tracker-893

A standalone add-on for [cognito-s3-stack-893](https://github.com/ltm893/cognito-s3-stack-893).

Tracks vehicle mileage and expenses with GPS trip tracking, receipt photo scanning, and CSV export. iOS app name **MilesExpenses**, built with SwiftUI + raw Cognito SRP auth (no Amplify).

## Features

- **Vehicles** — add, edit, delete vehicles with odometer tracking
- **Trips** — choose GPS, odometer, or both tracking modes; live GPS distance; tap to edit; swipe to delete
- **Expenses** — log expenses with category, receipt photo, on-device OCR auto-fill; tap to edit; swipe to delete
- **Receipt scanning** — Apple Vision framework extracts amount, date, merchant on-device; AWS Textract runs server-side for line items
- **Summary dashboard** — mileage + expense stats with date range filter (This Month / Last 30 / Last 90 / This Year / All Time)
- **CSV export** — export trips, expenses, or combined report for any date range
- **Invite-only auth** — Cognito SRP, Keychain token storage, auto-refresh

## What this deploys

```
MileageExpenseStack-{id}
├── API Gateway              — REST API, Cognito-authorised
├── Lambda: vehicles         — CRUD
├── Lambda: trips            — CRUD
├── Lambda: expenses         — CRUD + presigned S3 upload URLs
├── Lambda: ocr              — S3 trigger → Textract receipt scanning
├── DynamoDB: {id}-met-vehicles
├── DynamoDB: {id}-met-trips
├── DynamoDB: {id}-met-expenses
├── S3: {id}-met-receipts    — receipt photo storage
└── Cognito App Client       — on shared User Pool from base stack
```

All resource names are prefixed with `{id}` derived from your base stack — no hardcoded names, no same-account collisions.

## Prerequisites

1. Deploy [cognito-s3-stack-893](https://github.com/ltm893/cognito-s3-stack-893) first — note the path to its `base_outputs.json`
2. AWS CLI configured, CDK bootstrapped, Node.js 20+

## Deploy backend

```bash
# 1. Clone
git clone https://github.com/ltm893/mileage-expense-tracker-893.git
cd mileage-expense-tracker-893

# 2. Deploy backend
cd backend
chmod +x scripts/deploy.sh
BASE_OUTPUTS_PATH=/path/to/cognito-s3-stack-893/base_outputs.json \
  ./scripts/deploy.sh
# creates MileageExpenseStack-{id}
# writes met_outputs.json at repo root
```

The deploy script shows a summary of exactly what will be created before asking for confirmation.

## Build iOS app

1. Open `ios/MileageTracker893/MileageTracker893.xcodeproj` in Xcode
2. Drag `met_outputs.json` from the repo root into the `MileageTracker893` group in Xcode
   - Check "Copy items if needed"
   - Confirm target membership is checked
3. `⇧⌘K` clean, `⌘B` build, `⌘R` run

The app will appear on your home screen as **MilesExpenses**.

## met_outputs.json

Written to repo root by `deploy.sh`. Gitignored — never committed. A `met_outputs.example.json` is committed showing the schema.

```json
{
  "version": "1",
  "api":     { "aws_region": "...", "base_url": "https://..." },
  "auth":    { "user_pool_id": "...", "user_pool_client_id": "...", "identity_pool_id": "..." },
  "storage": { "receipts_bucket": "..." },
  "tables":  { "vehicles": "...", "trips": "...", "expenses": "..." }
}
```

## Creating a user

```bash
aws cognito-idp admin-create-user \
  --user-pool-id <user_pool_id> \
  --username user@example.com \
  --temporary-password 'TempPass1!' \
  --message-action SUPPRESS \
  --region us-east-1

aws cognito-idp admin-set-user-password \
  --user-pool-id <user_pool_id> \
  --username user@example.com \
  --password 'PermPass1!' \
  --permanent \
  --region us-east-1
```

## API endpoints

All endpoints require `Authorization: <Cognito ID token>`.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/vehicles` | List vehicles |
| POST | `/vehicles` | Add vehicle |
| PUT | `/vehicles/{vehicleId}` | Update vehicle |
| DELETE | `/vehicles/{vehicleId}` | Delete vehicle |
| GET | `/trips` | List trips |
| POST | `/trips` | Log trip |
| PUT | `/trips/{tripId}` | Update trip |
| DELETE | `/trips/{tripId}` | Delete trip |
| GET | `/expenses` | List expenses |
| POST | `/expenses` | Log expense |
| PUT | `/expenses/{expenseId}` | Update expense |
| DELETE | `/expenses/{expenseId}` | Delete expense |
| GET | `/expenses?uploadUrl=1&expenseId=` | Get presigned S3 URL for receipt upload |

## Structure

```
mileage-expense-tracker-893/
├── backend/
│   ├── bin/app.ts              ← CDK entry — derives idPrefix from base_outputs.json
│   ├── lib/met-stack.ts        ← CDK stack — all names use idPrefix
│   ├── lib/base-outputs.ts     ← TypeScript type for base_outputs.json
│   ├── lambda/
│   │   ├── vehicles/index.ts
│   │   ├── trips/index.ts
│   │   ├── expenses/index.ts
│   │   └── ocr/index.ts
│   └── scripts/deploy.sh
├── ios/MileageTracker893/
│   └── MileageTracker893/
│       ├── Config/             ← AppConfig (reads met_outputs.json), AppColors
│       ├── Models/             ← Vehicle, Trip, Expense — safe Codable decoding
│       ├── Services/           ← Auth, Network, Location, Camera, OCR, Upload
│       ├── Assets.xcassets/    ← App icon (speedometer, no text)
│       └── Views/
│           ├── ContentView.swift    ← auth gate, tab bar
│           ├── LoginView.swift
│           ├── VehiclesView.swift   ← list, add, edit, delete
│           ├── TripsView.swift      ← GPS/odometer/both modes, tap to edit, swipe to delete
│           ├── ExpensesView.swift   ← receipt OCR, tap to edit, swipe to delete
│           ├── SummaryView.swift    ← stats dashboard, date filter, CSV export
│           └── SettingsView.swift   ← app info, sign out
├── met_outputs.json            ← gitignored — generated by deploy.sh
└── met_outputs.example.json    ← committed — shows schema for forkers
```

## Estimated AWS costs

| Service | Est. cost at low usage |
|---------|------------------------|
| DynamoDB | $0 (free tier) |
| Lambda | $0 (free tier) |
| API Gateway | $0 (free tier) |
| S3 | ~$0.023/GB/month |
| Textract | $0.0015/page |

## Cleanup

```bash
# Destroy backend stack (DynamoDB tables + S3 bucket are retained)
cd backend
BASE_OUTPUTS_PATH=/path/to/base_outputs.json \
  npx cdk destroy MileageExpenseStack-{id}

# Delete retained resources
aws s3 rb s3://{id}-met-receipts --force
aws dynamodb delete-table --table-name {id}-met-vehicles --region us-east-1
aws dynamodb delete-table --table-name {id}-met-trips --region us-east-1
aws dynamodb delete-table --table-name {id}-met-expenses --region us-east-1
```
