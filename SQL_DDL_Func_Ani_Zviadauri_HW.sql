-- ============================================================
-- Tasks 1-5
-- ============================================================
 
CREATE SCHEMA IF NOT EXISTS core;
 
 
-- ============================================================
-- TASK 1. VIEW
-- sales_revenue_by_category_qtr
-- ============================================================
 
-- This view shows how much revenue each film category brought in
-- during the current quarter of the current year.
--
-- How the current quarter is determined:
--   date_trunc('quarter', CURRENT_DATE) gives the first day of the
--   quarter we are in right now. Adding 3 months gives the first day
--   of the next quarter. The filter is always:
--     payment_date >= start of this quarter
--     payment_date <  start of next quarter
--   This shifts automatically the moment a new quarter begins —
--   no manual update is ever needed.
--
-- Why the year does not need a separate filter:
--   The quarter range already pins us to a specific 3-month window
--   inside a specific year, so an extra EXTRACT(YEAR ...) check
--   would be redundant.
--
-- Why only categories with sales appear:
--   We start from actual payment rows and join outward to category.
--   If a category had no payments in this period, there are simply
--   no rows to join, so it never shows up in the result.
--
-- Why HAVING SUM(amount) > 0 is still here:
--   It acts as a safety net in case a payment row with a zero amount
--   somehow slips in. Such a category would appear in the GROUP BY
--   but should not count as having had real sales.
--
-- Note on the sample data:
--   The default dvdrental database contains payments from 2005-2007.
--   Because the current date is well past that, this view returns
--   0 rows today. That is expected — the quarter filter is correct,
--   the data just predates it. The test query below shows the same
--   logic working against a quarter that actually has data.
--
-- Data that should NOT appear in a correct result:
--   - Categories that had sales last quarter but not this one
--   - Categories that have films but zero payments this quarter
--   - Any category whose revenue sums to exactly zero
 
CREATE OR REPLACE VIEW core.sales_revenue_by_category_qtr AS
SELECT
    upper(category.name)             AS category_name,
    round(SUM(payment.amount), 2)    AS total_sales_revenue
FROM public.payment
JOIN public.rental
    ON rental.rental_id         = payment.rental_id
JOIN public.inventory
    ON inventory.inventory_id   = rental.inventory_id
JOIN public.film_category
    ON film_category.film_id    = inventory.film_id
JOIN public.category
    ON category.category_id     = film_category.category_id
WHERE payment.payment_date >= date_trunc('quarter', CURRENT_DATE)
  AND payment.payment_date <  date_trunc('quarter', CURRENT_DATE) + INTERVAL '3 months'
GROUP BY category.name
HAVING SUM(payment.amount) > 0
ORDER BY total_sales_revenue DESC, category.name;
 
 
-- TEST 1 (valid — Q1 2007 has real payment data in the sample db,
-- so this should return all categories that earned revenue that quarter):
SELECT
    upper(category.name)             AS category_name,
    round(SUM(payment.amount), 2)    AS total_sales_revenue
FROM public.payment
JOIN public.rental
    ON rental.rental_id         = payment.rental_id
JOIN public.inventory
    ON inventory.inventory_id   = rental.inventory_id
JOIN public.film_category
    ON film_category.film_id    = inventory.film_id
JOIN public.category
    ON category.category_id     = film_category.category_id
WHERE payment.payment_date >= DATE '2007-01-01'
  AND payment.payment_date <  DATE '2007-04-01'
GROUP BY category.name
HAVING SUM(payment.amount) > 0
ORDER BY total_sales_revenue DESC, category.name;
 
-- TEST 2 (edge — today's quarter has no data in the sample db,
-- so the view should return 0 rows):
SELECT * FROM core.sales_revenue_by_category_qtr;

-- ============================================================
-- TASK 2. QUERY LANGUAGE FUNCTION
-- get_sales_revenue_by_category_qtr
-- ============================================================
 
-- This function does the same thing as the view above, but lets you
-- pass in any date and it will use that date's quarter instead of
-- always using today's quarter.
--
-- Why a parameter is needed:
--   The view is always locked to the real current quarter, so you
--   cannot use it to look back at previous quarters or test against
--   historical data. The function makes the same logic reusable for
--   any point in time.
--
-- Why the parameter is a DATE and not a quarter number:
--   If the parameter were an integer representing a quarter (1 to 4),
--   a caller could pass 5, 0, or -1 and the function would need extra
--   validation. A DATE is always unambiguous — date_trunc('quarter', ...)
--   handles all the math, and PostgreSQL rejects malformed date strings
--   at the call site before the function body even runs.
--
-- What happens if an invalid date string is passed:
--   PostgreSQL rejects it before the function body even runs.
--   For example, '2007-13-01' fails at the call site with a cast
--   error — the function never sees it.
--
-- What happens if NULL is passed:
--   RAISE EXCEPTION fires immediately with a clear message.
--   This is why the function uses plpgsql instead of plain SQL —
--   LANGUAGE SQL functions cannot raise exceptions.
--
-- What happens if no data exists for the requested quarter:
--   The function returns 0 rows. That is the correct answer — an
--   empty result means nothing was sold in that period.
 
CREATE OR REPLACE FUNCTION core.get_sales_revenue_by_category_qtr(
    p_reference_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    category_name       TEXT,
    total_sales_revenue NUMERIC(10, 2)
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF p_reference_date IS NULL THEN
        RAISE EXCEPTION 'Reference date cannot be NULL — pass a valid date to identify the quarter';
    END IF;
 
    RETURN QUERY
    SELECT
        upper(category.name),
        round(SUM(payment.amount), 2)::numeric(10, 2) AS total_sales_revenue
    FROM public.payment
    JOIN public.rental
        ON rental.rental_id         = payment.rental_id
    JOIN public.inventory
        ON inventory.inventory_id   = rental.inventory_id
    JOIN public.film_category
        ON film_category.film_id    = inventory.film_id
    JOIN public.category
        ON category.category_id     = film_category.category_id
    WHERE payment.payment_date >= date_trunc('quarter', p_reference_date)
      AND payment.payment_date <  date_trunc('quarter', p_reference_date) + INTERVAL '3 months'
    GROUP BY category.name
    HAVING SUM(payment.amount) > 0
    ORDER BY total_sales_revenue DESC, category.name;
END;
$$;
 
 
-- TEST 1 (valid — a date in Q1 2007, which has real data in the sample db):
SELECT * FROM core.get_sales_revenue_by_category_qtr(DATE '2007-02-15');
 
-- TEST 2 (edge — NULL input, should raise exception with a clear message):
SELECT * FROM core.get_sales_revenue_by_category_qtr(NULL);
 
-- TEST 3 (edge — a quarter with no data, should return 0 rows without error):
SELECT * FROM core.get_sales_revenue_by_category_qtr(DATE '2020-06-01');
 
 
-- ============================================================
-- TASK 3. PROCEDURE LANGUAGE FUNCTION
-- most_popular_films_by_countries
-- ============================================================
 
-- Returns the single most popular film for each country in the input list.
--
-- How "most popular" is defined:
--   We count how many times each film was rented by customers from
--   that country. The film with the highest rental count wins.
--   Ties are broken first by total revenue (higher is better), then
--   alphabetically by title so the result is always deterministic.
--
-- How countries with no rental data are handled:
--   The country still appears in the result. All film-related columns
--   show "-" so the caller knows the country was recognized but had
--   no rental activity to rank.
--
-- What happens with bad input:
--   A NULL array or a completely empty array raises an exception
--   immediately. Blank strings inside the array are silently skipped.
--   If every entry is blank after cleaning, a second exception fires.
--
-- Why a counter variable is used instead of IF NOT FOUND:
--   In plpgsql, the FOUND variable is only set by SELECT INTO and
--   PERFORM — not by RETURN QUERY. Using a COUNT before the main
--   query is the reliable way to detect an empty cleaned input list.
 
CREATE OR REPLACE FUNCTION core.most_popular_films_by_countries(
    p_countries TEXT[]
)
RETURNS TABLE (
    country      TEXT,
    film         TEXT,
    rating       TEXT,
    language     TEXT,
    length       TEXT,
    release_year TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_valid_count INT;
BEGIN
    IF p_countries IS NULL OR array_length(p_countries, 1) IS NULL THEN
        RAISE EXCEPTION 'Country list cannot be NULL or empty';
    END IF;
 
    SELECT COUNT(*)
    INTO v_valid_count
    FROM unnest(p_countries) AS input_entry
    WHERE BTRIM(input_entry) <> '';
 
    IF v_valid_count = 0 THEN
        RAISE EXCEPTION 'No valid country names found in the input — all entries were blank';
    END IF;
 
    RETURN QUERY
    WITH
    clean_countries AS (
        SELECT DISTINCT lower(BTRIM(input_entry)) AS normalized_name
        FROM unnest(p_countries) AS input_entry
        WHERE BTRIM(input_entry) <> ''
    ),
    ranked_films AS (
        SELECT
            lower(country.country)           AS normalized_country,
            film.title                       AS film_title,
            film.rating::text                AS film_rating,
            language.name                    AS language_name,
            film.length                      AS film_length,
            film.release_year::text          AS film_release_year,
            ROW_NUMBER() OVER (
                PARTITION BY lower(country.country)
                ORDER BY
                    COUNT(rental.rental_id)          DESC,
                    COALESCE(SUM(payment.amount), 0) DESC,
                    upper(film.title)                ASC
            ) AS position
        FROM clean_countries
        JOIN public.country
            ON lower(country.country)       = clean_countries.normalized_name
        JOIN public.city
            ON city.country_id              = country.country_id
        JOIN public.address
            ON address.city_id              = city.city_id
        JOIN public.customer
            ON customer.address_id          = address.address_id
        JOIN public.rental
            ON rental.customer_id           = customer.customer_id
        JOIN public.inventory
            ON inventory.inventory_id       = rental.inventory_id
        JOIN public.film
            ON film.film_id                 = inventory.film_id
        JOIN public.language
            ON language.language_id         = film.language_id
        LEFT JOIN public.payment
            ON payment.rental_id            = rental.rental_id
        GROUP BY
            lower(country.country),
            film.title,
            film.rating,
            language.name,
            film.length,
            film.release_year
    )
    SELECT
        initcap(clean_countries.normalized_name),
        COALESCE(ranked_films.film_title,         '-'),
        COALESCE(upper(ranked_films.film_rating), '-'),
        COALESCE(initcap(ranked_films.language_name), '-'),
        COALESCE(ranked_films.film_length::text,  '-'),
        COALESCE(ranked_films.film_release_year,  '-')
    FROM clean_countries
    LEFT JOIN ranked_films
           ON ranked_films.normalized_country = clean_countries.normalized_name
          AND ranked_films.position = 1
    ORDER BY clean_countries.normalized_name;
 
END;
$$;
 
 
-- TEST 1 (valid — all three countries exist in the sample db):
SELECT * FROM core.most_popular_films_by_countries(
    ARRAY['Afghanistan', 'Brazil', 'United States']
);
 
-- TEST 2 (edge — all blank strings, should raise exception):
SELECT * FROM core.most_popular_films_by_countries(ARRAY['', '   ']);
 
-- TEST 3 (edge — NULL input, should raise exception):
SELECT * FROM core.most_popular_films_by_countries(NULL);
 
-- TEST 4 (edge — country not in the db, should return a row with "-" for film columns):
SELECT * FROM core.most_popular_films_by_countries(ARRAY['Atlantis']);
 
 
-- ============================================================
-- TASK 4. PROCEDURE LANGUAGE FUNCTION
-- films_in_stock_by_title
-- ============================================================
 
-- Returns all films currently in stock whose title matches the given
-- search pattern. Use % as a wildcard, e.g. '%love%' finds any title
-- containing "love".
--
-- How pattern matching works:
--   The search uses LIKE. Both the film title and the pattern are
--   passed through lower() before comparing, so the match is always
--   case-insensitive. '%Love%' and '%love%' give the same results.
--
-- How "in stock" is determined:
--   We reuse the existing inventory_in_stock() function from the
--   dvdrental schema. It returns true when a copy has no open rental
--   (no row where return_date IS NULL for that inventory copy).
--
-- Performance considerations:
--   A leading % prevents the database from using a standard B-tree
--   index on title. On large tables this can be slow. We reduce
--   unnecessary work by:
--     1) Finding matching titles first, before touching any other table
--     2) Using EXISTS to check stock — it stops as soon as one
--        available copy is found, avoiding a full inventory scan
--     3) Fetching rental and customer data only for films that passed
--        both filters above
--
-- What happens when nothing matches:
--   FOUND is not set by RETURN QUERY in plpgsql, so we use a counter
--   variable. If the count is zero we return a single informational
--   row instead of silently returning nothing.
--
-- What happens with NULL or blank input:
--   An exception is raised immediately, before any query runs.
 
CREATE OR REPLACE FUNCTION core.films_in_stock_by_title(
    p_title_pattern TEXT DEFAULT '%'
)
RETURNS TABLE (
    row_num       BIGINT,
    film_title    TEXT,
    language      TEXT,
    customer_name TEXT,
    rental_date   TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_match_count BIGINT := 0;
BEGIN
    IF p_title_pattern IS NULL OR BTRIM(p_title_pattern) = '' THEN
        RAISE EXCEPTION 'Search pattern cannot be NULL or empty';
    END IF;
 
    -- Count matching in-stock films before running the full query.
    -- We do this because FOUND is not set by RETURN QUERY in plpgsql.
    SELECT COUNT(DISTINCT film.film_id)
    INTO v_match_count
    FROM public.film
    WHERE lower(film.title) LIKE lower(p_title_pattern)
      AND EXISTS (
            SELECT 1
            FROM public.inventory
            WHERE inventory.film_id = film.film_id
              AND public.inventory_in_stock(inventory.inventory_id) = TRUE
          );
 
    IF v_match_count = 0 THEN
        RETURN QUERY
        SELECT
            1::bigint,
            'Movie not found or not currently in stock'::text,
            '-'::text,
            '-'::text,
            '-'::text;
        RETURN;
    END IF;
 
    RETURN QUERY
    WITH
    -- Step 1: find films matching the pattern that have at least one copy in stock
    matched_films AS (
        SELECT
            film.film_id,
            film.title        AS film_title,
            language.name     AS language_name
        FROM public.film
        JOIN public.language
            ON language.language_id = film.language_id
        WHERE lower(film.title) LIKE lower(p_title_pattern)
          AND EXISTS (
                SELECT 1
                FROM public.inventory
                WHERE inventory.film_id = film.film_id
                  AND public.inventory_in_stock(inventory.inventory_id) = TRUE
              )
    ),
    -- Step 2: for each matched film, find the most recent rental
    latest_rental AS (
        SELECT
            matched_films.film_id,
            CONCAT(customer.first_name, ' ', customer.last_name) AS full_customer_name,
            TO_CHAR(rental.rental_date, 'YYYY-MM-DD HH24:MI:SS') AS formatted_rental_date,
            ROW_NUMBER() OVER (
                PARTITION BY matched_films.film_id
                ORDER BY rental.rental_date DESC NULLS LAST
            ) AS recency_rank
        FROM matched_films
        LEFT JOIN public.inventory
            ON inventory.film_id            = matched_films.film_id
        LEFT JOIN public.rental
            ON rental.inventory_id          = inventory.inventory_id
        LEFT JOIN public.customer
            ON customer.customer_id         = rental.customer_id
    )
    SELECT
        ROW_NUMBER() OVER (
            ORDER BY upper(matched_films.film_title), matched_films.film_id
        )::bigint AS row_num,
        matched_films.film_title,
        initcap(matched_films.language_name),
        COALESCE(latest_rental.full_customer_name,    '-'),
        COALESCE(latest_rental.formatted_rental_date, '-')
    FROM matched_films
    LEFT JOIN latest_rental
           ON latest_rental.film_id      = matched_films.film_id
          AND latest_rental.recency_rank = 1;
 
END;
$$;
 
 
-- TEST 1 (valid — 'love' appears in several titles in the sample db):
SELECT * FROM core.films_in_stock_by_title('%love%');
 
-- TEST 2 (edge — pattern that matches nothing, expect the "not found" row):
SELECT * FROM core.films_in_stock_by_title('%zzzzzzzznomatch%');
 
-- TEST 3 (edge — empty string, should raise exception):
SELECT * FROM core.films_in_stock_by_title('');
 
 
-- ============================================================
-- TASK 5. PROCEDURE LANGUAGE FUNCTION
-- new_movie
-- ============================================================
 
-- Inserts a new film into public.film.
--
-- How a unique ID is generated:
--   The function generates a new film_id dynamically as
--   COALESCE(MAX(film_id), 0) + 1 from the public.film table.
--   This avoids hardcoding IDs and works even when film_id is not
--   backed by a usable sequence in the current database.
--
-- How duplicates are prevented:
--   Before inserting, we check whether a film with the same title
--   already exists. The check is case-insensitive — "Alien" and
--   "alien" are treated as the same title. If a match is found, an
--   exception is raised and nothing is inserted.
--
-- How language validation works:
--   We look up the given language name in public.language with a
--   case-insensitive match. If it is not found, an exception is raised
--   before anything is inserted.
--
-- What happens if the default language Klingon is not in the table:
--   The function raises: Language "Klingon" does not exist in the
--   language table. The function does not insert Klingon itself —
--   its job is to verify, not to modify reference data. If Klingon
--   is needed, it must be added to public.language manually first.
--   This is intentional and satisfies the requirement that the
--   function verifies language existence.
--
-- Optional parameters:
--   p_release_year defaults to the current year.
--   p_language defaults to 'Klingon'.
--
-- Why fulltext is not in the INSERT column list:
--   The fulltext column is a tsvector, usually maintained by a trigger.
--   Manually inserting NULL for it can conflict with some dvdrental
--   configurations. Leaving it out lets the database handle it as
--   intended and makes the function more portable.
--
-- What happens if the INSERT itself fails unexpectedly:
--   A dedicated EXCEPTION block wraps only the INSERT statement.
--   Validation exceptions raised before it are not caught here —
--   they bubble up with their original messages unchanged.
--
-- Consistency:
--   All validation runs before the INSERT. If anything fails during
--   the insert, PostgreSQL rolls back automatically.
 
CREATE OR REPLACE FUNCTION core.new_movie(
    p_title        TEXT,
    p_release_year INTEGER DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER,
    p_language     TEXT    DEFAULT 'Klingon'
)
RETURNS TABLE (
    new_film_id      INTEGER,
    new_title        TEXT,
    new_release_year INTEGER,
    new_language     TEXT,
    result_message   TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_film_id        INTEGER;
    v_language_id    INTEGER;
    v_language_name  TEXT;
BEGIN
    -- Validate title
    IF p_title IS NULL OR BTRIM(p_title) = '' THEN
        RAISE EXCEPTION 'Movie title cannot be NULL or empty';
    END IF;
 
    -- Validate release year range when provided
    IF p_release_year IS NOT NULL
       AND (p_release_year < 1888
            OR p_release_year > EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER + 5)
    THEN
        RAISE EXCEPTION 'Release year % is not valid', p_release_year;
    END IF;
 
    -- Check that the language exists in the reference table
    SELECT language.language_id, language.name
    INTO v_language_id, v_language_name
    FROM public.language
    WHERE lower(language.name) = lower(BTRIM(p_language));
 
    IF v_language_id IS NULL THEN
        RAISE EXCEPTION 'Language "%" does not exist in the language table', p_language;
    END IF;
 
    -- Reject duplicate titles (case-insensitive)
    IF EXISTS (
        SELECT 1
        FROM public.film
        WHERE lower(BTRIM(film.title)) = lower(BTRIM(p_title))
    ) THEN
        RAISE EXCEPTION 'A film called "%" already exists', p_title;
    END IF;
 
    -- Generate the next available film ID based on current max value
    SELECT COALESCE(MAX(film.film_id), 0) + 1
    INTO v_film_id
    FROM public.film;
 
    -- Insert — only this block is wrapped in an error handler so that
    -- validation exceptions above still surface with their own messages
    BEGIN
        INSERT INTO public.film (
            film_id,
            title,
            description,
            release_year,
            language_id,
            original_language_id,
            rental_duration,
            rental_rate,
            length,
            replacement_cost,
            rating,
            last_update,
            special_features
        )
        VALUES (
            v_film_id,
            BTRIM(p_title),
            'Inserted via core.new_movie()',
            COALESCE(p_release_year, EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER),
            v_language_id,
            NULL,
            3,        -- rental_duration: 3 days as required
            4.99,     -- rental_rate as required
            90,       -- default runtime in minutes
            19.99,    -- replacement_cost as required
            'PG',
            CURRENT_TIMESTAMP,
            ARRAY['Trailers']
        );
    EXCEPTION
        WHEN OTHERS THEN
            RAISE EXCEPTION 'Unexpected insert failure: %', SQLERRM;
    END;
 
    RETURN QUERY
    SELECT
        v_film_id,
        BTRIM(p_title),
        COALESCE(p_release_year, EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER),
        v_language_name,
        'Movie inserted successfully'::text;
 
END;
$$;
 

 
-- TEST 1 (valid — English exists in the sample db):
SELECT * FROM core.new_movie('Ani Test Movie', 2025, 'English');
 
-- TEST 2 (duplicate — same title again, should raise exception):
SELECT * FROM core.new_movie('Ani Test Movie', 2025, 'English');
 
-- TEST 3 (default language — raises exception unless Klingon has been
-- manually inserted into public.language first):
SELECT * FROM core.new_movie('Klingon Default Movie');
 
-- TEST 4 (unknown language — should raise exception):
SELECT * FROM core.new_movie('Bad Language Film', 2025, 'Elvish');
 
-- TEST 5 (empty title — should raise exception):
SELECT * FROM core.new_movie('');