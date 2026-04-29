# mileage-expense-tracker-893

CDK infrastructure + Lambda functions for the MET iOS/Android app.

## What gets created

| Resource | Name | Purpose |
|---|---|---|
| Cognito App Client | `met893-mobile-client` | New client on dliv.com's existing User Pool |
| Cognito Groups | `dliv-access`, `mileage-access` | Phase 1: created now. Phase 2: add Pre-Token Lambda to enforce dliv-access on dliv.com |
| Cognito Identity Pool | `met893_identity_pool` | Temporary S3 creds for mobile receipt uploads |
| S3 Bucket | `met893-receipts` | Receipt images (direct upload from mobile) |
| DynamoDB | `met893-vehicles` | Vehicles per user |
| DynamoDB | `met893-trips` | Trips per user (GSI by vehicleId) |
| DynamoDB | `met893-expenses` | Expenses per user (GSI by vehicleId) |
| API Gateway | `met893-api` | REST API with Cognito JWT authorizer |
| Lambda | VehiclesLambda | CRUD for /vehicles |
| Lambda | TripsLambda | CRUD for /trips |
| Lambda | ExpensesLambda | CRUD for /expenses |
| Lambda | OCRLambda | S3-triggered receipt OCR via Textract |

## Receipt upload flow

```
Mobile app
  1. POST /expenses  →  gets back { expenseId, ... }
  2. Upload image to S3 at: receipts/{userId}/{expenseId}.jpg
     (using Identity Pool temporary credentials)
  3. PUT /expenses/{expenseId}  →  attach receiptS3Key
  
S3 event fires automatically:
  4. OCR Lambda calls Textract.AnalyzeExpense
  5. Writes ocrData + ocrStatus=complete back to DynamoDB
  
Mobile app polls or refreshes:
  6. GET /expenses  →  sees ocrData with extracted total, merchant, date
```

## Auth flow (Phase 1)

dliv.com users share the same Cognito User Pool. The mileage app has its own App Client ID. No cross-app restrictions yet — all pool users can use both apps.

## Auth flow (Phase 2 — when you want mileage-only users)

Add a Pre-Token Generation Lambda to dliv.com's app client that checks for `dliv-access` group membership. Users without the group can't get a token for dliv.com. Mileage-only users are added to `mileage-access` only.

## Deploy

```bash
chmod +x scripts/*.sh
./scripts/deploy.sh
```

Outputs are written to `met_outputs.json` — copy this into your iOS and Android projects.

## API Endpoints

All endpoints require `Authorization: Bearer {CognitoIdToken}` header.

| Method | Path | Description |
|---|---|---|
| GET | /vehicles | List all vehicles |
| POST | /vehicles | Create vehicle |
| PUT | /vehicles/{vehicleId} | Update vehicle |
| DELETE | /vehicles/{vehicleId} | Delete vehicle |
| GET | /trips | List all trips |
| GET | /trips?vehicleId=xxx | List trips for one vehicle |
| POST | /trips | Create trip |
| PUT | /trips/{tripId} | Update trip |
| DELETE | /trips/{tripId} | Delete trip |
| GET | /expenses | List all expenses |
| GET | /expenses?vehicleId=xxx | List expenses for one vehicle |
| POST | /expenses | Create expense |
| PUT | /expenses/{expenseId} | Update expense |
| DELETE | /expenses/{expenseId} | Delete expense |
