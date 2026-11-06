"""Train a small loan-approval model and save it to MODEL_PATH (default model/model.joblib).
MODEL_VERSION (default 1.0.0) is saved with the model so /health can show it."""
import os
from pathlib import Path

import joblib
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

FEATURES = ["income", "loan_amount", "credit_score", "years_employed", "has_default"]


def make_data(n=5000, seed=42):
    rng = np.random.default_rng(seed)
    income = rng.normal(1500, 600, n).clip(200, 6000)          # monthly income, USD
    loan_amount = rng.normal(8000, 4000, n).clip(500, 40000)   # USD
    credit_score = rng.normal(650, 80, n).clip(300, 850)
    years_employed = rng.integers(0, 30, n)
    has_default = rng.binomial(1, 0.12, n)
    score = (0.002 * income - 0.0002 * loan_amount + 0.015 * (credit_score - 650)
             + 0.05 * years_employed - 2.0 * has_default + rng.normal(0, 0.5, n))
    approved = (score > 1.0).astype(int)
    X = np.column_stack([income, loan_amount, credit_score, years_employed, has_default])
    return X, approved


def main():
    X, y = make_data()
    model = make_pipeline(StandardScaler(), LogisticRegression(max_iter=1000))
    model.fit(X, y)
    path = Path(os.getenv("MODEL_PATH", "model/model.joblib"))
    path.parent.mkdir(parents=True, exist_ok=True)
    version = os.getenv("MODEL_VERSION", "1.0.0")
    joblib.dump({"model": model, "version": version}, path)
    print(f"Saved model {version} to {path} (training accuracy {model.score(X, y):.3f})")


if __name__ == "__main__":
    main()
