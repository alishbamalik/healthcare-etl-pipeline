-- =====================================================
-- MAiD ETL Pipeline
-- Description: End-to-end SQL ETL pipeline for integrating
--              and cleaning healthcare datasets
-- Author: Alishba Malik
-- =====================================================

CREATE PROCEDURE run_maid_etl
AS
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO audit.etl_run_log (status, step, message)
        VALUES ('STARTED', 'ETL', 'Pipeline started');

        --------------------------------------------------
        -- RESET TABLES (RERUN SAFE)
        --------------------------------------------------
        TRUNCATE TABLE clean.mortality_clean;
        TRUNCATE TABLE clean.maid_clean;
        TRUNCATE TABLE reporting.maid_final;
        TRUNCATE TABLE audit.mortality_errors;
        TRUNCATE TABLE audit.maid_errors;

        --------------------------------------------------
        -- VALIDATION / ERROR CAPTURE
        --------------------------------------------------
        INSERT INTO audit.mortality_errors
        SELECT record_id, 'Missing total_deaths'
        FROM staging.mortality_raw
        WHERE total_deaths IS NULL;

        INSERT INTO audit.maid_errors
        SELECT case_id, 'Not approved'
        FROM staging.maid_raw
        WHERE approval_status <> 'Approved';

        --------------------------------------------------
        -- TRANSFORM
        --------------------------------------------------
        INSERT INTO clean.mortality_clean
        SELECT
            CASE 
                WHEN LOWER(province_code) IN ('on','ont','ontario') THEN 'ON'
                WHEN LOWER(province_code) IN ('qc','quebec') THEN 'QC'
                WHEN LOWER(province_code) LIKE '%bc%' THEN 'BC'
                WHEN LOWER(province_code) LIKE '%ab%' THEN 'AB'
                WHEN LOWER(province_code) LIKE '%mb%' THEN 'MB'
                ELSE NULL
            END,
            CAST(year AS INT),
            total_deaths
        FROM staging.mortality_raw
        WHERE total_deaths IS NOT NULL;

        INSERT INTO clean.maid_clean
        SELECT
            CASE 
                WHEN LOWER(province) IN ('on','ontario') THEN 'ON'
                WHEN LOWER(province) IN ('qc','quebec') THEN 'QC'
                WHEN LOWER(province) LIKE '%bc%' THEN 'BC'
                WHEN LOWER(province) LIKE '%ab%' THEN 'AB'
                WHEN LOWER(province) LIKE '%mb%' THEN 'MB'
                ELSE NULL
            END,
            year_reported,
            maid_cases
        FROM staging.maid_raw
        WHERE approval_status = 'Approved';

        --------------------------------------------------
        -- DEDUP + JOIN
        --------------------------------------------------
        WITH mortality_dedup AS (
            SELECT province, year, MAX(total_deaths) AS total_deaths
            FROM clean.mortality_clean
            WHERE province IS NOT NULL
            GROUP BY province, year
        ),
        maid_dedup AS (
            SELECT province, year, SUM(maid_cases) AS maid_cases
            FROM clean.maid_clean
            WHERE province IS NOT NULL
            GROUP BY province, year
        )
        INSERT INTO reporting.maid_final
        SELECT
            m.province,
            m.year,
            m.maid_cases,
            d.total_deaths,
            ROUND((m.maid_cases * 100.0 / d.total_deaths), 2)
        FROM maid_dedup m
        JOIN mortality_dedup d
            ON m.province = d.province
           AND m.year = d.year;

        --------------------------------------------------
        -- VALIDATION CHECK
        --------------------------------------------------
        IF EXISTS (
            SELECT 1 FROM reporting.maid_final
            WHERE percent_of_deaths < 0 OR percent_of_deaths > 100
        )
        BEGIN
            THROW 50001, 'Invalid percentage detected', 1;
        END

        INSERT INTO audit.etl_run_log (status, step, message)
        VALUES ('SUCCESS', 'ETL', 'Pipeline completed');

        COMMIT;

    END TRY
    BEGIN CATCH
        ROLLBACK;

        INSERT INTO audit.etl_run_log (status, step, message)
        VALUES ('FAILED', 'ETL', ERROR_MESSAGE());
    END CATCH
END;
