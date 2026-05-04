/* =========================================================
   Tasks: writing queries using window functions
   ========================================================= */


/* =========================================================
   TASK 1
   Top 5 customers per sales channel
   ========================================================= */

-- I first aggregate sales per customer and channel because ranking should be based
-- on each customer's total sales, not individual purchase rows.
-- I use ROW_NUMBER() instead of DENSE_RANK() because it was clarified that
-- "just the first 5 customers" is acceptable, so this returns exactly 5 customers
-- per channel, even if there are ties.
-- SUM() OVER is used to calculate total sales per channel without using a window frame.

WITH customer_channel_sales AS (
    SELECT
        channels.channel_desc,
        customers.cust_id,
        customers.cust_last_name,
        customers.cust_first_name,
        SUM(sales.amount_sold) AS total_sales
    FROM sh.sales AS sales
    INNER JOIN sh.customers AS customers
        ON sales.cust_id = customers.cust_id
    INNER JOIN sh.channels AS channels
        ON sales.channel_id = channels.channel_id
    GROUP BY
        channels.channel_desc,
        customers.cust_id,
        customers.cust_last_name,
        customers.cust_first_name
),

ranked_customer_channel_sales AS (
    SELECT
        customer_channel_sales.channel_desc,
        customer_channel_sales.cust_id,
        customer_channel_sales.cust_last_name,
        customer_channel_sales.cust_first_name,
        customer_channel_sales.total_sales,

        SUM(customer_channel_sales.total_sales) OVER (
            PARTITION BY customer_channel_sales.channel_desc
        ) AS channel_total_sales,

        ROW_NUMBER() OVER (
            PARTITION BY customer_channel_sales.channel_desc
            ORDER BY customer_channel_sales.total_sales DESC
        ) AS customer_position
    FROM customer_channel_sales
)

SELECT
    ranked_customer_channel_sales.channel_desc,
    UPPER(ranked_customer_channel_sales.cust_last_name) AS cust_last_name,
    UPPER(ranked_customer_channel_sales.cust_first_name) AS cust_first_name,
    TO_CHAR(ranked_customer_channel_sales.total_sales, 'FM999999999.00') AS amount_sold,
    TO_CHAR(
        ranked_customer_channel_sales.total_sales
        / ranked_customer_channel_sales.channel_total_sales * 100,
        'FM999999999.0000'
    ) || ' %' AS sales_percentage
FROM ranked_customer_channel_sales
WHERE ranked_customer_channel_sales.customer_position <= 5
ORDER BY
    ranked_customer_channel_sales.channel_desc,
    ranked_customer_channel_sales.total_sales DESC;


/* =========================================================
   TASK 2
   Photo category product sales in Asia for year 2000
   Crosstab with quarter columns
   ========================================================= */

-- I use CROSSTAB here 
-- Quarter columns q1, q2, q3, and q4 are included because it was also clarified
-- that quarter columns should be present in the result.
-- The source query returns product name, quarter, and sales amount.
-- The category query fixes the order of quarters, so q1, q2, q3, and q4 are filled correctly.
-- COALESCE is used in YEAR_SUM in case a product has no sales in one of the quarters.

-- I add this to ensure crosstab works in case extension is not enabled
CREATE EXTENSION IF NOT EXISTS tablefunc;

SELECT
    crosstab_result.product_name,
    TO_CHAR(COALESCE(crosstab_result.q1, 0), 'FM999999999.00') AS q1,
    TO_CHAR(COALESCE(crosstab_result.q2, 0), 'FM999999999.00') AS q2,
    TO_CHAR(COALESCE(crosstab_result.q3, 0), 'FM999999999.00') AS q3,
    TO_CHAR(COALESCE(crosstab_result.q4, 0), 'FM999999999.00') AS q4,
    TO_CHAR(
        COALESCE(crosstab_result.q1, 0)
        + COALESCE(crosstab_result.q2, 0)
        + COALESCE(crosstab_result.q3, 0)
        + COALESCE(crosstab_result.q4, 0),
        'FM999999999.00'
    ) AS year_sum
FROM crosstab(
    $$
    SELECT
        products.prod_name AS product_name,
        'q' || times.calendar_quarter_number AS quarter_name,
        SUM(sales.amount_sold) AS quarter_sales
    FROM sh.sales AS sales
    INNER JOIN sh.products AS products
        ON sales.prod_id = products.prod_id
    INNER JOIN sh.times AS times
        ON sales.time_id = times.time_id
    INNER JOIN sh.customers AS customers
        ON sales.cust_id = customers.cust_id
    INNER JOIN sh.countries AS countries
        ON customers.country_id = countries.country_id
    WHERE
        LOWER(products.prod_category) = 'photo'
        AND LOWER(countries.country_region) = 'asia'
        AND times.calendar_year = 2000
    GROUP BY
        products.prod_name,
        times.calendar_quarter_number
    ORDER BY
        products.prod_name,
        times.calendar_quarter_number
    $$,
    $$
    SELECT 'q1'
    UNION ALL
    SELECT 'q2'
    UNION ALL
    SELECT 'q3'
    UNION ALL
    SELECT 'q4'
    $$
) AS crosstab_result (
    product_name TEXT,
    q1 NUMERIC,
    q2 NUMERIC,
    q3 NUMERIC,
    q4 NUMERIC
)
ORDER BY
    COALESCE(crosstab_result.q1, 0)
    + COALESCE(crosstab_result.q2, 0)
    + COALESCE(crosstab_result.q3, 0)
    + COALESCE(crosstab_result.q4, 0) DESC;
   
/* =========================================================
   TASK 3
   Customers who are in Top 300 for 1998, 1999, and 2001
   within the same sales channel
   ========================================================= */

-- I calculate according as in the teams chat there was clarified that Top 300 must be calculated separately for each channel
-- and separately for each year: 1998, 1999, and 2001.
-- Also it was clarified that the final report should include only customers who were
-- in the Top 300 in all three years within the same channel.
-- Therefore:
-- 1. I calculate yearly sales per customer and channel.
-- 2. I rank customers inside each channel and year.
-- 3. I keep only Top 300 customers for each channel/year.
-- 4. I keep only customers that appear in all three years in the same channel.
-- ROW_NUMBER() is used to return exactly Top 300 rows per channel/year.



WITH customer_year_channel_sales AS (
    SELECT
        channels.channel_desc,
        customers.cust_id,
        customers.cust_last_name,
        customers.cust_first_name,
        times.calendar_year,
        SUM(sales.amount_sold) AS total_sales
    FROM sh.sales AS sales
    INNER JOIN sh.customers AS customers
        ON sales.cust_id = customers.cust_id
    INNER JOIN sh.channels AS channels
        ON sales.channel_id = channels.channel_id
    INNER JOIN sh.times AS times
        ON sales.time_id = times.time_id
    WHERE times.calendar_year IN (1998, 1999, 2001)
    GROUP BY
        channels.channel_desc,
        customers.cust_id,
        customers.cust_last_name,
        customers.cust_first_name,
        times.calendar_year
),

ranked_customer_year_channel_sales AS (
    SELECT
        customer_year_channel_sales.*,
        ROW_NUMBER() OVER (
            PARTITION BY
                customer_year_channel_sales.channel_desc,
                customer_year_channel_sales.calendar_year
            ORDER BY customer_year_channel_sales.total_sales DESC
        ) AS customer_position
    FROM customer_year_channel_sales
),

top_300_customers AS (
    SELECT *
    FROM ranked_customer_year_channel_sales
    WHERE customer_position <= 300
),

customers_in_all_three_years AS (
    SELECT
        top_300_customers.channel_desc,
        top_300_customers.cust_id
    FROM top_300_customers
    GROUP BY
        top_300_customers.channel_desc,
        top_300_customers.cust_id
    HAVING COUNT(DISTINCT top_300_customers.calendar_year) = 3
)
-- I sum the three yearly sales in the final result because after checking that
-- the customer is in the Top 300 for all three years, the report should show
-- one total amount per customer and channel, like in the sample format.
SELECT
    top_300_customers.channel_desc,
    top_300_customers.cust_id,
    UPPER(top_300_customers.cust_last_name) AS cust_last_name,
    UPPER(top_300_customers.cust_first_name) AS cust_first_name,
    TO_CHAR(SUM(top_300_customers.total_sales), 'FM999999999.00') AS amount_sold
FROM top_300_customers
INNER JOIN customers_in_all_three_years
    ON top_300_customers.channel_desc = customers_in_all_three_years.channel_desc
    AND top_300_customers.cust_id = customers_in_all_three_years.cust_id
GROUP BY
    top_300_customers.channel_desc,
    top_300_customers.cust_id,
    top_300_customers.cust_last_name,
    top_300_customers.cust_first_name
ORDER BY
    top_300_customers.channel_desc,
    top_300_customers.cust_last_name,
    top_300_customers.cust_first_name;

/* =========================================================
   TASK 4
   Sales report for Jan, Feb, Mar 2000
   Europe and Americas by product category
   ========================================================= */

-- I use conditional aggregation because the task needs two separate regional columns:
-- Americas sales and Europe sales.
-- This is simpler and clearer than crosstab here because there are only two fixed regions.
-- LOWER() is applied only to the text column country_region.
-- The result is grouped by month and product category and ordered alphabetically
-- as required.

SELECT
    times.calendar_month_desc,
    products.prod_category,

    TO_CHAR(
        COALESCE(
            SUM(
                CASE
                    WHEN LOWER(countries.country_region) = 'americas'
                    THEN sales.amount_sold
                END
            ),
            0
        ),
        'FM999999999.00'
    ) AS americas_sales,

    TO_CHAR(
        COALESCE(
            SUM(
                CASE
                    WHEN LOWER(countries.country_region) = 'europe'
                    THEN sales.amount_sold
                END
            ),
            0
        ),
        'FM999999999.00'
    ) AS europe_sales

FROM sh.sales AS sales
INNER JOIN sh.products AS products
    ON sales.prod_id = products.prod_id
INNER JOIN sh.times AS times
    ON sales.time_id = times.time_id
INNER JOIN sh.customers AS customers
    ON sales.cust_id = customers.cust_id
INNER JOIN sh.countries AS countries
    ON customers.country_id = countries.country_id
WHERE
    times.calendar_year = 2000
    AND times.calendar_month_number IN (1, 2, 3)
    AND LOWER(countries.country_region) IN ('europe', 'americas')
GROUP BY
    times.calendar_month_desc,
    products.prod_category
ORDER BY
    times.calendar_month_desc,
    products.prod_category;