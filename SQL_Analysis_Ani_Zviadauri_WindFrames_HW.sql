-- Tasks: writing queries using window frames

-- Task 1
-- I first summarize sales by region, year, and channel.
-- Then I calculate how much each channel contributes to the full yearly sales of its region.
-- After that, I compare each channel percentage with the same channel from the previous year.
-- I include year 1998 only to calculate previous period for 1999.
-- Without this, LAG would return NULL for 1999.


WITH channel_sales AS (
    SELECT
        countries.country_region,
        times.calendar_year,
        channels.channel_desc,
        SUM(sales.amount_sold) AS amount_sold
    FROM sh.sales AS sales
    INNER JOIN sh.times AS times
        ON sales.time_id = times.time_id
    INNER JOIN sh.channels AS channels
        ON sales.channel_id = channels.channel_id
    INNER JOIN sh.customers AS customers
        ON sales.cust_id = customers.cust_id
    INNER JOIN sh.countries AS countries
        ON customers.country_id = countries.country_id
    WHERE times.calendar_year BETWEEN 1998 AND 2001
        -- I include 1998 only so I can calculate previous period values for 1999.
        AND UPPER(countries.country_region) IN ('AMERICAS', 'ASIA', 'EUROPE')
    GROUP BY
        countries.country_region,
        times.calendar_year,
        channels.channel_desc
),
channel_percentages AS (
    SELECT
        channel_sales.country_region,
        channel_sales.calendar_year,
        channel_sales.channel_desc,
        channel_sales.amount_sold,
        -- I calculate the percent of each channel inside the same region and year.
        ROUND(
            channel_sales.amount_sold
            / SUM(channel_sales.amount_sold) OVER (
                PARTITION BY channel_sales.country_region, channel_sales.calendar_year
            ) * 100,
            2
        ) AS pct_by_channels
    FROM channel_sales
),
previous_year_comparison AS (
    SELECT
        channel_percentages.country_region,
        channel_percentages.calendar_year,
        channel_percentages.channel_desc,
        channel_percentages.amount_sold,
        channel_percentages.pct_by_channels,
        -- I compare each channel with the same channel from the previous year.
        LAG(channel_percentages.pct_by_channels) OVER (
            PARTITION BY channel_percentages.country_region, channel_percentages.channel_desc
            ORDER BY channel_percentages.calendar_year
        ) AS pct_previous_period
    FROM channel_percentages
)
SELECT
    previous_year_comparison.country_region,
    previous_year_comparison.calendar_year,
    previous_year_comparison.channel_desc,
    previous_year_comparison.amount_sold,
    previous_year_comparison.pct_by_channels AS "% BY CHANNELS",
    previous_year_comparison.pct_previous_period AS "% PREVIOUS PERIOD",
    previous_year_comparison.pct_by_channels
        - previous_year_comparison.pct_previous_period AS "% DIFF"
FROM previous_year_comparison
WHERE previous_year_comparison.calendar_year BETWEEN 1999 AND 2001
ORDER BY
    previous_year_comparison.country_region,
    previous_year_comparison.calendar_year,
    previous_year_comparison.channel_desc;

-- Task 2
-- I first summarize sales by date because the sales table has many rows for one day.
-- Then I calculate the running sales amount inside each calendar week.
-- For the centered average, I calculate the average around each day.
-- I also include extra dates before week 49 and after week 51, because the first Monday and the last Friday need nearby weekend days.
-- Note:
-- My result for the first Monday (week 49) can differ from the sample.
-- I follow the instructions and include weekend data (Saturday and Sunday),
-- while the sample appears to calculate the average using only Monday and Tuesday.

WITH daily_sales AS (
    SELECT
        times.calendar_week_number,
        times.time_id,
        times.day_name,
        SUM(sales.amount_sold) AS sales
    FROM sh.sales AS sales
    INNER JOIN sh.times AS times
        ON sales.time_id = times.time_id
    -- I include 1999-12-04 and 1999-12-05 so Monday of week 49 can use the previous weekend.
    -- I include 1999-12-27 so the last days of week 51 can still calculate averages correctly.
    WHERE times.time_id BETWEEN DATE '1999-12-04' AND DATE '1999-12-27'
    GROUP BY
        times.calendar_week_number,
        times.time_id,
        times.day_name
),
weekly_report_days AS (
    SELECT
        daily_sales.calendar_week_number,
        daily_sales.time_id,
        daily_sales.day_name,
        daily_sales.sales,
        -- I restart this cumulative sum for each week.
        SUM(daily_sales.sales) OVER (
            PARTITION BY daily_sales.calendar_week_number
            ORDER BY daily_sales.time_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cum_sum,
        -- I use RANGE because I want to calculate by real date distance.
        -- This means one day before and one day after, not just the previous and next row.
        AVG(daily_sales.sales) OVER (
            ORDER BY daily_sales.time_id
            RANGE BETWEEN INTERVAL '1 day' PRECEDING AND INTERVAL '1 day' FOLLOWING
        ) AS normal_centered_avg,
        -- For Monday, I include Saturday, Sunday, Monday, and Tuesday.
        AVG(daily_sales.sales) OVER (
            ORDER BY daily_sales.time_id
            RANGE BETWEEN INTERVAL '2 days' PRECEDING AND INTERVAL '1 day' FOLLOWING
        ) AS monday_centered_avg,
        -- For Friday, I include Thursday, Friday, Saturday, and Sunday.
        AVG(daily_sales.sales) OVER (
            ORDER BY daily_sales.time_id
            RANGE BETWEEN INTERVAL '1 day' PRECEDING AND INTERVAL '2 days' FOLLOWING
        ) AS friday_centered_avg
    FROM daily_sales
)
SELECT
    weekly_report_days.calendar_week_number,
    weekly_report_days.time_id,
    weekly_report_days.day_name,
    ROUND(weekly_report_days.sales, 2) AS sales,
    ROUND(weekly_report_days.cum_sum, 2) AS cum_sum,
    -- I use special averages only for Monday and Friday because the task gives special rules for these days.
    -- For all other days, I use the normal centered average.
    ROUND(
        CASE
            WHEN UPPER(weekly_report_days.day_name) = 'MONDAY'
                THEN weekly_report_days.monday_centered_avg
            WHEN UPPER(weekly_report_days.day_name) = 'FRIDAY'
                THEN weekly_report_days.friday_centered_avg
            ELSE weekly_report_days.normal_centered_avg
        END,
        2
    ) AS centered_3_day_avg
FROM weekly_report_days
WHERE weekly_report_days.calendar_week_number IN (49, 50, 51)
    -- I show only weeks 49, 50, and 51 in the final result.
    -- The extra dates are used only for calculation, not for display.
    AND weekly_report_days.time_id BETWEEN DATE '1999-12-06' AND DATE '1999-12-26'
ORDER BY
    weekly_report_days.calendar_week_number,
    weekly_report_days.time_id;

-- Task 3.1 - ROWS frame
-- I use ROWS because I want to count exact rows.
-- This example shows the current day plus the previous two daily rows.


WITH daily_sales AS (
    SELECT
        times.time_id,
        times.day_name,
        SUM(sales.amount_sold) AS sales
    FROM sh.sales AS sales
    INNER JOIN sh.times AS times
        ON sales.time_id = times.time_id
    WHERE times.time_id BETWEEN DATE '2000-01-01' AND DATE '2000-01-10'
    GROUP BY
        times.time_id,
        times.day_name
)
SELECT
    daily_sales.time_id,
    daily_sales.day_name,
    daily_sales.sales,
    SUM(daily_sales.sales) OVER (
        ORDER BY daily_sales.time_id
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS three_row_running_sales
FROM daily_sales
ORDER BY daily_sales.time_id;



-- Task 3.2 - RANGE frame
-- I use RANGE because I want to use the real date interval around each row.
-- This is helpful when I care about one day before and one day after, not just nearby rows.


WITH daily_sales AS (
    SELECT
        times.time_id,
        times.day_name,
        SUM(sales.amount_sold) AS sales
    FROM sh.sales AS sales
    INNER JOIN sh.times AS times
        ON sales.time_id = times.time_id
    WHERE times.time_id BETWEEN DATE '2000-01-01' AND DATE '2000-01-10'
    GROUP BY
        times.time_id,
        times.day_name
)
SELECT
    daily_sales.time_id,
    daily_sales.day_name,
    daily_sales.sales,
    AVG(daily_sales.sales) OVER (
        ORDER BY daily_sales.time_id
        RANGE BETWEEN INTERVAL '1 day' PRECEDING AND INTERVAL '1 day' FOLLOWING
    ) AS date_range_centered_average
FROM daily_sales
ORDER BY daily_sales.time_id;



-- Task 3.3 - GROUPS frame
-- I use GROUPS because rows with the same calendar_year are treated as one peer group.
-- This lets me calculate sales for the current year group and the previous year group together.


WITH channel_sales AS (
    SELECT
        times.calendar_year,
        channels.channel_desc,
        SUM(sales.amount_sold) AS amount_sold
    FROM sh.sales AS sales
    INNER JOIN sh.times AS times
        ON sales.time_id = times.time_id
    INNER JOIN sh.channels AS channels
        ON sales.channel_id = channels.channel_id
    WHERE times.calendar_year BETWEEN 1999 AND 2001
    GROUP BY
        times.calendar_year,
        channels.channel_desc
)
SELECT
    channel_sales.calendar_year,
    channel_sales.channel_desc,
    channel_sales.amount_sold,
    SUM(channel_sales.amount_sold) OVER (
        ORDER BY channel_sales.calendar_year
        GROUPS BETWEEN 1 PRECEDING AND CURRENT ROW
    ) AS current_and_previous_year_sales
FROM channel_sales
ORDER BY
    channel_sales.calendar_year,
    channel_sales.channel_desc;



