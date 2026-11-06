# Production checklist — loan-api

Evidence that the production image (`Dockerfile.prod`) meets each requirement.
Run every command from the repository root. Replace each `PASTE OUTPUT HERE` with the real output (or a screenshot).

Docker Hub: https://hub.docker.com/r/DOCKER_USER/loan-api

---

## 1. Small, slim base image with a multi-stage build

`Dockerfile.prod` builds in a `builder` stage (dependencies + model training) and copies only the virtual environment, the model and `main.py` into a fresh `python:3.12-slim` image. Compilers, pip caches and `train.py` stay behind.

```bash
docker build -t loan-api:dev -f Dockerfile .
docker build -t loan-api:prod -f Dockerfile.prod .
docker images loan-api
```

```
PASTE OUTPUT HERE
```

## 2. Runs as a non-root user

```bash
docker run --rm loan-api:prod whoami
docker inspect --format '{{.Config.User}}' loan-api:prod
```

Expected: `app` for both.

```
PASTE OUTPUT HERE
```

## 3. Built-in health check

The `HEALTHCHECK` lives in the image, so `compose.yaml` does not define one for `api`.

```bash
docker compose up -d --build
sleep 35
docker compose ps
```

Expected: `api` and `db` both show `(healthy)`, `adminer` is running.

```
PASTE OUTPUT HERE
```

## 4. Configuration from environment variables (`MODEL_PATH`)

`main.py` reads `MODEL_PATH` (default `model/model.joblib`) and the optional `DATABASE_URL`. Nothing is hard-coded in the image.

```bash
docker inspect --format '{{json .Config.Env}}' loan-api:prod
docker run --rm -e MODEL_PATH=/app/model/missing.joblib loan-api:prod
```

Expected: the first shows `MODEL_PATH=/app/model/model.joblib`; the second fails to start with `FileNotFoundError`, which proves the variable is used.

```
PASTE OUTPUT HERE
```

## 5. Pinned dependencies

Every package in `requirements.txt` has an exact version, and the base image is pinned to `python:3.12-slim`. Test tools live only in `requirements-dev.txt`, so they are not in the production image.

```bash
cat requirements.txt
docker run --rm loan-api:prod pip list 2>/dev/null | grep -iE "pytest|httpx" || echo "no dev packages in the image"
```

```
PASTE OUTPUT HERE
```

## 6. No secrets in the image or the repository; `.dockerignore` keeps the context small

`.dockerignore` excludes `.git`, `.env`, tests, caches and the compose/SQL files. The only password in the repository is the development database password in `compose.yaml` (allowed exception).

```bash
docker run --rm loan-api:prod ls -la /app
docker history --no-trunc loan-api:prod | grep -iE "password|secret|token" || echo "no secrets in image history"
git grep -nIiE "password|secret|token" -- ':!CHECKLIST.md'
```

Expected: `/app` contains only `main.py` and `model/`; the history check prints nothing found; `git grep` shows only the dev password in `compose.yaml`.

```
PASTE OUTPUT HERE
```

## 7. Vulnerability scan with Trivy

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image --severity HIGH,CRITICAL loan-api:prod
```

```
PASTE OUTPUT HERE
```

### Notes on HIGH / CRITICAL findings

The runtime stage runs `apt-get upgrade`, so OS packages are as current as Debian allows at build time.

| CVE | Package | Action |
|-----|---------|--------|
| _none_ / CVE-XXXX-XXXX | pkg | Rebuilt and fixed / No fixed version released yet by Debian (status: will_not_fix / affected) |

---

## Published image

```bash
DOCKER_USER=your-dockerhub-username
docker tag loan-api:prod $DOCKER_USER/loan-api:1.0.0
docker tag loan-api:prod $DOCKER_USER/loan-api:latest
docker push $DOCKER_USER/loan-api:1.0.0
docker push $DOCKER_USER/loan-api:latest
```

```
PASTE OUTPUT HERE
```

## Pull and run from the registry (no local files)

```bash
docker compose down
docker rmi $DOCKER_USER/loan-api:1.0.0 $DOCKER_USER/loan-api:latest loan-api:prod
docker run --rm -p 8000:8000 $DOCKER_USER/loan-api:1.0.0
```

Then open `/docs`, send `POST /predict` with:

```json
{"income": 3000, "loan_amount": 2000, "credit_score": 780, "years_employed": 10, "has_default": false}
```

Screenshot of the 200 response: `screenshots/docs-200.png`
