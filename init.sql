CREATE TABLE IF NOT EXISTS predictions (
    id              SERIAL PRIMARY KEY,
    income          NUMERIC(12, 2) NOT NULL,
    loan_amount     NUMERIC(12, 2) NOT NULL,
    credit_score    INTEGER        NOT NULL,
    years_employed  INTEGER        NOT NULL,
    has_default     BOOLEAN        NOT NULL,
    approved        BOOLEAN        NOT NULL,
    probability     NUMERIC(6, 4)  NOT NULL,
    created_at      TIMESTAMPTZ    NOT NULL DEFAULT now()
);
