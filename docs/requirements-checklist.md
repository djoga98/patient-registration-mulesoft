# Requirements traceability

Source of truth: *Take-Home Assignment - Patient Registration APIs (MuleSoft)* (12-page PDF).
Each row is one requirement from the PDF. A status is only "Complete and verified"
when there is executed evidence. Evidence as of 2026-10-19:

- **MUnit**: `mvn clean verify` at the repository root; 107 tests (79 API-level, 28
  DataWeave), 0 failures, 100% application coverage in each app.
- **E2E**: `scripts/e2e-local.sh` against the three apps on a local Mule 4.12.3 runtime
  and Docker PostgreSQL 16 (empty database `patients_b3`); Newman: 13 requests (the 9
  sample cases plus 4 bonus requests), 87 assertions, 0 failures.
- **Failure modes**: `scripts/e2e-failure-modes.sh`; all checks passed.
- **DB test**: `scripts/db-integration-test.sh`; 7/7 checks passed.

Statuses: **Complete and verified** · **Implemented but not verified** · **Blocked by external access** · **Not started** · **Optional**

## Architecture and contracts

| ID | Requirement (PDF) | Implementation | Verification | Status | Notes |
|---|---|---|---|---|---|
| R01 | Three Mule apps, each with its own API spec implemented with APIkit | `patient-{exp,prc,sys}-api`; `src/main/resources/api/*.raml` (RAML 1.0 + types library); `apikit:config` + router in each `<app>.xml` | All three deploy on Mule 4.12.3 and load their RAML; APIkit 400/404/405/415 asserted in MUnit | Complete and verified | |
| R02 | Experience calls only Process, Process only System; only System touches the database | Exp: `process-api-request-config` only; Prc: `system-api-request-config` only; DB connector and driver only in `patient-sys-api/pom.xml` | Dependency lists; E2E logs show the exp→prc→sys chain per correlation ID | Complete and verified | Exp/Prc have no database dependency at all |
| R03 | `POST /api/patients` 201 with created patient; `GET /api/patients/{patientId}` 200, in all three APIs | Operation flows `post:\patients…` / `get:\patients\(patientId)…` in each app | MUnit (each layer); E2E cases 1-3 (201) and 8 (200) | Complete and verified | 201 also sets `Location` |
| R04 | Experience passes the request unchanged, adding `channel: PORTAL` | `exp dwl/PortalView.toProcessRegistration` | MUnit spy: forwarded body = request + `channel`; a caller-supplied channel is replaced | Complete and verified | |
| R05 | Validation 400 in the spec: required fields, `yyyy-MM-dd`, gender enum | `prc api/types/patient-types.raml` (also the portal contract in exp) | MUnit: case 7, malformed date, blank name → 400 without lower call; E2E case 7 | Complete and verified | |
| R06 | Future date of birth → 422 `INVALID_BIRTH_DATE` | `prc dwl/RegistrationRules.isBornInFuture` + choice in `register-patient` | MUnit (tomorrow → 422, no System call; today accepted); DW boundary test; E2E case 6 | Complete and verified | "Today" = clinic time zone |
| R07 | `consents.dataProcessing` must be true → 422 `CONSENT_REQUIRED` | `RegistrationRules.hasDataProcessingConsent` | MUnit (no System call); E2E case 5 | Complete and verified | |
| R08 | Mapping to record (names, birth_date, sex, category, email, phone omitted if absent, consents, `consent_sms` default false, channel → source) | `prc dwl/PatientMapping.toRecord` | MUnit: case 1 record equals the PDF step 4 record exactly; cases 2/3 phone omission, SMS default, MINOR/SENIOR; DW unit tests incl. Unicode, leap day, 17/18/64/65; E2E persisted rows | Complete and verified | |
| R09 | System stores, generates `PAT-` + 6 digits, returns record + `patient_id`, `status: ACTIVE`, `registered_at` UTC | `db/schema.sql` defaults; `sys patient-repository.xml` insert + read-back; `PatientRecords.fromRow` | MUnit; real DB: `PAT-000001…`, `ACTIVE`, `…Z` timestamps | Complete and verified | |
| R10 | Process response: reverse mapping to portal names/values | `PatientMapping.toPatient` | MUnit: equals the PDF step 5 response exactly (POST and GET) | Complete and verified | |
| R11 | Experience response with `fullName` and `age` on the day of the request | `exp dwl/PortalView.toPortalPatient` | DW test: step 5 → step 6 exactly (age 41 on 2026-10-15); API test against an independent `Periods.between` oracle; Postman age check | Complete and verified | |
| R12 | GET returns the same shapes at each layer | Shared mappers for POST and GET in prc and exp | MUnit GET tests per layer; E2E case 8 | Complete and verified | |

## Database

| ID | Requirement (PDF) | Implementation | Verification | Status | Notes |
|---|---|---|---|---|---|
| R13 | Relational DB, schema in `db/schema.sql`, table `patient` with a column per record field, nullable phone | `db/schema.sql` (PostgreSQL), `infrastructure/docker-compose.yml` | Applied by the container init; E2E row check shows NULL phone for case 2 | Complete and verified | Idempotent; never drops data |
| R14 | Unique constraint on (given_name, family_name, birth_date) → 409 `DUPLICATE_PATIENT` | `uq_patient_identity`; `INSERT … ON CONFLICT ON CONSTRAINT uq_patient_identity DO NOTHING` → `APP:DUPLICATE_PATIENT` | DB test (constraint rejects duplicates; ON CONFLICT inserts no row); MUnit (409 each layer); E2E case 4 (`"ANA kovač"`) → 409 | Complete and verified | |
| R15 | Parameterised queries only | `patient-repository.xml`: static SQL, named parameters | Code review: no string building in SQL | Complete and verified | |
| R16 | DB credentials in encrypted secure properties, never in Git in plain text | `secure-properties:config` (AES/CBC); `secure-local.yaml` generated + git-ignored; key via `secure.key` | Local runtime decrypts the generated file and connects; ciphertext verified byte for byte against the module encrypter; `git log` contains no credentials | Complete and verified | CloudHub file `secure-dev.yaml` must be generated with the real credentials (docs/deployment.md) |

## Error handling

| ID | Requirement (PDF) | Implementation | Verification | Status | Notes |
|---|---|---|---|---|---|
| R17 | One global error handler per app | `error-handler.xml` + `defaultErrorHandler-ref` in each app | No flow has its own handler; E2E log shows one error line per request (guard against double handling) | Complete and verified | |
| R18 | 404/409 from System reach the portal as 404/409 | `<lower>-client.xml` + `dwl/Downstream.dwl` re-raise typed errors | MUnit per layer; E2E cases 4 and 9 traced through all three logs | Complete and verified | 422 and 400 also keep their code |
| R19 | No internals in responses | Fixed catalogue messages (`dwl/ApiErrors.dwl`) | MUnit: SQL failure → generic 500 body with exactly 4 fields; failure-mode script checks bodies for exception/SQL/host text | Complete and verified | |
| R20 | Status/code table | `ApiErrors.catalogue` | DW test of the status table; each code produced in MUnit and E2E (500 in MUnit only) | Complete and verified | Additional protocol codes for APIkit 404/405/406/415 |
| R21 | Same error body in all three APIs | Identical `ApiErrors.dwl` / `error-handler.xml` | MUnit body assertions in all apps; Postman checks shape on every error case | Complete and verified | |

## Reliability, correlation, logging

| ID | Requirement (PDF) | Implementation | Verification | Status | Notes |
|---|---|---|---|---|---|
| R22 | Explicit timeouts on every lower-API HTTP call | `responseTimeout` on each `http:request`; `tcp-client-socket-properties connectionTimeout`; budgeted 5 s / 20 s | Config review; live: the Process API timed out the System API after 5 s while the DB was down | Complete and verified | DB query timeout and pgjdbc timeouts too |
| R23 | Retry GET on connectivity, timeout, 503 only; max 3 attempts, short delay; never 4xx | `until-successful` (2 retries, 500 ms) with `failure-status-code-validator values="503"` | MUnit: exactly 3 calls for CONNECTIVITY/TIMEOUT/SERVICE_UNAVAILABLE, 1 for 404/502; live: 3 attempts at Process, 1 at Experience | Complete and verified | |
| R24 | No POST retries; one-sentence reason in README | No retry scope on POST | MUnit (timeout/503/refused → 1 call); live (1 attempt); README *Reliability* | Complete and verified | |
| R25 | Retries exhausted → 502 `DOWNSTREAM_ERROR` | `MULE:RETRY_EXHAUSTED` → `DOWNSTREAM_ERROR` | MUnit; live failure modes | Complete and verified | |
| R26 | Experience reads `X-Correlation-ID` or generates a UUID | `request-context.xml`; `correlationIdGeneratorExpression="#[uuid()]"` | MUnit: given value used; absent → UUID that equals the runtime correlation ID | Complete and verified | |
| R27 | Same value to Process and System, in the response header, in every error body | Explicit header on each request (`sendCorrelationId="NEVER"`); listener response/error-response headers; `errorBody` | MUnit spies at both hops; Postman checks echo + error body on all 9 cases; E2E: one ID in all three logs | Complete and verified | |
| R28 | Every log line in all three apps contains it | JSON log layout field `correlationId` (`%X{correlationId}`) and the same value inside every application event; MUnit proves MDC value = propagated value | E2E log check (`scripts/log-events.js`): every line is JSON, 0 application events without the ID or with a different one; only container startup lines (no event) have none | Complete and verified | |
| R29 | Log request received, each lower call, response sent (status, duration), every error | `request-context.xml`, client sub-flows, error handler | E2E logs (example trace in the README) | Complete and verified | |
| R30 | No patient data in logs | No payload logging; `logException="false"`; c3p0 INFO silenced | E2E log scan for all sample names, emails, phones, birth dates: 0 matches | Complete and verified | |

## Testing

| ID | Requirement (PDF) | Implementation | Verification | Status | Notes |
|---|---|---|---|---|---|
| R31 | MUnit runs in `mvn clean verify`; a failing test stops the pipeline | munit-maven-plugin `test` goal in each POM; CI runs `mvn clean verify` | 107 tests pass; deliberately broken assertion → `BUILD FAILURE`, exit 1 | Complete and verified | Coverage gate 90% |
| R32 | No real systems in tests: every lower-API call and DB operation mocked | `mock-when` on `http:request` (by `config-ref`) and on `db:insert`/`db:select` | Tests run with nothing listening on the configured lower ports and an unreachable DB URL | Complete and verified | Real-DB behaviour is tested separately (DB test, E2E) |

## Platform, repository, CI/CD, deliverables

| ID | Requirement (PDF) | Implementation | Verification | Status | Notes |
|---|---|---|---|---|---|
| R33 | Mule 4.9+ on Java 17 | `minMuleVersion 4.9.0`, `javaSpecificationVersions ["17"]`; MUnit on 4.12.2 EE, local run on 4.12.3 EE, Java 17.0.12 | Builds and runs | Complete and verified | Built with Maven/CLI; Studio import not exercised (standard layout) |
| R34 | Deploy all three to CloudHub 2.0 shared space, smallest replica | `cloudhub2` profile in each POM (0.1 vCores, 1 replica), CD job | `mvn -P cloudhub2 package` builds; parameters checked against the MuleSoft docs | Blocked by external access | No Anypoint account |
| R35 | Lower APIs over HTTPS at CloudHub URLs, per-environment properties, never hard-coded | `config/dev.yaml` (HTTPS 443), host via deployment property (`SYS_API_HOST` / `PRC_API_HOST`) | Config review | Implemented but not verified | Needs a deployment |
| R36 | One repository: folder per app + `db/`, `postman/`, `.github/workflows/` | Repository layout | Present | Complete and verified | Local Git only, no remote yet |
| R37 | GitHub Actions: build + MUnit on every PR and push | `.github/workflows/ci-cd.yml` (`build-test` matrix) | `actionlint` clean | Implemented but not verified | Never ran on GitHub; MUnit on a clean runner needs MuleSoft EE repository credentials |
| R38 | On push to main, after tests, deploy to CloudHub 2.0 with the Mule Maven plugin | `deploy` job (`needs: build-test`) | `actionlint` clean | Blocked by external access | Gated by `CLOUDHUB_DEPLOY_ENABLED` |
| R39 | Connected App ID/secret as GitHub Secrets; secure-properties key a secret | `ANYPOINT_CLIENT_ID/SECRET`, `MULE_SECURE_KEY` → `connectedApp*`, `secureProperties` | Workflow review | Implemented but not verified | |
| R40 | `settings.xml` created in the workflow for Exchange | `.github/scripts/write-maven-settings.sh` (documented Connected App format) | Generated file accepted by Maven 3.9.15, with and without the EE repository | Implemented but not verified | Exchange authentication itself not testable |
| R41 | Postman collection with sample cases + environment pointing at CloudHub | `postman/` collection + local + CloudHub environment (URL placeholder) | Collection run locally: 13 requests, 87/87 assertions | Implemented but not verified | Verified locally; CloudHub URL unknown until deployed |
| R42 | README: architecture, local run, deployment, unfinished work | `README.md`, `docs/deployment.md` | Reviewed against the implementation | Complete and verified | |
| R43 | Sample cases 1-9 give the expected results | Postman collection / `scripts/e2e-local.sh` | All 9 pass locally, in order, on an empty table | Implemented but not verified | PDF asks for this on CloudHub: blocked |
| R44 | Deliver GitHub link and CloudHub URLs | - | - | Blocked by external access | |

## Bonus (optional - only after all must-haves)

| ID | Item | Status | Notes |
|---|---|---|---|
| B1 | Search endpoint `GET /api/patients?lastName=` | Complete and verified | All three layers: Process normalises the term like a registered last name, System matches the stored value exactly (index, max 100, by patient ID). 12 MUnit tests; Postman/E2E cases 10-11 |
| B2 | `Idempotency-Key` on Experience POST with Object Store | Complete and verified | Persistent Object Store (OSv2 on CloudHub), atomic claim, replay of the stored 201, 409 in progress, 422 other body, key released on error. 8 API + 2 DataWeave MUnit tests on the real store; Postman/E2E cases 12-13 (one row stored). OSv2 on CloudHub not verified |
| B3 | Client ID Enforcement on Process and System | Implemented but not verified | Autodiscovery in both, credentials sent by their callers (MUnit stub test, fails with a wrong secret), gatekeeper handling verified on the local runtime, deployment wiring. Policy, instances and contracts need API Manager: docs/api-manager.md |
| B4 | DataWeave mappings in separate `.dwl` modules with their own tests | Complete and verified | 28 DataWeave MUnit tests across the three apps |
| B5 | Minimum MUnit coverage enforced in the build | Complete and verified | `failBuild` below 90%; all apps at 100% |
| B6 | Structured JSON logging | Complete and verified | JSON line layout + JSON application events (`dwl/LogEvent.dwl`); E2E: every line of all three logs parses as JSON. CloudHub collection of the format not verified |
