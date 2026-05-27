CREATE DATABASE loan_risk_db;
USE loan_risk_db;

CREATE TABLE loans (
    loan_id VARCHAR(20) PRIMARY KEY,
    age INT,
    income DECIMAL(12,2),
    loan_amount DECIMAL(12,2),
    loan_purpose VARCHAR(50),
    tenure_months INT,
    credit_score INT,
    employment_type VARCHAR(30),
    defaulted TINYINT(1)
);
SET GLOBAL local_infile = 1;
LOAD DATA LOCAL INFILE 'D:/Users/yasha/Desktop/Bank Loan Default Risk Analyzer/dataset/Loan_defaultfinal.csv'
INTO TABLE loans
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;
SELECT COUNT(*) FROM loans;
SELECT * FROM loans LIMIT 10;

-- NULL CHECK
SELECT
    SUM(CASE WHEN income IS NULL THEN 1 ELSE 0 END) AS null_income,
    SUM(CASE WHEN credit_score IS NULL THEN 1 ELSE 0 END) AS null_credit,
    SUM(CASE WHEN loan_amount IS NULL THEN 1 ELSE 0 END) AS null_loan_amt,
    SUM(CASE WHEN defaulted IS NULL THEN 1 ELSE 0 END) AS null_defaulted
FROM loans;

-- DUPLICATE DETECTION
SELECT
    loan_id,
    COUNT(*) AS duplicate_count
FROM loans
GROUP BY loan_id
HAVING COUNT(*) > 1;

-- OUTLIER FLAGGING
SELECT
    loan_id,
    income,
    loan_amount,
    credit_score,

    CASE
        WHEN income < 0 OR income > 10000000
            THEN 'Income Outlier'

        WHEN credit_score < 300 OR credit_score > 900
            THEN 'Credit Score Outlier'

        WHEN loan_amount <= 0
            THEN 'Invalid Loan Amount'

        ELSE 'Clean'
    END AS data_quality_flag

FROM loans;

-- OVERALL DEFAULT RATE
SELECT
    COUNT(*) AS total_applicants,
    SUM(defaulted) AS total_defaults,
    ROUND(SUM(defaulted) * 100.0 / COUNT(*), 2) AS default_rate_pct
FROM loans;

-- DEFAULT RATE BY AGE GROUP
SELECT
    CASE
        WHEN age BETWEEN 18 AND 25 THEN '18-25'
        WHEN age BETWEEN 26 AND 35 THEN '26-35'
        WHEN age BETWEEN 36 AND 45 THEN '36-45'
        WHEN age BETWEEN 46 AND 60 THEN '46-60'
        ELSE '60+'
    END AS age_group,

    COUNT(*) AS total_applicants,

    SUM(defaulted) AS total_defaults,

    ROUND(SUM(defaulted) * 100.0 / COUNT(*), 2)
    AS default_rate_pct

FROM loans
GROUP BY age_group
ORDER BY age_group;
-- Younger applicants show the highest default rate.
-- Default risk decreases as age group increases.
-- Banks can apply stricter checks for younger borrower segments.

-- DEFAULT RATE BY CREDIT SCORE BAND

SELECT
    CASE
        WHEN credit_score < 500 THEN 'Very Poor (<500)'
        WHEN credit_score < 600 THEN 'Poor (500-599)'
        WHEN credit_score < 700 THEN 'Fair (600-699)'
        WHEN credit_score < 800 THEN 'Good (700-799)'
        ELSE 'Excellent (800+)'
    END AS credit_band,

    COUNT(*) AS total_applicants,

    SUM(defaulted) AS total_defaults,

    ROUND(SUM(defaulted) * 100.0 / COUNT(*), 2)
    AS default_rate_pct,

    ROUND(AVG(loan_amount),2)
    AS avg_loan_amount

FROM loans
GROUP BY credit_band
ORDER BY MIN(credit_score);
-- Applicants with lower credit scores show higher default rates.
-- Default risk gradually decreases as credit score improves.
-- Credit score alone is not a sufficient predictor of default risk,
-- indicating that income, employment status, and loan burden also influence repayment behavior.

-- DEFAULT RATE BY LOAN PURPOSE

SELECT
    loan_purpose,

    COUNT(*) AS total_applicants,

    SUM(defaulted) AS total_defaults,

    ROUND(SUM(defaulted) * 100.0 / COUNT(*), 2)
    AS default_rate_pct,

    ROUND(AVG(income),2)
    AS avg_income

FROM loans

GROUP BY loan_purpose
HAVING COUNT(*) > 50
ORDER BY default_rate_pct DESC;
-- Business loans exhibit the highest default rate among all loan categories.
-- Home loans show comparatively lower repayment risk, indicating more financially stable borrowers.
-- Banks may apply stricter underwriting policies for business-related borrowing segments.

-- HIGH RISK SEGMENT IDENTIFICATION 

WITH risk_segments AS (
    SELECT
        employment_type,
        CASE
            WHEN credit_score < 600 THEN 'Low Credit'
            WHEN credit_score < 750 THEN 'Medium Credit'
            ELSE 'High Credit'
        END AS credit_tier,

        COUNT(*) AS total_applicants,

        SUM(defaulted) AS total_defaults,

        ROUND(SUM(defaulted) * 100.0 / COUNT(*), 2)
        AS default_rate_pct

    FROM loans
    GROUP BY employment_type, credit_tier
),

high_risk AS (

    SELECT *
    FROM risk_segments
    WHERE default_rate_pct > 12
)

SELECT *
FROM high_risk
ORDER BY default_rate_pct DESC;
-- Unemployed applicants with low credit scores represent the highest-risk borrower segment.
-- Default probability increases significantly when weak employment status is combined with poor creditworthiness.
-- Financial institutions may apply stricter approval criteria and enhanced verification for these high-risk segments.

-- RISK RANKING
SELECT
    loan_id,
    credit_score,
    income,
    loan_amount,
    defaulted,

    ROUND(
        (loan_amount / NULLIF(income,0)) * 100,2) AS loan_to_income_ratio,

    RANK() OVER (
        ORDER BY credit_score ASC,
                 loan_amount DESC
    ) AS risk_rank,

    NTILE(4) OVER (
        ORDER BY credit_score ASC
    ) AS risk_quartile

FROM loans
ORDER BY risk_rank
LIMIT 20;
-- Applicants with the lowest credit scores are ranked as the highest-risk borrowers.
-- High loan-to-income ratios indicate greater repayment pressure on applicants.
-- Risk ranking helps banks prioritize manual review for borrowers with weak credit profiles.

-- FINAL  RISK SCORING MODEL

SELECT
    loan_id,
    age,
    income,
    loan_amount,
    credit_score,
    employment_type,
    defaulted,

    ROUND(
        ((900 - credit_score) / 600.0 * 100 * 0.40) +

        (LEAST((loan_amount / NULLIF(income,0)) * 10, 100) * 0.35) +

        ((CASE
            WHEN age < 25 THEN 70
            WHEN age > 60 THEN 60
            ELSE 30
        END) * 0.15) +

        ((CASE
            WHEN employment_type = 'Unemployed' THEN 100
            WHEN employment_type = 'Part-time' THEN 60
            WHEN employment_type = 'Self-employed' THEN 40
            ELSE 20
        END) * 0.10)

    ,2) AS risk_score,

    CASE
        WHEN ROUND(
            ((900 - credit_score) / 600.0 * 100 * 0.40) +
            (LEAST((loan_amount / NULLIF(income,0)) * 10, 100) * 0.35) +
            ((CASE
                WHEN age < 25 THEN 70
                WHEN age > 60 THEN 60
                ELSE 30
            END) * 0.15) +
            ((CASE
                WHEN employment_type = 'Unemployed' THEN 100
                WHEN employment_type = 'Part-time' THEN 60
                WHEN employment_type = 'Self-employed' THEN 40
                ELSE 20
            END) * 0.10)
        ,2) >= 65 THEN 'HIGH RISK'

        WHEN ROUND(
            ((900 - credit_score) / 600.0 * 100 * 0.40) +
            (LEAST((loan_amount / NULLIF(income,0)) * 10, 100) * 0.35) +
            ((CASE
                WHEN age < 25 THEN 70
                WHEN age > 60 THEN 60
                ELSE 30
            END) * 0.15) +
            ((CASE
                WHEN employment_type = 'Unemployed' THEN 100
                WHEN employment_type = 'Part-time' THEN 60
                WHEN employment_type = 'Self-employed' THEN 40
                ELSE 20
            END) * 0.10)
        ,2) >= 40 THEN 'MEDIUM RISK'

        ELSE 'LOW RISK'
    END AS risk_label

FROM loans
ORDER BY risk_score DESC
LIMIT 20;
-- Applicants with very low credit scores, unemployment status, and high loan amounts receive the highest risk scores.
-- The weighted scoring model combines creditworthiness, income burden, age, and employment stability to classify borrower risk.
-- This rule-based model can help lenders prioritize high-risk applications for manual review before loan approval.

-- export
CREATE VIEW loan_risk_analysis AS

SELECT
    loan_id,
    age,
    income,
    loan_amount,
    loan_purpose,
    tenure_months,
    credit_score,
    employment_type,
    defaulted,

    CASE
        WHEN age BETWEEN 18 AND 25 THEN '18-25'
        WHEN age BETWEEN 26 AND 35 THEN '26-35'
        WHEN age BETWEEN 36 AND 45 THEN '36-45'
        WHEN age BETWEEN 46 AND 60 THEN '46-60'
        ELSE '60+'
    END AS age_group,

    CASE
        WHEN credit_score < 500 THEN 'Very Poor'
        WHEN credit_score < 600 THEN 'Poor'
        WHEN credit_score < 700 THEN 'Fair'
        WHEN credit_score < 800 THEN 'Good'
        ELSE 'Excellent'
    END AS credit_band,

    ROUND(
        ((900 - credit_score) / 600.0 * 100 * 0.40) +

        (LEAST((loan_amount / NULLIF(income,0)) * 10,100) * 0.35) +

        ((CASE
            WHEN age < 25 THEN 70
            WHEN age > 60 THEN 60
            ELSE 30
        END) * 0.15) +

        ((CASE
            WHEN employment_type='Unemployed' THEN 100
            WHEN employment_type='Part-time' THEN 60
            WHEN employment_type='Self-employed' THEN 40
            ELSE 20
        END) * 0.10)

    ,2) AS risk_score,

    CASE
        WHEN ROUND(
            ((900 - credit_score) / 600.0 * 100 * 0.40) +
            (LEAST((loan_amount / NULLIF(income,0)) * 10,100) * 0.35) +

            ((CASE
                WHEN age < 25 THEN 70
                WHEN age > 60 THEN 60
                ELSE 30
            END) * 0.15) +

            ((CASE
                WHEN employment_type='Unemployed' THEN 100
                WHEN employment_type='Part-time' THEN 60
                WHEN employment_type='Self-employed' THEN 40
                ELSE 20
            END) * 0.10)

        ,2) >= 65 THEN 'HIGH RISK'

        WHEN ROUND(
            ((900 - credit_score) / 600.0 * 100 * 0.40) +
            (LEAST((loan_amount / NULLIF(income,0)) * 10,100) * 0.35) +

            ((CASE
                WHEN age < 25 THEN 70
                WHEN age > 60 THEN 60
                ELSE 30
            END) * 0.15) +

            ((CASE
                WHEN employment_type='Unemployed' THEN 100
                WHEN employment_type='Part-time' THEN 60
                WHEN employment_type='Self-employed' THEN 40
                ELSE 20
            END) * 0.10)

        ,2) >= 40 THEN 'MEDIUM RISK'

        ELSE 'LOW RISK'
    END AS risk_label

FROM loans;
SELECT * FROM loan_risk_analysis
ORDER BY RAND()
LIMIT 10000;