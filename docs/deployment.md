# CloudHub 2.0 deployment and CI/CD

## How the pipeline works

`.github/workflows/ci-cd.yml`

| Job | Runs on | What it does |
|---|---|---|
| `build-test` | every push and pull request (matrix: the three apps) | Java 17, Maven 3.9.15, `mvn clean verify` = build + MUnit + coverage. A failing test fails the job. MUnit/coverage reports are uploaded as artifacts. |
| `deploy` | push to `main`, after all three `build-test` jobs pass, only when the repository variable `CLOUDHUB_DEPLOY_ENABLED` is `true` | Writes `settings.xml` from secrets, sets each app's `groupId` to the business group ID and its version to `1.0.<run number>`, then for **sys → prc → exp** runs `mvn -P cloudhub2 clean deploy -DmuleDeploy`: publish to Exchange, then deploy to CloudHub 2.0 with the Mule Maven plugin. |

The `deploy` job runs in the GitHub environment `cloudhub-dev`, so the deployment
secrets can be scoped to it and protected with required reviewers. Deployments are
serialised (`concurrency: cloudhub-deploy`).

Each application's `cloudhub2` Maven profile (in its `pom.xml`) holds the
`<cloudhub2Deployment>` configuration: shared space, `vCores` 0.1 (the smallest
replica), 1 replica, Java 17, Connected App authentication (`connectedAppGrantType`
`client_credentials`). Deployment properties set `env=dev` plus each app's lower-API
host; the System API also gets `secure.key` and `db.url` as **secure** properties
(hidden in Runtime Manager).

To build the deployable artifacts without deploying: `mvn -P cloudhub2 clean package`.

## 1. Anypoint Platform

1. Note the **organization (business group) ID**:
   *Access Management → Organization → (your org)*.
2. Pick the environment, e.g. `Sandbox`, and the CloudHub 2.0 shared-space region,
   e.g. `Cloudhub-US-East-2`.
3. Create a **Connected App**: *Access Management → Connected Apps → Create app → App
   acts on its own behalf (client credentials)*. Grant it the scopes for your org and
   environment:
   - **Exchange Contributor**: publish the applications to Exchange (CloudHub 2.0 deploys from Exchange).
   - **Design Center Developer**: required by the Mule Maven plugin for Connected App deployments.
   - **Runtime Manager**: Create Applications, Delete Applications, Read Applications, Read Servers.

   A deployment that fails with 403 means a scope is missing for the selected
   environment.

## 2. Hosted PostgreSQL (System API)

1. Create a database (e.g. Neon or Supabase, free tier) reachable from CloudHub.
2. As the owner, run `db/schema.sql`. Then create the least-privilege runtime role and
   run `db/grants.sql` (edit its `CONNECT ON DATABASE` line to your database name):
   ```sql
   CREATE ROLE patient_app LOGIN PASSWORD '<generated>';
   ```
3. JDBC URL with TLS, for the `DB_URL` secret:
   `jdbc:postgresql://<host>:5432/<db>?sslmode=require&connectTimeout=5&socketTimeout=30`
   (`sslmode=verify-full` with the provider's root certificate is stricter.)

## 3. Secure properties

1. Generate a 16-character key: `openssl rand -base64 12`.
2. Run `scripts/generate-cloud-secrets.sh dev` and enter the key, `patient_app` and its
   password. It writes `patient-sys-api/src/main/resources/config/secure-dev.yaml`,
   which contains **ciphertext only**. Commit that file.
3. Store the same key as the GitHub Secret `MULE_SECURE_KEY`. It is never in Git and
   reaches the app only as a CloudHub secure property.

## 4. GitHub configuration

Secrets (*Settings → Secrets and variables → Actions*). `ANYPOINT_CLIENT_ID` /
`ANYPOINT_CLIENT_SECRET` (and `MULE_EE_REPO_*`) are **repository** secrets, because the
`build-test` job needs them to resolve dependencies from Exchange. The others are used
only by the `deploy` job and can be scoped to the `cloudhub-dev` environment.

| Secret | Value |
|---|---|
| `ANYPOINT_CLIENT_ID` | Connected App client ID |
| `ANYPOINT_CLIENT_SECRET` | Connected App client secret |
| `MULE_SECURE_KEY` | key from step 3 |
| `DB_URL` | JDBC URL from step 2 |
| `MULE_EE_REPO_USERNAME`, `MULE_EE_REPO_PASSWORD` | MuleSoft Enterprise repository (see below) |

Variables:

| Variable | Value |
|---|---|
| `ANYPOINT_BUSINESS_GROUP_ID` | organization / business group ID |
| `CLOUDHUB_ENVIRONMENT` | e.g. `Sandbox` (default) |
| `CLOUDHUB_TARGET` | e.g. `Cloudhub-US-East-2` (default) |
| `CLOUDHUB_MULE_VERSION` | default `4.12.3`; a 4.12.x version Runtime Manager offers |
| `CLOUDHUB_RELEASE_CHANNEL` | default `EDGE` (4.12 is an Edge release) |
| `SYS_API_HOST`, `PRC_API_HOST` | CloudHub hosts, filled in during the first rollout (step 5) |
| `CLOUDHUB_DEPLOY_ENABLED` | `true` to switch deployment on |
| `SYS_API_ID`, `PRC_API_ID` | *optional*, API Manager instance IDs for Client ID Enforcement ([api-manager.md](api-manager.md)). Empty: the APIs are deployed unmanaged (placeholder ID, gatekeeper disabled). |

Optional secrets for Client ID Enforcement, only together with the API IDs:
`SYS_API_CLIENT_ID` / `SYS_API_CLIENT_SECRET` (used by the Process API) and
`PRC_API_CLIENT_ID` / `PRC_API_CLIENT_SECRET` (used by the Experience API). The Experience
API also uses Object Store v2 (Idempotency-Key), enabled in its deployment profile.

### MUnit in CI and the Enterprise repository

MUnit runs the tests on the Mule Enterprise runtime, which Maven downloads from
`MuleRepository`
(`https://repository.mulesoft.org/nexus-ee/content/repositories/releases-ee/`). The
credentials for it are provided by MuleSoft Support. `write-maven-settings.sh` adds the
repository to `settings.xml` when `MULE_EE_REPO_USERNAME` / `MULE_EE_REPO_PASSWORD` are
set. If `build-test` fails while resolving the Mule runtime, these two secrets are
missing or wrong.

## 5. First rollout (hosts are assigned by CloudHub)

CloudHub 2.0 assigns each app's public host on first deployment, and each layer needs
the host of the one below it. The workflow therefore deploys a layer only once that
host is configured:

1. Set the secrets, `ANYPOINT_BUSINESS_GROUP_ID` and `CLOUDHUB_DEPLOY_ENABLED=true`;
   push to `main`. **patient-sys-api** is deployed.
2. Copy its public URL host from Runtime Manager into `SYS_API_HOST`
   (host only, e.g. `patient-sys-api-xxxxxx.yyyyyy.usa-e2.cloudhub.io`); re-run the
   workflow. **patient-prc-api** is deployed as well.
3. Copy the Process API host into `PRC_API_HOST`; re-run. **patient-exp-api** follows.

The Process and Experience APIs call the lower layer at `https://<host>:443` (see
`config/dev.yaml`). CloudHub's ingress terminates TLS and forwards to the app's listener
on port 8081 (`lastMileSecurity` is off, the default).

## 6. After deployment

1. Put the Experience API URL into `postman/patient-registration.cloudhub.postman_environment.json`
   (`baseUrl`).
2. Make sure the patient table is empty (`TRUNCATE TABLE patient; ALTER SEQUENCE patient_id_seq RESTART;`
   as the owner; this is deliberately a manual, explicit step).
3. Run the collection in order:
   `npx newman run postman/patient-registration.postman_collection.json -e postman/patient-registration.cloudhub.postman_environment.json`
4. In Runtime Manager → each app → Logs, check that one `correlationId` appears in all
   three apps for each request.
