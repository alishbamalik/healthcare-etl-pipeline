# Healthcare ETL Pipeline

MAiD Data ETL & Analysis Pipeline

-------------------------------------
Overview
-------------------------------------

This project demonstrates an end-to-end ETL (Extract, Transform, Load) pipeline built to integrate and prepare healthcare-style datasets for analysis. The goal was to simulate a real-world scenario where raw data is inconsistent, incomplete, and not directly usable, and must be processed into a reliable format for reporting and analytics. The final output is a clean dataset used for statistical analysis in R.

-------------------------------------
Architecture
-------------------------------------

Raw Data → SQL ETL Pipeline → Clean Reporting Table → RMarkdown Analysis → PDF Report

-------------------------------------
Data Sources
-------------------------------------

Two synthetic datasets were created to simulate real healthcare reporting systems:

1. Mortality Records
- Contains total deaths by province and year
- Includes inconsistencies such as:
    - Mixed data types (year as text and numeric)
    - Missing values
    - Inconsistent province naming

2. MAiD Procedure Records
- Contains counts of MAiD cases
- Includes:
  - Duplicate entries
  - Non-approved records
  - Different province naming conventions

-------------------------------------
ETL Pipeline (SQL)
-------------------------------------

The ETL pipeline is implemented in SQL and structured into three layers:

1. Extract (Staging Layer)
- Raw CSV files are loaded into staging tables using bulk operations
- Data is stored as-is to preserve original structure
  
3. Transform (Cleaning & Integration)
- Standardized province names (e.g., Ontario → ON)
- Converted data types (e.g., year → integer)
- Filtered invalid records (e.g., non-approved MAiD cases)
- Removed duplicates using aggregation
- Applied validation rules to ensure data quality
- Captured invalid records in error tables
  
5. Load (Reporting Layer)
- Cleaned datasets are joined on province and year
- Final metric is derived: percent_of_deaths = (maid_cases / total_deaths) * 100
- Output is stored in a structured reporting table with one record per province per year

------------------------------------- 
Data Validation
-------------------------------------

To ensure data integrity, the pipeline includes:
- Null checks
- Duplicate detection
- Range validation (percent values between 0–100)
- Error logging for invalid records

-------------------------------------
Pipeline Execution
-------------------------------------

The ETL process is encapsulated in a stored procedure:
- Supports repeatable execution
- Uses transaction handling for reliability
- Logs execution status (success/failure)

-------------------------------------
Analysis (RMarkdown)
-------------------------------------

The cleaned dataset is exported and used in R for analysis.

Key Steps:
- Load processed dataset
- Perform statistical analysis (trend modeling)
- Generate visualizations
- Produce a PDF report

This separation ensures:
- SQL handles data preparation
- R handles analysis and reporting

-------------------------------------
Design Decisions
-------------------------------------

- Layered architecture (staging → clean → reporting) for maintainability
- Standardization of categorical data to enable reliable joins
- Validation and error capture to improve data quality
- Separation of ETL and analytics for scalability and reuse

-------------------------------------
Challenges
-------------------------------------

- Inconsistent province naming across datasets
- Missing and incomplete data
- Duplicate records requiring aggregation
- Ensuring accurate joins between independent data sources

-------------------------------------
Tools & Technologies
-------------------------------------

- SQL (ETL pipeline, data transformation)
- R (data analysis)
- RMarkdown (report generation)

-------------------------------------
Outcome
-------------------------------------

This project demonstrates the ability to:

- Build a structured ETL pipeline
- Clean and integrate multiple datasets
- Ensure data quality through validation
- Prepare data for downstream analytics
- Separate data engineering and analysis workflows

-------------------------------------
Future Improvements
-------------------------------------

- Implement incremental data loading
- Add indexing for performance optimization
- Automate scheduling of ETL pipeline
- Expand validation and monitoring

