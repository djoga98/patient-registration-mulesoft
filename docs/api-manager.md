# Client ID Enforcement on the Process and System APIs (API Manager)

Status: **prepared in the code, not applied.** No Anypoint account was available, so no
API instance, policy, client application or contract exists yet. Everything below the
"What is in the code" section is done in Anypoint Platform once the apps are deployed
(see [deployment.md](deployment.md)).

## What is in the code

| Piece | Where |
|---|---|
| API autodiscovery: pairs the main flow with its API Manager instance, so policies applied there run in front of the APIkit router | `patient-sys-api` and `patient-prc-api`, `src/main/mule/global.xml` (`<api-gateway:autodiscovery apiId="${api.id}" …/>`) |
| Callers send their client credentials: `client_id` / `client_secret` headers on every call to the lower API, only when a client ID is configured | `dwl/Downstream.dwl` (`clientCredentialHeaders`), used in `system-api-client.xml` (Process → System) and `process-api-client.xml` (Experience → Process) |
| Contract documentation: RAML security scheme `client-id-enforcement` (headers, 401) | `api/security/client-id-enforcement.raml` in both specs |
| Deployment wiring: `api.id`, `anypoint.platform.gatekeeper`, `systemApi.clientId`/`clientSecret`, `processApi.clientId`/`clientSecret` (secrets as **secure** deployment properties) | `cloudhub2` profiles in the POMs, `.github/scripts/deploy-app.sh`, `.github/workflows/ci-cd.yml` |
| MUnit: a stub lower API that answers 200 only with the expected credentials proves the headers are really sent (the test fails with a wrong secret; checked) | `system-api-calls-carry-the-client-credentials`, `process-api-calls-carry-the-client-credentials` |

The Experience API is not managed (the assignment asks for the Process and System APIs).
A 401 from a lower API's policy means *our* credentials are wrong, which the portal
cannot fix: it answers 502 `DOWNSTREAM_ERROR` like any other unexpected lower status, and
is not retried.

### The gatekeeper (verified locally)

With autodiscovery, a runtime that has no API Manager instance to pair with **blocks the
API with 503** in the default gatekeeper mode. Observed on the local Mule 4.12.3 runtime:

```
GateKeeper started in FLEXIBLE mode
Client ID or Client Secret were not provided. API Platform client is DISABLED.
API ApiKey{id='0'} is blocked (unavailable).
```

So wherever an API is not managed, the gatekeeper must be off:

- **Locally**, `scripts/run-mule-local.sh` starts the runtime with
  `-Danypoint.platform.gatekeeper=disabled` (and `api.id` is the placeholder `0` in
  `config/local.yaml`). The E2E and failure-mode scripts passed with autodiscovery in
  place.
- **On CloudHub**, `deploy-app.sh` deploys with `api.id=0` and the gatekeeper `disabled`
  while `SYS_API_ID` / `PRC_API_ID` are empty, and with the real instance ID and the
  gatekeeper `flexible` (the platform default: blocked until the policies are applied)
  once they are set. Deploying without API Manager therefore keeps working exactly as
  before.
- MUnit does not start the gateway; the tests are unaffected.

## Activation (Anypoint Platform)

Do this after the first rollout of all three apps (deployment.md, step 5).

1. **Publish the two specs to Exchange.** *Exchange → Publish new asset → REST API - RAML*,
   upload a zip of `patient-sys-api/src/main/resources/api` (main file
   `patient-sys-api.raml`), and the same for `patient-prc-api`.
2. **Create the API instances.** *API Manager → Add API → From Exchange*: pick the asset,
   *Mule Gateway*, *Basic endpoint* (the app itself is the implementation; no proxy),
   in the same environment as the deployment. Note each instance's **API ID**.
3. **Apply the policy** to both instances: *Policies → Add policy → Client ID Enforcement*,
   credentials origin *Custom Expression* with the defaults
   `#[attributes.headers['client_id']]` and `#[attributes.headers['client_secret']]`.
4. **Client applications and contracts.** In Exchange, on the System API asset,
   *Request access* to its instance with a new client application `patient-prc-api`;
   on the Process API asset, request access with a new application `patient-exp-api`.
   Approve the contracts (*API Manager → Contracts*) if approval is manual.
5. **GitHub configuration** (environment `cloudhub-dev`):

   | Kind | Name | Value |
   |---|---|---|
   | Variable | `SYS_API_ID` | API ID of the System API instance |
   | Variable | `PRC_API_ID` | API ID of the Process API instance |
   | Secret | `SYS_API_CLIENT_ID`, `SYS_API_CLIENT_SECRET` | client application `patient-prc-api` (it calls the System API) |
   | Secret | `PRC_API_CLIENT_ID`, `PRC_API_CLIENT_SECRET` | client application `patient-exp-api` (it calls the Process API) |

   The workflow refuses to deploy when an API ID is set without the client ID of its
   caller, which would otherwise lock that caller out.
6. **Redeploy** (re-run the workflow on `main`). The order is sys → prc → exp, so for the
   minutes between the System API starting to enforce and the new Process API replica
   taking over, the old Process API calls without credentials and gets 401 (answered as
   502). Activate outside a demo.
7. **Check.** API Manager shows both instances as *Active*. A direct call to the Process or
   System API without headers gets `401`; the Postman collection against the Experience
   API still passes.

## Not verified (needs the account)

- Whether CloudHub 2.0 supplies the runtime's platform credentials automatically. The
  MuleSoft page on organization credentials describes setting
  `anypoint.platform.client_id` / `anypoint.platform.client_secret` (the environment's
  client ID and secret) as properties. If API Manager does not show the instances as
  *Active* after step 6, add those two as secure deployment properties for the System and
  Process APIs.
- The exact Exchange/API Manager screen names, which change between platform releases.
- Policy behaviour itself (401 body, contract caching) on CloudHub.
