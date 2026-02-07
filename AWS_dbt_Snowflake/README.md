# Airbnb Data Engineering Project

## 1. Project Overview

This project is a **full-scale, end-to-end data engineering implementation** that demonstrates how raw operational data can be transformed into **analytics-ready, historically accurate datasets** using modern cloud-native tools.

The project simulates a real-world Airbnb-style analytics platform, starting from **raw CSV files stored in Amazon S3**, ingesting them into **Snowflake**, and transforming them using **dbt (data build tool)** following the **Medallion Architecture (Bronze → Silver → Gold)**.

The primary goal of this project is not just to move data, but to **showcase engineering decision-making**:

* Why certain tools were chosen
* Why specific modeling techniques were applied
* How scalability, maintainability, and analytics usability were considered

This repository is intentionally verbose and explicit so that **any data engineer, analytics engineer, or recruiter** can clearly understand *what was done, how it was done, and why it matters*.

---

## 2. High-Level Architecture

### Technology Stack

| Layer            | Technology             | Reason for Choice                                                       |
| ---------------- | ---------------------- | ----------------------------------------------------------------------- |
| Raw Storage      | Amazon S3              | Industry-standard object storage for raw, immutable data                |
| Data Warehouse   | Snowflake              | Separation of compute & storage, strong support for analytics workloads |
| Transformation   | dbt Core               | Version-controlled, SQL-first transformations with lineage              |
| Modeling Pattern | Medallion Architecture | Scalable and production-proven warehouse design                         |
| Dev Environment  | VS Code + Python venv  | Reproducible local development                                          |

### End-to-End Flow

```
CSV Files (S3)
   ↓
Snowflake STAGING schema (raw ingestion)
   ↓
BRONZE schema (incremental raw models)
   ↓
SILVER schema (cleaned + enriched models)
   ↓
GOLD schema (OBT, facts, dimensions, SCD Type 2)
```

This layered approach ensures:

* Raw data is preserved
* Transformations are auditable
* Analytics models are stable and performant

---

## 3. Source Data Design (Snowflake DDL)

Before ingesting any data, destination tables were **explicitly created** in Snowflake.

### Why Explicit DDL?

In real production systems:

* Schemas must be controlled
* Data types must be intentional
* Primary keys should be clearly defined

This avoids schema drift and enforces warehouse governance.

### Tables Created

#### Hosts Table

```sql
CREATE OR REPLACE TABLE HOSTS (
    host_id NUMBER,
    host_name STRING,
    host_since DATE,
    is_superhost BOOLEAN,
    response_rate NUMBER,
    created_at TIMESTAMP,
    PRIMARY KEY (host_id)
);
```

#### Listings Table

```sql
CREATE OR REPLACE TABLE LISTINGS (
    listing_id NUMBER,
    host_id NUMBER,
    property_type STRING,
    room_type STRING,
    city STRING,
    country STRING,
    accommodates NUMBER,
    bedrooms NUMBER,
    bathrooms NUMBER,
    price_per_night NUMBER,
    created_at TIMESTAMP,
    PRIMARY KEY (listing_id)
);
```

#### Bookings Table

```sql
CREATE OR REPLACE TABLE BOOKINGS (
    booking_id STRING,
    listing_id NUMBER,
    booking_date TIMESTAMP,
    nights_booked NUMBER,
    booking_amount NUMBER,
    cleaning_fee NUMBER,
    service_fee NUMBER,
    booking_status STRING,
    created_at TIMESTAMP,
    PRIMARY KEY (booking_id)
);
```

---

## 4. Data Ingestion: Amazon S3 → Snowflake

### CSV File Format

```sql
CREATE OR REPLACE FILE FORMAT csv_format
  TYPE = 'CSV'
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE;
```

#### Why These Settings?

* `SKIP_HEADER`: Prevents headers from being ingested as records
* `ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE`: Makes ingestion resilient to minor upstream changes

### Snowflake Stage

```sql
CREATE OR REPLACE STAGE snowstage
FILE_FORMAT = csv_format
URL='your_s3_bucket_path';
```

Stages abstract external storage and allow Snowflake to treat S3 as a queryable source.

### Secure Access to S3

To allow Snowflake to access S3:

* An IAM user was created
* `AmazonS3FullAccess` policy attached
* Access keys used explicitly in COPY commands

```sql
COPY INTO <your_table_name>
FROM @snowstage
FILES=('your_file_name.csv')
CREDENTIALS=(aws_key_id='your_key', aws_secret_key='your_secret');
```

**Design Note:** This project uses manual `COPY INTO` for clarity. In production, Snowpipe could be introduced for continuous ingestion.

---

## 5. dbt Project Setup

### Environment Preparation

* Created a Python virtual environment
* Installed:

  * `dbt-core`
  * `dbt-snowflake`
* Initialized project using `dbt init`

### Connection Configuration

Important clarifications:

* **User**: Snowflake login username
* **Account**: Snowflake account identifier (not email)

A temporary schema (`dbt_schema`) is created by dbt by default. This was later overridden to enforce clean warehouse organization.

```bash
dbt debug
```

This ensured authentication, warehouse access, and permissions were correctly configured before modeling.

---

## 6. Medallion Architecture Implementation

### Bronze Layer – Raw Incremental Models

**Purpose:** Preserve source fidelity while enabling scalable ingestion.

Key characteristics:

* One model per source table
* Incremental materialization
* Minimal transformation

#### Source Definition (Lineage)

```yml
sources:
  - name: staging
    database: AIRBNB
    schema: staging
    tables:
      - name: listings
      - name: hosts
      - name: bookings
```

Defining sources enables:

* Data lineage tracking
* Source freshness checks
* Clear separation between raw and transformed data

#### Incremental Logic

```sql
{{ config(materialized='incremental') }}

SELECT *
FROM {{ source('staging', 'bookings') }}

{% if is_incremental() %}
WHERE created_at > (
    SELECT COALESCE(MAX(created_at), '1900-01-01') FROM {{ this }}
)
{% endif %}
```

**Why Incremental?**

* Prevents full table reloads
* Reduces compute cost
* Mirrors real streaming/batch hybrid pipelines

### Schema Control via Macro

A custom `generate_schema_name` macro was implemented to prevent dbt from auto-prefixing schemas.

This ensures:

* Clean warehouse layout
* Predictable schema naming
* Alignment with enterprise standards

---

### Silver Layer – Business Transformations

**Purpose:** Convert raw data into analytically meaningful datasets.

Key principles applied:

* Light transformations only
* No loss of grain
* Reusable business logic via macros

#### Reusable Macros

```sql
{% macro multiply(x, y, precision) %}
    round({{ x }} * {{ y }}, {{ precision }})
{% endmacro %}
```

```sql
{% macro tag(col) %}
    CASE 
        WHEN {{ col }} < 100 THEN 'low'
        WHEN {{ col }} < 200 THEN 'medium'
        ELSE 'high'
    END
{% endmacro %}
```

Macros enforce consistency and reduce logic duplication across models.

#### Example Enhancements

* Calculated total booking values
* Parsed host names into first/last
* Categorized response quality
* Tagged listings by price band

Incremental logic with keys enables safe upserts.

---

### Gold Layer – Analytics Models

**Purpose:** Deliver final datasets optimized for BI tools and stakeholders.

#### One Big Table (OBT)

* Built using a **metadata-driven Jinja configuration**
* Centralizes joins
* Simplifies downstream analytics

This approach reduces SQL repetition and improves maintainability.

#### Dimensions & Slowly Changing Dimensions (SCD Type 2)

* Dimensions defined as **ephemeral models** to avoid unnecessary persistence
* dbt snapshots used to track historical changes

```yml
snapshots:
  - name: dim_hosts
    relation: ref('hosts')
    config:
      schema: gold
      database: AIRBNB
      unique_key: HOST_ID
      strategy: timestamp
      updated_at: HOST_CREATED_AT
      dbt_valid_to_current: "to_date('9999-12-31')"
```

**Why SCD Type 2?**

* Preserves historical truth
* Enables accurate trend analysis
* Reflects enterprise data warehouse standards

---

## 7. Fact Table Design

The fact table consolidates measurable metrics:

* Booking amounts
* Fees
* Capacity metrics

It joins cleanly to dimension tables, forming a classic star-schema analytics layer.

---

## 8. How to Run the Project

```bash
dbt run --select models/bronze
dbt run --select models/silver
dbt run --select models/gold
dbt snapshot
```

---

## 9. Key Skills Demonstrated

* Cloud data ingestion (AWS S3 → Snowflake)
* Incremental data modeling
* dbt macros & Jinja templating
* Medallion architecture
* Metadata-driven SQL
* SCD Type 2 implementation
* Analytics-ready fact & dimension modeling

---

## 10. Final Thoughts

This project was designed to closely mirror **real production data engineering workflows**. Every architectural and modeling choice was intentional, focusing on scalability, clarity, and analytical usefulness.

---

**Author:** Eseosa Isidahomhen
**Focus:** Data Engneering | Analytics Engineering | Cloud Data Platforms
