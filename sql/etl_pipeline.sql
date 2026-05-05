-- =====================================================
-- MAiD ETL Pipeline
-- Description: End-to-end SQL ETL pipeline for integrating
--              and cleaning healthcare datasets
-- Author: Alishba Malik
-- =====================================================

/* =====================================================
   MAiD Healthcare ETL Pipeline
   Purpose: Import raw CSV data, clean and standardize it,
            validate records, join datasets, and create a
            final reporting table for analysis.
   ===================================================== */

---------------------------------------------------------
-- 1. CREATE SCHEMAS
---------------------------------------------------------

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'staging')
    EXEC('CREATE SCHEMA staging');

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'clean')
    EXEC('CREATE SCHEMA clean');

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'reporting')
    EXEC('CREATE SCHEMA reporting');

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'audit')
    EXEC('CREATE SCHEMA audit');


---------------------------------------------------------
-- 2. DROP OLD OBJECTS SO SCRIPT CAN BE RERUN
---------------------------------------------------------

DROP TABLE IF EXISTS reporting.maid_final;
DROP TABLE IF EXISTS clean.mortality_clean;
DROP TABLE IF EXISTS clean.maid_clean;
DROP TABLE IF EXISTS audit.mortality_errors;
DROP TABLE IF EXISTS audit.maid_errors;
DROP TABLE IF EXISTS audit.etl_run_log;
DROP TABLE IF EXISTS staging.mortality_raw;
DROP TABLE IF EXISTS staging.maid_raw;


---------------------------------------------------------
-- 3. CREATE STAGING TABLES
---------------------------------------------------------

CREATE TABLE staging.mortality_raw (
    record_id VARCHAR(20),
    year VARCHAR(10),
    province_code VARCHAR(50),
    total_deaths INT NULL,
    reporting_source VARCHAR(50)
);

CREATE TABLE staging.maid_raw (
    case_id VARCHAR(20),
    province VARCHAR(50),
    year_reported INT,
    maid_cases INT,
    approval_status VARCHAR(20)
);


---------------------------------------------------------
-- 4. IMPORT RAW CSV FILES
-- Update file paths before running
---------------------------------------------------------

BULK INSERT staging.mortality_raw
FROM 'C:\ETL\data\mortality_records_sample.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    TABLOCK
);

BULK INSERT staging.maid_raw
FROM 'C:\ETL\data\maid_procedures_sample.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    TABLOCK
);


---------------------------------------------------------
-- 5. CREATE AUDIT / ERROR TABLES
---------------------------------------------------------

CREATE TABLE audit.etl_run_log (
    run_id INT IDENTITY(1,1) PRIMARY KEY,
    run_time DATETIME DEFAULT GETDATE(),
    status VARCHAR(20),
    step_name VARCHAR(100),
    message VARCHAR(255)
);

CREATE TABLE audit.mortality_errors (
    record_id VARCHAR(20),
    issue VARCHAR(255)
);

CREATE TABLE audit.maid_errors (
    case_id VARCHAR(20),
    issue VARCHAR(255)
);


---------------------------------------------------------
-- 6. CREATE CLEAN TABLES
---------------------------------------------------------

CREATE TABLE clean.mortality_clean (
    province VARCHAR(2),
    year INT,
    total_deaths INT
);

CREATE TABLE clean.maid_clean (
    province VARCHAR(2),
    year INT,
    maid_cases INT
);


---------------------------------------------------------
-- 7. CREATE FINAL REPORTING TABLE
---------------------------------------------------------

CREATE TABLE reporting.maid_final (
    province VARCHAR(2),
    year INT,
    maid_cases INT,
    total_deaths INT,
    percent_of_deaths DECIMAL(6,2),
    PRIMARY KEY (province, year)
);


---------------------------------------------------------
-- 8. CREATE STORED PROCEDURE TO RUN ETL
---------------------------------------------------------

DROP PROCEDURE IF EXISTS dbo.run_maid_etl;
GO

CREATE PROCEDURE dbo.run_maid_etl
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO audit.etl_run_log (status, step_name, message)
        VALUES ('STARTED', 'ETL', 'MAiD ETL pipeline started');

        -------------------------------------------------
        -- Clear previous transformed outputs
        -------------------------------------------------

        TRUNCATE TABLE clean.mortality_clean;
        TRUNCATE TABLE clean.maid_clean;
        TRUNCATE TABLE reporting.maid_final;
        TRUNCATE TABLE audit.mortality_errors;
        TRUNCATE TABLE audit.maid_errors;


        -------------------------------------------------
        -- Capture invalid mortality records
        -------------------------------------------------

        INSERT INTO audit.mortality_errors (record_id, issue)
        SELECT record_id, 'Missing total_deaths'
        FROM staging.mortality_raw
        WHERE total_deaths IS NULL;

        INSERT INTO audit.mortality_errors (record_id, issue)
        SELECT record_id, 'Invalid or missing year'
        FROM staging.mortality_raw
        WHERE TRY_CAST(year AS INT) IS NULL;


        -------------------------------------------------
        -- Capture invalid MAiD records
        -------------------------------------------------

        INSERT INTO audit.maid_errors (case_id, issue)
        SELECT case_id, 'Record not approved'
        FROM staging.maid_raw
        WHERE approval_status <> 'Approved';

        INSERT INTO audit.maid_errors (case_id, issue)
        SELECT case_id, 'Missing or invalid MAiD cases'
        FROM staging.maid_raw
        WHERE maid_cases IS NULL OR maid_cases < 0;


        -------------------------------------------------
        -- Clean mortality data
        -------------------------------------------------

        INSERT INTO clean.mortality_clean (province, year, total_deaths)
        SELECT
            CASE
                WHEN LOWER(province_code) IN ('on', 'ont', 'ontario') THEN 'ON'
                WHEN LOWER(province_code) IN ('qc', 'quebec') THEN 'QC'
                WHEN LOWER(province_code) IN ('bc', 'b.c.', 'british columbia') THEN 'BC'
                WHEN LOWER(province_code) IN ('ab', 'alta', 'alberta') THEN 'AB'
                WHEN LOWER(province_code) IN ('mb', 'man', 'manitoba') THEN 'MB'
                ELSE NULL
            END AS province,
            TRY_CAST(year AS INT) AS year,
            total_deaths
        FROM staging.mortality_raw
        WHERE total_deaths IS NOT NULL
          AND TRY_CAST(year AS INT) IS NOT NULL;


        -------------------------------------------------
        -- Clean MAiD data
        -------------------------------------------------

        INSERT INTO clean.maid_clean (province, year, maid_cases)
        SELECT
            CASE
                WHEN LOWER(province) IN ('on', 'ont', 'ontario') THEN 'ON'
                WHEN LOWER(province) IN ('qc', 'quebec') THEN 'QC'
                WHEN LOWER(province) IN ('bc', 'b.c.', 'british columbia') THEN 'BC'
                WHEN LOWER(province) IN ('ab', 'alta', 'alberta') THEN 'AB'
                WHEN LOWER(province) IN ('mb', 'man', 'manitoba') THEN 'MB'
                ELSE NULL
            END AS province,
            year_reported AS year,
            maid_cases
        FROM staging.maid_raw
        WHERE approval_status = 'Approved'
          AND maid_cases IS NOT NULL
          AND maid_cases >= 0;


        -------------------------------------------------
        -- Deduplicate, aggregate, join, and load final table
        -------------------------------------------------

        WITH mortality_dedup AS (
            SELECT
                province,
                year,
                MAX(total_deaths) AS total_deaths
            FROM clean.mortality_clean
            WHERE province IS NOT NULL
            GROUP BY province, year
        ),
        maid_dedup AS (
            SELECT
                province,
                year,
                SUM(maid_cases) AS maid_cases
            FROM clean.maid_clean
            WHERE province IS NOT NULL
            GROUP BY province, year
        )
        INSERT INTO reporting.maid_final (
            province,
            year,
            maid_cases,
            total_deaths,
            percent_of_deaths
        )
        SELECT
            m.province,
            m.year,
            m.maid_cases,
            d.total_deaths,
            ROUND((m.maid_cases * 100.0 / d.total_deaths), 2) AS percent_of_deaths
        FROM maid_dedup m
        INNER JOIN mortality_dedup d
            ON m.province = d.province
           AND m.year = d.year;


        -------------------------------------------------
        -- Final validation checks
        -------------------------------------------------

        IF EXISTS (
            SELECT 1
            FROM reporting.maid_final
            WHERE percent_of_deaths < 0
               OR percent_of_deaths > 100
        )
        BEGIN
            THROW 50001, 'Validation failed: percent_of_deaths outside valid range.', 1;
        END;

        IF EXISTS (
            SELECT province, year
            FROM reporting.maid_final
            GROUP BY province, year
            HAVING COUNT(*) > 1
        )
        BEGIN
            THROW 50002, 'Validation failed: duplicate province-year records found.', 1;
        END;


        -------------------------------------------------
        -- Log success
        -------------------------------------------------

        INSERT INTO audit.etl_run_log (status, step_name, message)
        VALUES ('SUCCESS', 'ETL', 'MAiD ETL pipeline completed successfully');

        COMMIT TRANSACTION;
    END TRY

    BEGIN CATCH
        ROLLBACK TRANSACTION;

        INSERT INTO audit.etl_run_log (status, step_name, message)
        VALUES ('FAILED', 'ETL', ERROR_MESSAGE());
    END CATCH
END;
GO


---------------------------------------------------------
-- 9. RUN ETL PIPELINE
---------------------------------------------------------

EXEC dbo.run_maid_etl;


---------------------------------------------------------
-- 10. VIEW FINAL REPORTING DATA
---------------------------------------------------------

SELECT *
FROM reporting.maid_final
ORDER BY province, year;


---------------------------------------------------------
-- 11. VIEW AUDIT LOG
---------------------------------------------------------

SELECT *
FROM audit.etl_run_log
ORDER BY run_time DESC;


---------------------------------------------------------
-- 12. VIEW ERROR RECORDS
---------------------------------------------------------

SELECT *
FROM audit.mortality_errors;

SELECT *
FROM audit.maid_errors;
