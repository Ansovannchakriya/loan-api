import importlib
import os
import subprocess
import sys

import pytest
from fastapi.testclient import TestClient


@pytest.fixture(scope="module")
def client(tmp_path_factory):
    model_path = tmp_path_factory.mktemp("model") / "model.joblib"
    os.environ["MODEL_PATH"] = str(model_path)
    subprocess.run([sys.executable, "train.py"], check=True)
    import main
    importlib.reload(main)
    with TestClient(main.app) as c:
        yield c


GOOD = {"income": 3000, "loan_amount": 2000, "credit_score": 780, "years_employed": 10, "has_default": False}


def test_health(client):
    assert client.get("/health").json() == {"status": "ok", "model_loaded": True}


def test_predict_good_applicant(client):
    r = client.post("/predict", json=GOOD)
    assert r.status_code == 200
    assert r.json()["approved"] is True


def test_predict_risky_applicant(client):
    risky = {**GOOD, "income": 400, "loan_amount": 30000, "credit_score": 420, "has_default": True}
    assert client.post("/predict", json=risky).json()["approved"] is False


def test_invalid_credit_score_is_422(client):
    assert client.post("/predict", json={**GOOD, "credit_score": 900}).status_code == 422
