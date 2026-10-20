# Client ID Enforcement on the Process and System APIs (API Manager)

The Process and System APIs are protected by the API Manager policy *Client ID
Enforcement*. The code side is part of the applications; the policy, the API instances
and the client applications are set up in Anypoint Platform once the apps are deployed
(see [deployment.md](deployment.md)).

## What is in the code

| Piece | Where |
|---|---|
| API autodiscovery: pairs the main flow with its API Manager instance, so policies applied there run in front of the APIkit router | `patient-sys-api` and `patient-prc-api`, `src/main/mule/global.xml` (`<api-gateway:autodiscovery apiId="${api.id}" …/>`) |
| Callers send their client credentials: `client_id` / `client_secret` headers on every call to the lower API, only when a client ID is configured | `dwl/Downstream.dwl` (`clientCredentialHeaders`), used in `system-api-client.xml` (Process → System) and `process-api-client.xml` (Experience → Process) |
| Contract documentation: RAML security scheme `client-id-enforcement` (headers, 401) | `api/security/client-id-enforcement.raml` in both specs |
| Deployment wiring: `api.id`, `anypoint.platform.gatekeeper`, `systemApi.clientId`/`clientSecret`, `processApi.clientId`/`clientSecret` (secrets as **secure** deployment properties) | `cloudhub2` profiles in the POMs, `.github/scripts/deploy-app.sh`, `.github/workflows/ci-cd.yml` |
| MUnit: a stub lower API that answers 200 only with the expected credentials proves the headers are really sent | `system-api-calls-carry-the-client-credentials`, `process-api-calls-carry-the-client-credentials` |

The Experience API is not managed (the assignment asks for the Process and System APIs).
A 401 from a lower API's policy means *our* credentials are wrong, which the portal
cannot fix: it answers 502 `DOWNSTREAM_ERROR` like any other unexpected lower status, and
is not retried.

### The gatekeeper

With autodiscovery, a runtime that has no API Manager instance to pair with **blocks the
API with 503** in the default gatekeeper mode. The runtime log shows:

```
GateKeeper started in FLEXIBLE mode
Client ID or Client Secret were not provided. API Platform client is DISABLED.
API ApiKey{id='0'} is blocked (unavailable).
```

So wherever an API is not managed, the gatekeeper is off:

- **Locally**, `scripts/run-mule-local.sh` starts the runtime with
  `-Danypoint.platform.gatekeeper=disabled` (and `api.id` is the placeholder `0` in
  `config/local.yaml`).
- **On CloudHub**, `deploy-app.sh` deploys with `api.id=0` and the gatekeeper `disabled`
  while `SYS_API_ID` / `PRC_API_ID` are empty, and with the real instance ID and the
  gatekeeper `flexible` (the platform default: blocked until the policies are applied)
  once they are set. Deploying without API Manager therefore keeps working as before.
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
   | Secret | `ANYPOINT_PLATFORM_CLIENT_ID`, `ANYPOINT_PLATFORM_CLIENT_SECRET` | the **environment's** client ID and secret (*Access Management → Environments → Sandbox*). The System and Process APIs get them as `anypoint.platform.client_id` / `client_secret` (the secret as a secure property) and use them to pair with API Manager and download their policies. |

   The workflow refuses to deploy when an API ID is set without the client ID of its
   caller, which would otherwise lock that caller out, or without the environment
   credentials, without which the gatekeeper keeps the API blocked.
6. **Redeploy** (re-run the workflow on `main`). The order is sys → prc → exp, so for the
   minutes between the System API starting to enforce and the new Process API replica
   taking over, the old Process API calls without credentials and gets 401 (answered as
   502). Activate outside a demo.
7. **Check.** API Manager shows both instances as *Active*. A direct call to the Process or
   System API without headers gets `401`; the Postman collection against the Experience
   API still passes.

## Troubleshooting

- **The new replica never becomes ready and its log shows
  `API ApiKey{id='…'} is blocked (unavailable)`.** The runtime has no environment
  credentials, so it cannot download its policies and the gatekeeper keeps the API
  blocked. Set `ANYPOINT_PLATFORM_CLIENT_ID` / `ANYPOINT_PLATFORM_CLIENT_SECRET` (step 5)
  and redeploy.
- **The portal answers 502 and the lower API logs a 401.** The caller's client ID or
  secret does not match the client application with a contract on that instance.
