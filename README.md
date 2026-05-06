# mileage-expense-tracker-893

A standalone, forkable mileage and expense tracker. Deploy your own AWS backend, build the iOS app against it. No dependency on any other repo required — but compatible with [cognito-s3-stack-893](https://github.com/ltm893/cognito-s3-stack-893) if you want a shared auth base.

iOS app name: **MilesExpenses**. Built with SwiftUI + raw Cognito auth (no Amplify).

## Features

- **Vehicles** — add, edit, delete vehicles with odometer tracking
- **Trips** — GPS, odometer, or both tracking modes; live GPS distance; tap to edit; swipe to delete
- **Expenses** — log expenses with category, receipt photo, on-device OCR auto-fill; tap to edit; swipe to delete
- **Receipt scanning** — Apple Vision extracts amount, date, merchant on-device; AWS Textract runs server-side for line items
- **Summary dashboard** — mileage + expense stats with date range filter (This Month / Last 30 / Last 90 / This Year / All Time)
- **CSV export** — export trips, expenses, or combined report for any date range
- **Invite-only auth** — Cognito SRP, Keychain token storage, auto-refresh

## What this deploys

```
MileageExpenseStack-{id}
├── API Gateway              — REST API, Cognito-authorised, idempotent (never recreated)
├── Lambda: vehicles         — CRUD
├── Lambda: trips            — CRUD
├── Lambda: expenses         — CRUD + presigned S3 upload URLs
├── Lambda: ocr              — S3 trigger → Textract receipt scanning
├── DynamoDB: {id}-met-vehicles
├── DynamoDB: {id}-met-trips
├── DynamoDB: {id}-met-expenses
├── S3: {id}-met-receipts    — receipt photo storage
├── Cognito App Client       — on your User Pool, idempotent (never recreated)
└── Identity Pool            — scoped S3 access for authenticated users
```

All resource names are prefixed with `{id}` — no hardcoded names, no same-account collisions.

## Prerequisites

- AWS CLI configured (`aws configure`)
- AWS CDK bootstrapped (`npx cdk bootstrap`)
- Node.js 20+

## Deploy backend

### Option A — Standalone (bring your own Cognito User Pool)

```bash
git clone https://github.com/ltm893/mileage-expense-tracker-893.git
cd mileage-expense-tracker-893/backend
chmod +x scripts/deploy.sh

ID_PREFIX=yourname \
USER_POOL_ID=us-east-1_XXXXXXXXX \
AWS_REGION=us-east-1 \
  ./scripts/deploy.sh
```

Use any existing Cognito User Pool. The deploy script will create a new App Client on that pool — idempotent, safe to rerun.

### Option B — With cognito-s3-stack-893 base stack

```bash
git clone https://github.com/ltm893/mileage-expense-tracker-893.git
cd mileage-expense-tracker-893/backend
chmod +x scripts/deploy.sh

BASE_OUTPUTS_PATH=/path/to/cognito-s3-stack-893/base_outputs.json \
  ./scripts/deploy.sh
```

The deploy script reads `ID_PREFIX`, `USER_POOL_ID`, and `AWS_REGION` from `base_outputs.json` automatically.

### What deploy.sh does

1. Checks if `{id}-met-client` exists on the User Pool — creates it only if missing
2. Checks if `{id}-mileage-expense-api` exists — imports it into CDK if found, creates if not
3. Runs `cdk deploy` — creates DynamoDB tables, S3 bucket, Identity Pool, Lambdas
4. Writes `met_outputs.json` to the repo root with all resource values

**Idempotent** — safe to run on every deploy. Stateful resources (API Gateway, Cognito App Client, DynamoDB tables, S3 bucket) are never recreated once they exist.

## Build iOS app

1. Open `ios/MileageTracker893/MileageTracker893.xcodeproj` in Xcode
2. Drag `met_outputs.json` from the repo root into the `MileageTracker893` group
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
│   ├── bin/app.ts              ← CDK entry — supports env var overrides + base_outputs.json
│   ├── lib/met-stack.ts        ← CDK stack — imports existing API GW + app client, never recreates
│   ├── lib/base-outputs.ts     ← TypeScript type for base_outputs.json
│   ├── lambda/
│   │   ├── vehicles/index.ts
│   │   ├── trips/index.ts
│   │   ├── expenses/index.ts
│   │   └── ocr/index.ts
│   └── scripts/deploy.sh       ← idempotent deploy + writes met_outputs.json
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
npx cdk destroy MileageExpenseStack-{id}

# Delete retained resources manually
aws s3 rb s3://{id}-met-receipts --force
aws dynamodb delete-table --table-name {id}-met-vehicles --region us-east-1
aws dynamodb delete-table --table-name {id}-met-trips --region us-east-1
aws dynamodb delete-table --table-name {id}-met-expenses --region us-east-1

# Delete Cognito app client
aws cognito-idp delete-user-pool-client \
  --user-pool-id <user_pool_id> \
  --client-id <client_id> \
  --region us-east-1
```
