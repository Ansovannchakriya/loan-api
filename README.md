# Loan Prediction API

A small FastAPI app that predicts if a loan should be approved. The model is a scikit-learn logistic regression trained on generated data. I packaged it with Docker for the Docker module: there is a production image, a Compose setup with PostgreSQL, and the image is on Docker Hub.

## How to run

Run the image from Docker Hub (no files needed):

```bash
docker run --rm -p 8000:8000 sovannchakriya/loan-api:1.0.0
```

Then open http://localhost:8000/docs.

Or run everything with Compose (api, PostgreSQL and Adminer):

```bash
docker compose up -d --build
docker compose ps
```

- API docs: http://localhost:8000/docs
- Adminer (to look at the database): http://localhost:8080

Stop it with `docker compose down`.

## Endpoints

- `GET /health` - returns the status, the Docker health check uses this
- `POST /predict` - returns `approved` and `probability` for one application

Example body for `/predict`:

```json
{
  "income": 3000,
  "loan_amount": 2000,
  "credit_score": 780,
  "years_employed": 10,
  "has_default": false
}
```

Answer:

```json
{
  "approved": true,
  "probability": 1.0
}
```

`income` and `loan_amount` must be more than 0, `credit_score` is 300 to 850 and `years_employed` is 0 to 60. Wrong values give a 422.

## Settings

- `MODEL_PATH` - where the model file is. In the image it is `/app/model/model.joblib`.
- `DATABASE_URL` - optional. If it is set (Compose sets it), each prediction is saved in the `predictions` table.

## About the production image

`Dockerfile.prod` uses two stages. The first stage installs the packages and trains the model, the second one only copies the virtual environment, the model and `main.py` into `python:3.12-slim`. It runs as a non-root user (`app`) and has a `HEALTHCHECK` that calls `/health`. The proof for each requirement is in [CHECKLIST.md](CHECKLIST.md).

## Files

- `main.py` - the API
- `train.py` - trains the model (runs during the image build)
- `Dockerfile` - image for development (auto reload)
- `Dockerfile.prod` - image for production
- `compose.yaml` - api, db and adminer
- `init.sql` - creates the `predictions` table
- `requirements.txt` / `requirements-dev.txt` - packages (dev adds pytest and httpx)
- `tests/test_main.py` - tests
- `collect-evidence.ps1` - script I used to run the checklist commands

## Tests

```bash
pip install -r requirements-dev.txt
pytest
```
