# Loan Prediction API

A **FastAPI** service that predicts whether a loan application should be approved, using a **scikit-learn** model.
It is packaged as a **production-ready Docker image**, runs with **Docker Compose** next to PostgreSQL, and is published on **Docker Hub**.

![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-0.143-009688?logo=fastapi&logoColor=white)
![scikit-learn](https://img.shields.io/badge/scikit--learn-1.6-F7931E?logo=scikitlearn&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-multi--stage-2496ED?logo=docker&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)

---

## Quick start

### Run the published image (no local files needed)

```bash
docker run --rm -p 8000:8000 sovannchakriya/loan-api:1.0.0
```

Open **http://localhost:8000/docs**.

### Run the full stack with Compose

```bash
docker compose up -d --build
docker compose ps        # api and db show (healthy)
```

| Service   | URL                          | Purpose                          |
|-----------|------------------------------|----------------------------------|
| `api`     | http://localhost:8000/docs   | Loan prediction API              |
| `db`      | `localhost:5432` (internal)  | PostgreSQL, stores predictions   |
| `adminer` | http://localhost:8080        | Web UI to browse the database    |

Stop everything with `docker compose down`.

---

## API

| Method | Path       | Description                                   |
|--------|------------|-----------------------------------------------|
| `GET`  | `/health`  | Health status, used by the Docker `HEALTHCHECK` |
| `POST` | `/predict` | Predicts approval for one loan application    |

**Example request body**

```json
{
  "income": 3000,
  "loan_amount": 2000,
  "credit_score": 780,
  "years_employed": 10,
  "has_default": false
}
```

Send it with curl:

```bash
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"income": 3000, "loan_amount": 2000, "credit_score": 780, "years_employed": 10, "has_default": false}'
```

**Example response**

```json
{
  "approved": true,
  "probability": 1.0
}
```

| Field            | Type    | Rule                     |
|------------------|---------|--------------------------|
| `income`         | number  | monthly income in USD, > 0 |
| `loan_amount`    | number  | loan in USD, > 0         |
| `credit_score`   | integer | 300 – 850                |
| `years_employed` | integer | 0 – 60                   |
| `has_default`    | boolean | defaulted before?        |

Invalid values return **422**.

---

## Configuration

| Variable       | Default                    | Description                                         |
|----------------|----------------------------|-----------------------------------------------------|
| `MODEL_PATH`   | `/app/model/model.joblib`  | Where the API loads the model from                  |
| `DATABASE_URL` | _not set_                  | Optional. When set, each prediction is saved to PostgreSQL |

---

## Production image

`Dockerfile.prod` is built for production:

- **Multi-stage build**: dependencies are installed and the model is trained in a `builder` stage; only the result is copied into the final image.
- **Slim base**: `python:3.12-slim`, with OS packages upgraded.
- **Non-root user**: runs as `app`.
- **Built-in `HEALTHCHECK`**: calls `/health`, so every platform that runs the image gets it.
- **Pinned dependencies** and a strict `.dockerignore`, so no tests, caches or secrets go into the image.

Evidence for each requirement is in [`CHECKLIST.md`](CHECKLIST.md).

---

## Project structure

```
loan-api/
├── main.py              # FastAPI app (reads MODEL_PATH)
├── train.py             # trains the model during the image build
├── Dockerfile           # development image (auto-reload)
├── Dockerfile.prod      # production image
├── compose.yaml         # api + db + adminer
├── init.sql             # creates the predictions table
├── requirements.txt     # runtime dependencies (pinned)
├── requirements-dev.txt # + pytest, httpx
├── tests/test_main.py   # API tests
└── CHECKLIST.md         # evidence for each requirement
```

---

## Tests

```bash
pip install -r requirements-dev.txt
pytest
```

---

