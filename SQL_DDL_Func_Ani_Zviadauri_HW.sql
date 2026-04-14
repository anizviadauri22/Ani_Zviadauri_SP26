-- ============================================================
-- Tasks 1-5
-- ============================================================

CREATE SCHEMA IF NOT EXISTS core;


-- ============================================================
-- TASK 1. VIEW
-- sales_revenue_by_category_qtr
-- ============================================================

-- In this view, I show how much revenue each film category earned
-- in the current quarter of the current year.
--
-- How I define the current quarter:
--   I use date_trunc('quarter', CURRENT_DATE) to get the first day
--   of the current quarter. Then I add 3 months to get the start
--   of the next quarter.
--
-- How I define the current year:
--   I also check the year explicitly with EXTRACT(YEAR FROM ...),
--   because I was asked to take the year into account as well.
--
-- Why only categories with sales appear:
--   I start from the payment table, so only categories connected
--   to actual payments in this period can appear in the result.
--
-- Why I keep HAVING SUM(amount) > 0:
--   I use it as an extra safety check, so categories with zero
--   total revenue do not appear.
--
-- Note about the sample data:
--   The sample dvdrental data is historical, so this view may return
--   0 rows for the real current quarter. That is expected. To check
--   that the logic works, I also use a historical test query with
--   a quarter that has data.
--
-- Example of data that should not appear:
--   - categories that had sales in another quarter but not this one
--   - categories that have films but no payments in this period
--   - categories whose total revenue is zero

CREATE OR REPLACE VIEW core.sales_revenue_by_category_qtr AS
SELECT
    upper(category.name)             AS category_name,
    round(SUM(payment.amount), 2)    AS total_sales_revenue
FROM public.payment
INNER JOIN public.rental
    ON rental.rental_id = payment.rental_id
INNER JOIN public.inventory
    ON inventory.inventory_id = rental.inventory_id
INNER JOIN public.film_category
    ON film_category.film_id = inventory.film_id
INNER JOIN public.category
    ON category.category_id = film_category.category_id
WHERE payment.payment_date >= date_trunc('quarter', CURRENT_DATE)
  AND payment.payment_date <  date_trunc('quarter', CURRENT_DATE) + INTERVAL '3 months'
  AND EXTRACT(YEAR FROM payment.payment_date) = EXTRACT(YEAR FROM CURRENT_DATE)
GROUP BY category.name
HAVING SUM(payment.amount) > 0
ORDER BY total_sales_revenue DESC, category.name;


-- TEST 1 (valid — use a quarter that actually has payment data in your sample db):
SELECT
    upper(category.name)             AS category_name,
    round(SUM(payment.amount), 2)    AS total_sales_revenue
FROM public.payment
INNER JOIN public.rental
    ON rental.rental_id = payment.rental_id
INNER JOIN public.inventory
    ON inventory.inventory_id = rental.inventory_id
INNER JOIN public.film_category
    ON film_category.film_id = inventory.film_id
INNER JOIN public.category
    ON category.category_id = film_category.category_id
WHERE payment.payment_date >= DATE '2017-01-01'
  AND payment.payment_date <  DATE '2017-04-01'
  AND EXTRACT(YEAR FROM payment.payment_date) = 2017
GROUP BY category.name
HAVING SUM(payment.amount) > 0
ORDER BY total_sales_revenue DESC, category.name;

-- TEST 2 (edge — today's quarter may have no data in the sample db,
-- so the view may return 0 rows):
SELECT * FROM core.sales_revenue_by_category_qtr;


-- ============================================================
-- TASK 2. QUERY LANGUAGE FUNCTION
-- get_sales_revenue_by_category_qtr
-- ============================================================

-- This function returns the same kind of result as the view,
-- but here I can test any quarter by passing a date.
--
-- Why I use a parameter:
--   The view is always tied to the real current quarter, but with
--   this function I can also check past quarters.
--
-- Why I use a DATE parameter:
--   I chose a DATE instead of a quarter number because a date is
--   more precise and PostgreSQL can derive the quarter from it.
--
-- What happens if the input date is invalid:
--   PostgreSQL rejects an invalid date before the function runs.
--
-- What happens if NULL is passed:
--   I raise an exception immediately because the function cannot
--   determine a quarter from NULL.
--
-- What happens if there is no data:
--   In that case, the function simply returns 0 rows.

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
    INNER JOIN public.rental
        ON rental.rental_id = payment.rental_id
    INNER JOIN public.inventory
        ON inventory.inventory_id = rental.inventory_id
    INNER JOIN public.film_category
        ON film_category.film_id = inventory.film_id
    INNER JOIN public.category
        ON category.category_id = film_category.category_id
    WHERE payment.payment_date >= date_trunc('quarter', p_reference_date)
      AND payment.payment_date <  date_trunc('quarter', p_reference_date) + INTERVAL '3 months'
      AND EXTRACT(YEAR FROM payment.payment_date) = EXTRACT(YEAR FROM p_reference_date)
    GROUP BY category.name
    HAVING SUM(payment.amount) > 0
    ORDER BY total_sales_revenue DESC, category.name;
END;
$$;


-- TEST 1 (valid — a date in a quarter that has real data in the sample db):
SELECT * FROM core.get_sales_revenue_by_category_qtr(DATE '2017-02-15');

-- TEST 2 (edge — NULL input, should raise exception with a clear message):
SELECT * FROM core.get_sales_revenue_by_category_qtr(NULL);

-- TEST 3 (edge — a quarter with no data, should return 0 rows without error):
SELECT * FROM core.get_sales_revenue_by_category_qtr(DATE '2020-06-01');


-- ============================================================
-- TASK 3. PROCEDURE LANGUAGE FUNCTION
-- most_popular_films_by_countries
-- ============================================================

-- This function returns the most popular film for each country
-- from the input array.
--
-- How I define "most popular":
--   I count how many times each film was rented by customers from
--   that country. The film with the highest rental count is the winner.
--
-- How I handle ties:
--   First I compare total revenue. If there is still a tie, I choose
--   the alphabetically first title, so the result is deterministic.
--
-- How I handle countries with no data:
--   I still return the country name, but I show '-' in the film-related
--   columns.
--
-- How I validate the input:
--   I first unnest the array into rows and trim each value.
--   Then I count how many non-blank country names remain.
--   If the count is zero, I raise an exception.

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

    -- Here I validate the input array before the main query starts.
    -- I use unnest(p_countries) to turn the array into separate rows.
    -- Then I trim each value with BTRIM and ignore blank entries.
    -- I store the number of valid country names in v_valid_count.
    -- If the count is zero, it means the input only had empty values,
    -- so I raise an exception.

    SELECT COUNT(*)
    INTO v_valid_count
    FROM unnest(p_countries) AS input_entry
    WHERE BTRIM(input_entry) <> '';

    IF v_valid_count = 0 THEN
        RAISE EXCEPTION 'No valid country names found in the input — all entries were blank';
    END IF;

    RETURN QUERY
    WITH clean_countries AS (
        SELECT DISTINCT lower(BTRIM(input_entry)) AS normalized_name
        FROM unnest(p_countries) AS input_entry
        WHERE BTRIM(input_entry) <> ''
    ),
    film_statistics AS (
        SELECT
            lower(country.country) AS normalized_country,
            film.title AS film_title,
            film.rating::text AS film_rating,
            language.name AS language_name,
            film.length AS film_length,
            film.release_year::text AS film_release_year,
            COUNT(rental.rental_id) AS rental_count,
            COALESCE(SUM(payment.amount), 0) AS total_revenue
        FROM clean_countries
        INNER JOIN public.country
            ON lower(country.country) = clean_countries.normalized_name
        INNER JOIN public.city
            ON city.country_id = country.country_id
        INNER JOIN public.address
            ON address.city_id = city.city_id
        INNER JOIN public.customer
            ON customer.address_id = address.address_id
        INNER JOIN public.rental
            ON rental.customer_id = customer.customer_id
        INNER JOIN public.inventory
            ON inventory.inventory_id = rental.inventory_id
        INNER JOIN public.film
            ON film.film_id = inventory.film_id
        INNER JOIN public.language
            ON language.language_id = film.language_id
        LEFT JOIN public.payment
            ON payment.rental_id = rental.rental_id
        GROUP BY
            lower(country.country),
            film.title,
            film.rating,
            language.name,
            film.length,
            film.release_year
    ),
    max_rentals AS (
        SELECT
            film_statistics.normalized_country,
            MAX(film_statistics.rental_count) AS max_rental_count
        FROM film_statistics
        GROUP BY film_statistics.normalized_country
    ),
    rental_winners AS (
        SELECT film_statistics.*
        FROM film_statistics
        INNER JOIN max_rentals
            ON max_rentals.normalized_country = film_statistics.normalized_country
           AND max_rentals.max_rental_count = film_statistics.rental_count
    ),
    max_revenue AS (
        SELECT
            rental_winners.normalized_country,
            MAX(rental_winners.total_revenue) AS max_total_revenue
        FROM rental_winners
        GROUP BY rental_winners.normalized_country
    ),
    revenue_winners AS (
        SELECT rental_winners.*
        FROM rental_winners
        INNER JOIN max_revenue
            ON max_revenue.normalized_country = rental_winners.normalized_country
           AND max_revenue.max_total_revenue = rental_winners.total_revenue
    ),
    final_titles AS (
        SELECT
            revenue_winners.normalized_country,
            MIN(upper(revenue_winners.film_title)) AS selected_title_upper
        FROM revenue_winners
        GROUP BY revenue_winners.normalized_country
    ),
    final_result AS (
        SELECT revenue_winners.*
        FROM revenue_winners
        INNER JOIN final_titles
            ON final_titles.normalized_country = revenue_winners.normalized_country
           AND final_titles.selected_title_upper = upper(revenue_winners.film_title)
    )
    SELECT
        initcap(clean_countries.normalized_name),
        COALESCE(final_result.film_title, '-'),
        COALESCE(upper(final_result.film_rating), '-'),
        COALESCE(initcap(final_result.language_name), '-'),
        COALESCE(final_result.film_length::text, '-'),
        COALESCE(final_result.film_release_year, '-')
    FROM clean_countries
    LEFT JOIN final_result
           ON final_result.normalized_country = clean_countries.normalized_name
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

-- This function returns films that are currently in stock
-- and match the title pattern I pass.
--
-- How pattern matching works:
--   I use LIKE with lower(...) on both sides, so the search is
--   case-insensitive. For example, '%love%' and '%Love%' work the same.
--
-- How I define "in stock":
--   I use the existing inventory_in_stock() function.
--   A film is considered available if at least one copy is not
--   rented right now.
--
-- How I keep the query simpler:
--   First I find matching titles, then I check which of them are
--   currently in stock, and only after that I get the rental details.
--
-- What happens if nothing matches:
--   I return one informational row instead of returning nothing.
--
-- What happens if the input is NULL or blank:
--   I raise an exception immediately.

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
    WITH matched_films AS (
        SELECT
            film.film_id,
            film.title AS film_title,
            language.name AS language_name
        FROM public.film
        INNER JOIN public.language
            ON language.language_id = film.language_id
        WHERE lower(film.title) LIKE lower(p_title_pattern)
          AND EXISTS (
                SELECT 1
                FROM public.inventory
                WHERE inventory.film_id = film.film_id
                  AND public.inventory_in_stock(inventory.inventory_id) = TRUE
              )
    ),
    latest_rental_date AS (
        SELECT
            matched_films.film_id,
            MAX(rental.rental_date) AS latest_date
        FROM matched_films
        LEFT JOIN public.inventory
            ON inventory.film_id = matched_films.film_id
        LEFT JOIN public.rental
            ON rental.inventory_id = inventory.inventory_id
        GROUP BY matched_films.film_id
    ),
    latest_rental_details AS (
        SELECT
            matched_films.film_id,
            CONCAT(customer.first_name, ' ', customer.last_name) AS full_customer_name,
            TO_CHAR(rental.rental_date, 'YYYY-MM-DD HH24:MI:SS') AS formatted_rental_date
        FROM matched_films
        LEFT JOIN public.inventory
            ON inventory.film_id = matched_films.film_id
        LEFT JOIN public.rental
            ON rental.inventory_id = inventory.inventory_id
        LEFT JOIN public.customer
            ON customer.customer_id = rental.customer_id
        INNER JOIN latest_rental_date
            ON latest_rental_date.film_id = matched_films.film_id
           AND latest_rental_date.latest_date IS NOT DISTINCT FROM rental.rental_date
    ),
    final_rows AS (
        SELECT DISTINCT
            matched_films.film_id,
            matched_films.film_title,
            matched_films.language_name,
            COALESCE(latest_rental_details.full_customer_name, '-') AS customer_name_value,
            COALESCE(latest_rental_details.formatted_rental_date, '-') AS rental_date_value
        FROM matched_films
        LEFT JOIN latest_rental_details
            ON latest_rental_details.film_id = matched_films.film_id
    )
    SELECT
        (
            SELECT COUNT(*)
            FROM final_rows AS numbering_rows
            WHERE upper(numbering_rows.film_title) < upper(final_rows.film_title)
               OR (
                    upper(numbering_rows.film_title) = upper(final_rows.film_title)
                    AND numbering_rows.film_id <= final_rows.film_id
                  )
        )::bigint AS row_num,
        final_rows.film_title,
        initcap(final_rows.language_name),
        final_rows.customer_name_value,
        final_rows.rental_date_value
    FROM final_rows
    ORDER BY upper(final_rows.film_title), final_rows.film_id;

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

-- This function inserts a new movie into public.film.
--
-- How I generate a new ID:
--   I get the next available film_id from the sequence
--   public.film_film_id_seq by calling nextval().
--
-- How I prevent duplicates:
--   Before inserting, I check whether the same title already exists.
--   I compare titles case-insensitively, so titles like 'Alien' and
--   'alien' are treated as duplicates.
--
-- How I validate the language:
--   I check whether the language exists in public.language.
--   If it does not exist, I raise an exception before the insert.
--
-- What happens if the default language Klingon does not exist:
--   I raise an exception. I do not insert new reference data here,
--   because this function is only supposed to validate it.
--
-- Optional parameters:
--   If release year is not passed, I use the current year.
--   If language is not passed, I use 'Klingon'.
--
-- Why I do not include fulltext in the INSERT:
--   I leave that column to the database logic, because in dvdrental
--   it is usually maintained automatically.
--
-- What happens if the insert fails:
--   I catch unexpected insert errors and raise a clear exception.
--
-- How I keep consistency:
--   I do all validation first, and only then I try to insert the row.

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
    IF p_title IS NULL OR BTRIM(p_title) = '' THEN
        RAISE EXCEPTION 'Movie title cannot be NULL or empty';
    END IF;

    IF p_release_year IS NOT NULL
       AND (p_release_year < 1888
            OR p_release_year > EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER + 5)
    THEN
        RAISE EXCEPTION 'Release year % is not valid', p_release_year;
    END IF;

    SELECT language.language_id, language.name
    INTO v_language_id, v_language_name
    FROM public.language
    WHERE lower(language.name) = lower(BTRIM(p_language));

    IF v_language_id IS NULL THEN
        RAISE EXCEPTION 'Language "%" does not exist in the language table', p_language;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.film
        WHERE lower(BTRIM(film.title)) = lower(BTRIM(p_title))
    ) THEN
        RAISE EXCEPTION 'A film called "%" already exists', p_title;
    END IF;

    -- Get the next available film ID from the film sequence
    SELECT nextval('public.film_film_id_seq'::regclass)
    INTO v_film_id;

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
            3,
            4.99,
            90,
            19.99,
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