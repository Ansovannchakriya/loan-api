# Checklist - loan-api

Evidence for each requirement in the lesson table. I ran everything in PowerShell with Docker Desktop on 6 Nov 2026. The commands are in `collect-evidence.ps1` so I could run them all at once.

## 1. Multi-stage Dockerfile.prod: slim base, non-root user, HEALTHCHECK

`Dockerfile.prod` has two stages, both on `python:3.12-slim`. The `builder` stage installs the packages and trains the model, the final stage only copies the virtual environment, the model and `main.py`.

```powershell
Select-String -Path Dockerfile.prod -Pattern "^FROM|^USER|^HEALTHCHECK"
```

```
Dockerfile.prod:4:FROM python:3.12-slim AS builder
Dockerfile.prod:19:FROM python:3.12-slim
Dockerfile.prod:34:USER appuser
Dockerfile.prod:37:HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=3 \
```

`whoami` prints `appuser`:

```powershell
docker run --rm loan-api:prod whoami
```

```
appuser
```

The health check (it calls `/health`) makes the container healthy:

```powershell
docker run -d --name hc-test loan-api:prod
Start-Sleep 30
docker ps --filter name=hc-test --format "{{.Names}}  {{.Status}}"
```

```
hc-test  Up 30 seconds (healthy)
```

## 2. .dockerignore excludes Git, caches, local models and dev config

```powershell
Get-Content .dockerignore
```

```
.git
.github
.gitignore
.venv
venv
__pycache__
*.pyc
.pytest_cache
tests
model
.env
.env.*
*.md
compose.yaml
init.sql
Dockerfile*
.dockerignore
.devcontainer
.vscode
_to_delete
collect-evidence.ps1
evidence.txt
models
```

- Git: `.git`, `.github`, `.gitignore`
- caches: `__pycache__`, `*.pyc`, `.pytest_cache`, `.venv`, `venv`
- local models: `model`, `models`
- dev config: `.env`, `.env.*`, `.vscode`, `.devcontainer`, `compose.yaml`

## 3. Model path configurable with MODEL_PATH

`train.py` saves the model together with its version, and `/health` shows the version of the model that was loaded. The image has model 1.0.0 built in. I trained a 1.1.0 model into a local `models` folder:

```powershell
docker run --rm -v "${PWD}/models:/out" -e MODEL_PATH=/out/model-1.1.0.joblib -e MODEL_VERSION=1.1.0 loan-api:full python train.py
```

```
Saved model 1.1.0 to /out/model-1.1.0.joblib (training accuracy 0.923)
```

Without `MODEL_PATH`, the built-in model is used:

```powershell
docker run -d --name m-default -p 8001:8000 loan-api:prod
Invoke-RestMethod http://localhost:8001/health | ConvertTo-Json -Compress
```

```
{"status":"ok","model_version":"1.0.0","model_path":"/app/model/model.joblib"}
```

With the 1.1.0 model mounted and `MODEL_PATH` pointing to it, `/health` shows 1.1.0:

```powershell
docker run -d --name m-110 -p 8002:8000 -v "${PWD}/models:/models:ro" -e MODEL_PATH=/models/model-1.1.0.joblib loan-api:prod
Invoke-RestMethod http://localhost:8002/health | ConvertTo-Json -Compress
```

```
{"status":"ok","model_version":"1.1.0","model_path":"/models/model-1.1.0.joblib"}
```

## 4. compose.yaml runs API + PostgreSQL + Adminer, API built from Dockerfile.prod

In `compose.yaml` the `api` service has `build: context: .` and `dockerfile: Dockerfile.prod`.

```powershell
docker compose up -d --build
Start-Sleep 35
docker compose ps
```

```
NAME                 IMAGE                COMMAND                  SERVICE   CREATED          STATUS                    PORTS
loan-api-adminer-1   adminer:4            "entrypoint.sh docke…"   adminer   42 seconds ago   Up 41 seconds             0.0.0.0:8080->8080/tcp, [::]:8080->8080/tcp
loan-api-api-1       loan-api-api         "uvicorn main:app --…"   api       42 seconds ago   Up 35 seconds (healthy)   0.0.0.0:8000->8000/tcp, [::]:8000->8000/tcp
loan-api-db-1        postgres:16-alpine   "docker-entrypoint.s…"   db        42 seconds ago   Up 41 seconds (healthy)   5432/tcp
```

All three are up and db is healthy (api too, from the image's health check).

## 5. Image at least 40% smaller than the full-Python variant

`Dockerfile` is the full-Python variant (`FROM python:3.12`), `Dockerfile.prod` is the slim multi-stage one.

```powershell
docker build -t loan-api:full -f Dockerfile .
docker build -t loan-api:prod -f Dockerfile.prod .
docker images loan-api
```

```
IMAGE           ID             DISK USAGE   CONTENT SIZE   EXTRA
loan-api:full   1e29cae071ed       2.01GB          507MB        
loan-api:prod   cd2797328f43        611MB          143MB
```

611 MB vs 2.01 GB: the production image is about 70% smaller (content size 143 MB vs 507 MB, also about 72% smaller).

## 6. No HIGH or CRITICAL findings without a note

```powershell
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --severity HIGH,CRITICAL --no-progress loan-api:prod
```

Result: Debian packages 49 HIGH, 0 CRITICAL. Python packages 0 HIGH, 0 CRITICAL.

Fixed: my first scan found 3 HIGH in starlette 0.41.3 (CVE-2025-62727, CVE-2026-48818, CVE-2026-54283). Starlette comes with FastAPI, so I upgraded FastAPI from 0.115.6 to 0.143.0, rebuilt and scanned again. The Python packages now have 0.

Not fixed yet: the other 49 are all in Debian packages from the `python:3.12-slim` base. Trivy shows no fixed version for any of them (status `affected`, and `fix_deferred` for perl). The image already runs `apt-get upgrade`, so I can only fix them by rebuilding after Debian releases the patches.

- CVE-2026-76642, CVE-2026-78408, CVE-2026-78409, CVE-2026-78410 - util-linux packages (bsdutils, libblkid1, liblastlog2-2, libmount1, libsmartcols1, libuuid1, login, mount, util-linux). No fix yet. These are mount/nsenter tools that the app does not use, and it runs as non-root.
- CVE-2026-119373, CVE-2026-119374, CVE-2026-119379 - libsqlite3-0. No fix yet. The app uses PostgreSQL, not SQLite.
- CVE-2026-16742 - libsystemd0, libudev1. No fix yet. It is about systemd-homed, which does not run in a container.
- CVE-2025-69720 - ncurses (libncursesw6, libtinfo6, ncurses-base). No fix yet. Terminal library, not used by the API.
- CVE-2026-54369 - libacl1. No fix yet. Needs local symlink access.
- CVE-2026-76844, CVE-2026-85091 - zlib1g. No fix yet. Python needs zlib so it cannot be removed.
- CVE-2026-9538 - perl-base. Debian deferred the fix. The app does not use Perl.

No secrets in the image either:

```powershell
docker history --no-trunc loan-api:prod | Select-String -Pattern "password|secret|token"
```

```
(no output)
```

```powershell
git grep -nIiE "password|secret|token"
```

```
compose.yaml:9:      DATABASE_URL: postgresql://loan:loan_dev_password@db:5432/loans
compose.yaml:18:      POSTGRES_PASSWORD: loan_dev_password   # development only
```

The only password is the development database password in `compose.yaml`, which the task allows.

## 7. Image published as sovannchakriya/loan-api:1.0.0 and :latest

```powershell
$DOCKER_USER="sovannchakriya"
docker tag loan-api:prod $DOCKER_USER/loan-api:1.0.0
docker tag loan-api:prod $DOCKER_USER/loan-api:latest
docker push $DOCKER_USER/loan-api:1.0.0
docker push $DOCKER_USER/loan-api:latest
```

Both tags are on https://hub.docker.com/r/sovannchakriya/loan-api/tags

### Run from Docker Hub

I deleted the local images and ran the one from Docker Hub:

```powershell
docker compose down
docker rmi $DOCKER_USER/loan-api:1.0.0 $DOCKER_USER/loan-api:latest loan-api:prod
docker run --rm -p 8000:8000 $DOCKER_USER/loan-api:1.0.0
```

```
Unable to find image 'sovannchakriya/loan-api:1.0.0' locally
1.0.0: Pulling from sovannchakriya/loan-api
44136fa355b3: Already exists
d44ad7cd37c6: Download complete
Digest: sha256:cd2797328f43f2c0b4eef3edd3667239c34892b324d41eab0058d9f678263b51
Status: Downloaded newer image for sovannchakriya/loan-api:1.0.0
INFO:     Started server process [1]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
INFO:     127.0.0.1:39198 - "GET /health HTTP/1.1" 200 OK
```

The digest `cd2797328f43` is the same ID as the `loan-api:prod` image I checked above, so the image on Docker Hub is the one that passed the checks. In a second terminal:

```powershell
Invoke-RestMethod http://localhost:8000/health
```

```
status model_version model_path
------ ------------- ----------
ok     1.0.0         /app/model/model.joblib
```

Then I sent this to `POST /predict` in `/docs` and got 200:

```json
{
  "income": 3000,
  "loan_amount": 2000,
  "credit_score": 780,
  "years_employed": 10,
  "has_default": false
}
```

![200 response in /docs](screenshots/docs-200.png)
