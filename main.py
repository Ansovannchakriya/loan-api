"""Loan prediction API. The model file location comes from the MODEL_PATH environment variable."""
import logging
import os
from contextlib import asynccontextmanager

import joblib
from fastapi import FastAPI
from pydantic import BaseModel, Field

MODEL_PATH = os.getenv("MODEL_PATH", "model/model.joblib")
DATABASE_URL = os.getenv("DATABASE_URL")  # optional: when set, predictions are logged to PostgreSQL

log = logging.getLogger("loan-api")
state = {}


@asynccontextmanager
async def lifespan(app: FastAPI):
    bundle = joblib.load(MODEL_PATH)
    state["model"] = bundle["model"]
    state["version"] = bundle["version"]
    yield
    state.clear()


app = FastAPI(title="Loan Prediction API", version="1.0.0", lifespan=lifespan)


class LoanApplication(BaseModel):
    income: float = Field(..., gt=0, description="Monthly income in USD")
    loan_amount: float = Field(..., gt=0, description="Requested loan in USD")
    credit_score: int = Field(..., ge=300, le=850)
    years_employed: int = Field(..., ge=0, le=60)
    has_default: bool = Field(..., description="Has the applicant defaulted before?")


class Prediction(BaseModel):
    approved: bool
    probability: float


def save_prediction(app_in: LoanApplication, result: Prediction):
    """Store the prediction when a database is configured; never fail the request because of it."""
    if not DATABASE_URL:
        return
    try:
        import psycopg

        with psycopg.connect(DATABASE_URL, connect_timeout=3) as conn:
            conn.execute(
                "INSERT INTO predictions (income, loan_amount, credit_score, years_employed,"
                " has_default, approved, probability) VALUES (%s, %s, %s, %s, %s, %s, %s)",
                (app_in.income, app_in.loan_amount, app_in.credit_score, app_in.years_employed,
                 app_in.has_default, result.approved, result.probability),
            )
    except Exception as exc:  # the API still answers if the database is down
        log.warning("Could not save prediction: %s", exc)


@app.get("/health")
def health():
    return {"status": "ok", "model_version": state.get("version"), "model_path": MODEL_PATH}


@app.post("/predict", response_model=Prediction)
def predict(application: LoanApplication):
    row = [[application.income, application.loan_amount, application.credit_score,
            application.years_employed, int(application.has_default)]]
    probability = float(state["model"].predict_proba(row)[0][1])
    result = Prediction(approved=probability >= 0.5, probability=round(probability, 4))
    save_prediction(application, result)
    return result
