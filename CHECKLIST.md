# Production checklist — loan-api

Evidence that the production image built from `Dockerfile.prod` meets each requirement.
All commands were run in PowerShell with Docker Desktop on 6 November 2026, from the repository root.
The full raw output was produced by `collect-evidence.ps1`.

| # | Requirement | Result |
|---|-------------|--------|
| 1 | Slim base image and multi-stage build | ✅ |
| 2 | Runs as a non-root user | ✅ |
| 3 | Health check built into the image | ✅ |
| 4 | Configuration from environment variables (`MODEL_PATH`) | ✅ |
| 5 | Pinned dependencies, no dev tools in the image | ✅ |
| 6 | No secrets in the image or the repository; strict `.dockerignore` | ✅ |
| 7 | Vulnerability scan with Trivy, findings handled | ✅ 0 CRITICAL; Python HIGH fixed; OS HIGH explained below |

---

## 1. Slim base image and multi-stage build

`Dockerfile.prod` has two stages. The `builder` stage creates a virtual environment, installs `requirements.txt` and trains the model. The final stage starts again from `python:3.12-slim` and copies only `/opt/venv`, the trained model and `main.py`. `train.py`, pip caches and the test tools never reach the final image.

```powershell
docker build -t loan-api:dev -f Dockerfile .
docker build -t loan-api:prod -f Dockerfile.prod .
docker images loan-api
```

```
IMAGE           ID             DISK USAGE   CONTENT SIZE   EXTRA
loan-api:dev    5d8eeb5b7301        589MB          138MB        
loan-api:prod   dd08bf7f34f9        611MB          143MB
```

Both images use the slim base. The production image is about the same size as the development one because almost all of the size is the runtime libraries (NumPy, SciPy, scikit-learn) that both need; the difference is in **what** is inside: the production image has no pytest, httpx, training script or tests, and it adds an OS security upgrade layer.

## 2. Runs as a non-root user

```powershell
docker run --rm loan-api:prod whoami
docker inspect --format '{{.Config.User}}' loan-api:prod
```

```
app
app
```

The image creates a system user `app` and switches to it with `USER app`.

## 3. Health check built into the image

The `HEALTHCHECK` is defined in `Dockerfile.prod` (it calls `/health`), so `compose.yaml` does not need one for `api`; every platform that runs the image gets it.

```powershell
docker compose up -d --build
Start-Sleep 35
docker compose ps
```

```
NAME                 IMAGE                COMMAND                  SERVICE   CREATED          STATUS                    PORTS
loan-api-adminer-1   adminer:4            "entrypoint.sh docke…"   adminer   55 minutes ago   Up 55 minutes             0.0.0.0:8080->8080/tcp, [::]:8080->8080/tcp
loan-api-api-1       loan-api-api         "uvicorn main:app --…"   api       40 seconds ago   Up 36 seconds (healthy)   0.0.0.0:8000->8000/tcp, [::]:8000->8000/tcp
loan-api-db-1        postgres:16-alpine   "docker-entrypoint.s…"   db        55 minutes ago   Up 55 minutes (healthy)   5432/tcp
```

`api` and `db` are both `(healthy)`; `adminer` is running.

## 4. Configuration from environment variables (`MODEL_PATH`)

`main.py` reads `MODEL_PATH` (default `model/model.joblib`) and the optional `DATABASE_URL`. The image sets `MODEL_PATH=/app/model/model.joblib`.

```powershell
docker inspect --format '{{json .Config.Env}}' loan-api:prod
```

```
["PATH=/opt/venv/bin:/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin","LANG=C.UTF-8","GPG_KEY=7169605F62C751356D054A26A821E680E5FA6305","PYTHON_VERSION=3.12.15","PYTHON_SHA256=c2c4321961fab0fb999d66e0cecf521c2ab3994c7992873ea99e306c1094fd5a","PYTHONDONTWRITEBYTECODE=1","PYTHONUNBUFFERED=1","MODEL_PATH=/app/model/model.joblib"]
```

Pointing `MODEL_PATH` at a missing file makes the API refuse to start, which proves the variable is really used:

```powershell
docker run --name bad-path -e MODEL_PATH=/app/model/missing.joblib loan-api:prod
```

```
INFO:     Started server process [1]
INFO:     Waiting for application startup.
ERROR:    Traceback (most recent call last):
  File "/opt/venv/lib/python3.12/site-packages/starlette/routing.py", line 661, in lifespan
    async with self.lifespan_context(app) as maybe_state:
               ^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/contextlib.py", line 210, in __aenter__
    return await anext(self.gen)
           ^^^^^^^^^^^^^^^^^^^^^
  File "/app/main.py", line 19, in lifespan
    state["model"] = joblib.load(MODEL_PATH)
                     ^^^^^^^^^^^^^^^^^^^^^^^
  File "/opt/venv/lib/python3.12/site-packages/joblib/numpy_pickle.py", line 650, in load
    with open(filename, 'rb') as f:
         ^^^^^^^^^^^^^^^^^^^^
FileNotFoundError: [Errno 2] No such file or directory: '/app/model/missing.joblib'

ERROR:    Application startup failed. Exiting.
```

(`GPG_KEY` above is the public key of the official Python image, used to verify the Python download. It is not a secret.)

## 5. Pinned dependencies, no dev tools in the image

Every runtime package has an exact version. Test tools (`pytest`, `httpx`) are only in `requirements-dev.txt`, which the production image never installs.

```powershell
Get-Content requirements.txt
```

```
fastapi==0.143.0
uvicorn==0.34.0
scikit-learn==1.6.1
joblib==1.4.2
numpy==2.2.2
psycopg[binary]==3.2.4
```

```powershell
docker run --rm loan-api:prod pip list | Select-String -Pattern "pytest|httpx"
```

```
(no output: pytest and httpx are not installed in the production image)
```

## 6. No secrets in the image or the repository

`.dockerignore` excludes `.git`, `.env`, tests, caches, `compose.yaml`, `init.sql` and documentation, so the image only contains the application:

```powershell
docker run --rm loan-api:prod ls -la /app
```

```
total 16
drwxr-xr-x 1 root root 4096 Nov  6 10:16 .
drwxr-xr-x 1 root root 4096 Nov  6 10:18 ..
-rwxr-xr-x 1 root root 2520 Nov  6 09:03 main.py
drwxr-xr-x 2 root root 4096 Nov  6 10:16 model
```

No password, secret or token in any image layer:

```powershell
docker history --no-trunc loan-api:prod | Select-String -Pattern "password|secret|token"
```

```
(no output: nothing found)
```

Search of the repository:

```powershell
git grep -nIiE "password|secret|token"
```

```
README.md:91:- **Pinned dependencies** and a strict `.dockerignore`, so no tests, caches or secrets go into the image.
compose.yaml:9:      DATABASE_URL: postgresql://loan:loan_dev_password@db:5432/loans
compose.yaml:18:      POSTGRES_PASSWORD: loan_dev_password   # development only
```

The only password is the **development-only** database password in `compose.yaml` (the allowed exception). The README line is just the word "secrets" in a sentence.

## 7. Vulnerability scan with Trivy

```powershell
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --severity HIGH,CRITICAL --no-progress loan-api:prod
```

Result summary:

| Target | Type | HIGH | CRITICAL |
|--------|------|------|----------|
| loan-api:prod (debian 13.7) | debian | 49 | 0 |
| Python packages in `/opt/venv` | python-pkg | 0 | 0 |

### Notes on HIGH / CRITICAL findings

**Rebuilt and fixed: Starlette (3 HIGH).** The first scan found CVE-2025-62727, CVE-2026-48818 and CVE-2026-54283 in `starlette 0.41.3`, which came with FastAPI 0.115.6. I upgraded FastAPI to `0.143.0` (it brings a fixed Starlette 1.x), rebuilt the image and scanned again: the Python packages now have **0** HIGH or CRITICAL findings.

**Cannot be fixed yet: Debian OS packages (49 HIGH).** Every remaining finding is in a package of the `python:3.12-slim` base (Debian 13). Trivy lists **no fixed version** for any of them: Debian marks them `affected` (fix not released yet) or `fix_deferred`. The final stage already runs `apt-get update && apt-get upgrade`, so the image has the newest packages Debian publishes. They will be fixed by rebuilding when Debian releases the patches.

| CVE | Packages | Debian status | Why it cannot be fixed yet / risk here |
|-----|----------|---------------|------------------------------------------|
| CVE-2026-76642, CVE-2026-78408, CVE-2026-78409, CVE-2026-78410 | util-linux family: bsdutils, libblkid1, liblastlog2-2, libmount1, libsmartcols1, libuuid1, login, mount, util-linux | affected | No fix released. These are mount / nsenter tools; the API never calls them and runs as non-root. |
| CVE-2026-119373, CVE-2026-119374, CVE-2026-119379 | libsqlite3-0 | affected | No fix released. The API does not use SQLite (it uses PostgreSQL). |
| CVE-2026-16742 | libsystemd0, libudev1 | affected | No fix released. Affects `systemd-homed`, which does not run in a container. |
| CVE-2025-69720 | libncursesw6, libtinfo6, ncurses-base | affected | No fix released. Terminal library; the API has no interactive terminal. |
| CVE-2026-54369 | libacl1 | affected | No fix released. Needs local symlink access; the container runs as non-root. |
| CVE-2026-76844, CVE-2026-85091 | zlib1g | affected | No fix released. Required by Python itself, so it cannot be removed. |
| CVE-2026-9538 | perl-base | fix_deferred | Debian deferred the fix. Perl's Archive::Tar is never used by the API. |

---

## Published image

```powershell
$DOCKER_USER="sovannchakriya"
docker tag loan-api:prod $DOCKER_USER/loan-api:1.0.0
docker tag loan-api:prod $DOCKER_USER/loan-api:latest
docker push $DOCKER_USER/loan-api:1.0.0
docker push $DOCKER_USER/loan-api:latest
```

Docker Hub: https://hub.docker.com/r/sovannchakriya/loan-api/tags (both `1.0.0` and `latest` listed)

## Pull and run from the registry (no local files)

```powershell
docker compose down
docker rmi $DOCKER_USER/loan-api:1.0.0 $DOCKER_USER/loan-api:latest loan-api:prod
docker run --rm -p 8000:8000 $DOCKER_USER/loan-api:1.0.0
```

`POST /predict` with this body answers **200**:

```json
{
  "income": 3000,
  "loan_amount": 2000,
  "credit_score": 780,
  "years_employed": 10,
  "has_default": false
}
```


![/docs showing the 200 response](screenshots/docs-200.png)
