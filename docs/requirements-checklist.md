# Requirements traceability

Source of truth: *Take-Home Assignment - Patient Registration APIs (MuleSoft)* (12-page PDF).
Each row is one requirement from the PDF. Statuses are only upgraded with evidence.

Statuses: **Complete and verified** · **Implemented but not verified** · **Blocked by external access** · **Not started** · **Optional**

## Architecture and contracts

| ID | Requirement (PDF) | Implementation | Verification | Status | Notes |
|---|---|---|---|---|---|
| R01 | Three Mule apps, each with its own API spec (RAML 1.0/OAS 3) implemented with APIkit | | | Not started | |
| R02 | Experience calls only Process, Process calls only System; only System touches the database | | | Not started | |
| R03 | `POST /api/patients` → 201 with created patient; `GET /api/patients/{patientId}` → 200, in all three APIs | | | Not started | |
| R04 | Experience passes the portal request to Process unchanged, adding `"channel": "PORTAL"` | | | Not started | |
| R05 | Process validation → 400 in the API spec: firstName, lastName, dateOfBirth (yyyy-MM-dd), gender (female/male/other), contact.email, consents.dataProcessing | | | Not started | |
| R06 | Business rule: dateOfBirth not in the future → 422 `INVALID_BIRTH_DATE` | | | Not started | |
| R07 | Business rule: consents.dataProcessing must be true → 422 `CONSENT_REQUIRED` | | | Not started | |
| R08 | Mapping to record: names trimmed + first letter upper/rest lower; birth_date copy; sex F/M/O; category MINOR/ADULT/SENIOR by age today; email lower case; phone without spaces/dashes/brackets, omitted when absent; consents copied; consent_sms defaults to false; channel → source | | | Not started | |
| R09 | System stores the record, generates `PAT-` + six digits, returns record plus `patient_id`, `status: ACTIVE`, `registered_at` (UTC) | | | Not started | |
| R10 | Process response: reverse mapping record → portal field names and values | | | Not started | |
| R11 | Experience response: flatter view with `fullName` and `age` calculated on the day of the request | | | Not started | |
| R12 | GET returns the same shapes at each layer | | | Not started | |

## Database

| ID | Requirement (PDF) | Implementation | Verification | Status | Notes |
|---|---|---|---|---|---|
| R13 | Relational DB; schema script in repo (`db/schema.sql`); table `patient` with one column per record field, `phone` nullable | | | Not started | |
| R14 | Unique constraint on (given_name, family_name, birth_date); violation → 409 `DUPLICATE_PATIENT` | | | Not started | |
| R15 | Parameterised queries only | | | Not started | |
| R16 | DB credentials in encrypted secure properties, never committed in plain text | | | Not started | |

## Error handling

| ID | Requirement (PDF) | Implementation | Verification | Status | Notes |
|---|---|---|---|---|---|
| R17 | One global error handler per app | | | Not started | |
| R18 | Errors keep their meaning across layers (System 404/409 reach the portal as 404/409) | | | Not started | |
| R19 | No internals in responses (stack traces, SQL, hostnames, raw connector messages) | | | Not started | |
| R20 | Status/code table: 400 BAD_REQUEST, 404 PATIENT_NOT_FOUND, 409 DUPLICATE_PATIENT, 422 INVALID_BIRTH_DATE/CONSENT_REQUIRED, 502 DOWNSTREAM_ERROR, 500 INTERNAL_ERROR | | | Not started | |
| R21 | Same error body (`error.code/message/correlationId/timestamp`) in all three APIs | | | Not started | |

## Reliability, correlation, logging

| ID | Requirement (PDF) | Implementation | Verification | Status | Notes |
|---|---|---|---|---|---|
| R22 | Explicit timeouts on every HTTP call to a lower API | | | Not started | |
| R23 | Retry GET calls on transient failures only (connection errors, timeouts, 503); at most 3 attempts with a short delay; never retry 4xx | | | Not started | |
| R24 | Don't retry POST calls; one-sentence reason in README | | | Not started | |
| R25 | When retries run out → 502 `DOWNSTREAM_ERROR` | | | Not started | |
| R26 | Experience reads `X-Correlation-ID` or generates a UUID | | | Not started | |
| R27 | Same value sent to Process and System in `X-Correlation-ID`, returned in the response header, included in every error body | | | Not started | |
| R28 | Every log line in all three apps contains the correlation ID | | | Not started | |
| R29 | Log at least: request received (method, path), each lower-API call, response sent (status, duration), every error | | | Not started | |
| R30 | No patient data in logs (payloads, names, emails, phones, birth dates); patient IDs allowed | | | Not started | |

## Testing

| ID | Requirement (PDF) | Implementation | Verification | Status | Notes |
|---|---|---|---|---|---|
| R31 | MUnit tests run in the build (`mvn clean verify`); a failing test stops the pipeline | | | Not started | |
| R32 | No real systems in tests: every lower-API HTTP call and every DB operation mocked | | | Not started | |

## Platform, repository, CI/CD, deliverables

| ID | Requirement (PDF) | Implementation | Verification | Status | Notes |
|---|---|---|---|---|---|
| R33 | Mule runtime 4.9+ on Java 17 | | | Not started | |
| R34 | Deploy all three apps to CloudHub 2.0 shared space, smallest replica size | | | Not started | |
| R35 | Lower APIs called over HTTPS at CloudHub URLs, set as per-environment properties, never hard-coded | | | Not started | |
| R36 | One repository: folder per app plus `db/`, `postman/`, `.github/workflows/` | | | Not started | |
| R37 | GitHub Actions: build all three apps and run MUnit on every pull request and push | | | Not started | |
| R38 | On push to `main`, after tests pass, deploy to CloudHub 2.0 with the Mule Maven plugin | | | Not started | |
| R39 | Connected App (client credentials) ID/secret as GitHub Secrets; secure-properties key is a secret supplied at deployment | | | Not started | |
| R40 | Maven `settings.xml` created in the workflow for Exchange access | | | Not started | |
| R41 | Postman collection with the sample cases and an environment pointing at CloudHub | | | Not started | |
| R42 | README: architecture overview, how to run locally, how deployment works, what is unfinished / more time | | | Not started | |
| R43 | Sample cases 1-9 give the expected results (in order) | | | Not started | |
| R44 | Deliver GitHub repository link and CloudHub URLs | | | Not started | |

## Bonus (optional - only after all must-haves)

| ID | Item | Status | Notes |
|---|---|---|---|
| B1 | Search endpoint `GET /api/patients?lastName=` through all layers | Optional | |
| B2 | `Idempotency-Key` on Experience POST backed by Object Store | Optional | |
| B3 | Client ID Enforcement in API Manager on Process and System | Optional | |
| B4 | DataWeave mappings in separate `.dwl` modules with their own tests | Optional | |
| B5 | Minimum MUnit coverage enforced in the build | Optional | |
| B6 | Structured JSON logging | Optional | |
