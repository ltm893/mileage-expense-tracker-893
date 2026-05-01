# mileage-expense-tracker-893

A standalone add-on for [cognito-s3-stack-893](https://github.com/ltm893/cognito-s3-stack-893).

Tracks vehicle mileage and expenses with receipt scanning via AWS Textract.

## Structure

```
mileage-expense-tracker-893/
├── backend/               ← CDK stack: DynamoDB, Lambda, API Gateway, S3
│   ├── bin/app.ts         ← CDK entry point (reads base_outputs.json via env var)
│   ├── lib/met-stack.ts   ← Stack definition
│   ├── lambda/
│   │   ├── vehicles/      ← CRUD: vehicles
│   │   ├── trips/         ← CRUD: trips
│   │   ├── expenses/      ← CRUD: expenses + presigned S3 upload URLs
│   │   └── ocr/           ← S3 trigger → Textract receipt scanning
│   └── scripts/deploy.sh  ← Deploy + write met_outputs.json
├── ios/                   ← SwiftUI iOS app (coming soon)
└── met_outputs.json       ← Written by deploy.sh (gitignored)
```

## Prerequisites

1. Deploy [cognito-s3-stack-893](https://github.com/ltm893/cognito-s3-stack-893) first
2. Note the path to its `base_outputs.json`
3. AWS CLI configured, CDK bootstrapped, Node.js 20+

## Deploy

```bash
# 1. Clone this repo
git clone https://github.com/ltm893/mileage-expense-tracker-893.git
cd mileage-expense-tracker-893

# 2. Point to your base stack outputs
export BASE_OUTPUTS_PATH=/path/to/cognito-s3-stack-893/base_outputs.json

# 3. Deploy the backend
cd backend
chmod +x scripts/deploy.sh
./scripts/deploy.sh
# → writes met_outputs.json at repo root
```

## API Endpoints

All endpoints require a Cognito JWT (`Authorization: Bearer <token>`).

| Method | Path | Description |
|--------|------|-------------|
| GET | `/vehicles` | List vehicles |
| POST | `/vehicles` | Add vehicle |
| PUT | `/vehicles/{vehicleId}` | Update vehicle |
| DELETE | `/vehicles/{vehicleId}` | Delete vehicle |
| GET | `/trips` | List trips (filter: `?vehicleId=`) |
| POST | `/trips` | Log trip |
| PUT | `/trips/{tripId}` | Update trip |
| DELETE | `/trips/{tripId}` | Delete trip |
| GET | `/expenses` | List expenses (filter: `?vehicleId=`) |
| POST | `/expenses` | Log expense |
| PUT | `/expenses/{expenseId}` | Update expense |
| DELETE | `/expenses/{expenseId}` | Delete expense |
| GET | `/expenses?uploadUrl=1` | Get presigned S3 URL for receipt upload |

## Receipt OCR

Upload a receipt image to S3 at `receipts/{userId}/{expenseId}.jpg` — Textract automatically extracts total, date, merchant, and line items, writing results back to the expense record.

## Estimated AWS Costs

| Service | Est. cost at low usage |
|---------|------------------------|
| DynamoDB | $0 (free tier) |
| Lambda | $0 (free tier) |
| API Gateway | $0 (free tier) |
| S3 | ~$0.023/GB/month |
| Textract | $0.0015/page |
