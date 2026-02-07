{{ 
    config(
        materialized='incremental',
        keys='BOOKING_ID'
    ) 
}}

SELECT
    BOOKING_ID,
    LISTING_ID,
    BOOKING_DATE,
    NIGHTS_BOOKED,
    BOOKING_AMOUNT,
    {{ multiply('NIGHTS_BOOKED','BOOKING_AMOUNT',2) }} AS TOTAL_BOOKING_AMOUNT,
    CLEANING_FEE,
    SERVICE_FEE,
    {{ multiply('NIGHTS_BOOKED','BOOKING_AMOUNT',2) }} + CLEANING_FEE + SERVICE_FEE AS TOTAL_AMOUNT,
    BOOKING_STATUS,
    CREATED_AT
FROM
{{ ref('bronze_bookings') }}
