/* =========================================================
PART 1 - ASSUMPTIONS AND MY UNDERSTANDING OF THE TASK
========================================================= */
-- Identifying Animation:
-- I’m defining "Animation movies" as any film linked to the 'Animation' category by joining the film, film_category, and category tables.

-- Setting the Date Range:
-- When I look for movies "between 2017 and 2019," I'm including both of those years in my search.

-- Filtering by Rate:
-- To show movies with a "rate more than 1," I’m specifically looking for a rental_rate greater than 1.

-- Defining the Starting Point:
-- For anything "after March 2017," I’m starting my count right on April 1, 2017.

-- Calculating Revenue:
-- I’m getting all my revenue figures by summing up the amount column in the payments table.

-- Connecting Revenue to Stores:
-- To figure out which store earned what, I’m following the trail from the payment to the rental, then to the specific inventory item, and finally to the store that owns it.

-- Cleaning up Addresses:
-- I’m merging the two address columns into one. If the second address line is empty or missing, I just show the first one; otherwise, I’ll separate them with a comma.

-- Ranking Top Actors:
-- To find the top 5 actors since 2015, I’m counting every film they’ve been in that has a release year of 2015 or later.

-- Tracking Genre Trends:
-- I’m grouping movies by their release year and then counting how many Drama, Travel, and Documentary films were made in each of those years.

-- Handling Missing Data:
-- If a certain genre didn't have any movies in a specific year, I’ve made sure the result shows a 0 instead of leaving it blank or as a NULL.

-- Using Joins:
-- I am using explicit join types (like INNER or LEFT) for every query to make sure the logic is clear and the results are predictable.

/* =========================================================
PART 1 - TASK 1
Conditions:
The marketing team needs a list of animation movies between 2017 and 2019
to promote family-friendly content in an upcoming season in stores.
Show all animation movies released during this period with rate more than 1 and sort them alphabetically.

Expected output example:
title, release_year, rental_rate

JOIN behavior:
-- INNER JOIN public.film_category keeps only films that are linked to a category.
-- INNER JOIN public.category keeps only films that belong to an existing category.
-- This means only valid "Animation" movies will appear in the result.
========================================================= */

-- ---------------------------------------------------------
-- TASK 1 - JOIN SOLUTION
-- I think this is production-friendly because the logic is simple,
-- easy to read, and directly shows how tables are connected.
-- ---------------------------------------------------------
SELECT
    film.title,
    film.release_year,
    film.rental_rate
FROM public.film AS film
INNER JOIN public.film_category AS film_category
    ON film.film_id = film_category.film_id
INNER JOIN public.category AS category
    ON film_category.category_id = category.category_id
WHERE category.name = 'Animation'
  AND film.release_year BETWEEN 2017 AND 2019
  AND film.rental_rate > 1
ORDER BY film.title ASC;


-- ---------------------------------------------------------
-- TASK 1 - SUBQUERY SOLUTION
-- Here I use a subquery to first filter only Animation films
-- and then apply the rest of the conditions.
-- ---------------------------------------------------------
SELECT
    film.title,
    film.release_year,
    film.rental_rate
FROM public.film AS film
WHERE film.film_id IN (
    SELECT
        film_category.film_id
    FROM public.film_category AS film_category
    INNER JOIN public.category AS category
        ON film_category.category_id = category.category_id
    WHERE category.name = 'Animation'
)
  AND film.release_year BETWEEN 2017 AND 2019
  AND film.rental_rate > 1
ORDER BY film.title ASC;


-- ---------------------------------------------------------
-- TASK 1 - CTE SOLUTION
-- Here I use a CTE to first identify Animation films,
-- and then I filter them in the main query.
-- ---------------------------------------------------------
WITH animation_films AS (
    SELECT
        film_category.film_id
    FROM public.film_category AS film_category
    INNER JOIN public.category AS category
        ON film_category.category_id = category.category_id
    WHERE category.name = 'Animation'
)
SELECT
    film.title,
    film.release_year,
    film.rental_rate
FROM public.film AS film
INNER JOIN animation_films AS animation_films_cte
    ON film.film_id = animation_films_cte.film_id
WHERE film.release_year BETWEEN 2017 AND 2019
  AND film.rental_rate > 1
ORDER BY film.title ASC;

-- Advantages / disadvantages / production choice:

-- CTE advantages:
-- I think this is easy to understand because the logic is split into steps.
-- It is also easier to change later if the task becomes more complex.

-- CTE disadvantages:
-- It is a bit longer than needed for a simple task.

-- Subquery advantages:
-- I find this solution more compact.
-- It works well when I just need a simple intermediate result.

-- Subquery disadvantages:
-- It can be a bit harder to read compared to a direct JOIN.

-- JOIN advantages:
-- I think this is the most clear and straightforward solution.
-- It is easy to follow how the tables are connected.

-- JOIN disadvantages:
-- It can become harder to read if I add more conditions later.

-- Production choice:
-- I would use the JOIN solution in production because it is simple,
-- clear, and easy to understand.

/* =========================================================
PART 1 - TASK 2

Conditions:
The finance department requires a report on store performance to assess
profitability and plan resource allocation for stores after March 2017.
Calculate the revenue earned by each rental store after March 2017
(since April) (include columns: address and address2 – as one column, revenue).

Expected output example:
store_address, revenue

My understanding:
-- I calculate revenue by summing payment amounts after April 1, 2017.
-- I connect payments to stores through rental and inventory tables.
-- I combine address and address2 into one column.
-- If address2 is empty, I only show address.

JOIN behavior:
-- INNER JOIN public.inventory keeps only inventory that belongs to stores.
-- INNER JOIN public.rental keeps only inventory that was rented.
-- INNER JOIN public.payment keeps only rentals that generated payments.
-- INNER JOIN public.address keeps only valid store addresses.

========================================================= */
-- ---------------------------------------------------------
-- TASK 2 - JOIN SOLUTION
-- Here I directly calculate revenue for each store using joins.
-- I group by store address and sum all payments after April 2017.
-- ---------------------------------------------------------
SELECT
    CASE
        WHEN address.address2 IS NULL OR address.address2 = '' THEN address.address
        ELSE address.address || ', ' || address.address2
    END AS store_address,
    SUM(payment.amount) AS revenue
FROM public.store AS store
INNER JOIN public.address AS address
    ON store.address_id = address.address_id
INNER JOIN public.inventory AS inventory
    ON store.store_id = inventory.store_id
INNER JOIN public.rental AS rental
    ON inventory.inventory_id = rental.inventory_id
INNER JOIN public.payment AS payment
    ON rental.rental_id = payment.rental_id
WHERE payment.payment_date >= DATE '2017-04-01'
GROUP BY
    CASE
        WHEN address.address2 IS NULL OR address.address2 = '' THEN address.address
        ELSE address.address || ', ' || address.address2
    END
ORDER BY revenue DESC, store_address ASC;

-- ---------------------------------------------------------
-- TASK 2 - SUBQUERY SOLUTION
-- Here I first calculate revenue per store in a subquery,
-- and then I join it with the address table.
-- ---------------------------------------------------------
SELECT
    CASE
        WHEN address.address2 IS NULL OR address.address2 = '' THEN address.address
        ELSE address.address || ', ' || address.address2
    END AS store_address,
    store_revenue.revenue
FROM public.store AS store
INNER JOIN public.address AS address
    ON store.address_id = address.address_id
INNER JOIN (
    SELECT
        inventory.store_id,
        SUM(payment.amount) AS revenue
    FROM public.inventory AS inventory
    INNER JOIN public.rental AS rental
        ON inventory.inventory_id = rental.inventory_id
    INNER JOIN public.payment AS payment
        ON rental.rental_id = payment.rental_id
    WHERE payment.payment_date >= DATE '2017-04-01'
    GROUP BY inventory.store_id
) AS store_revenue
    ON store.store_id = store_revenue.store_id
ORDER BY store_revenue.revenue DESC, store_address ASC;




-- ---------------------------------------------------------
-- TASK 2 - CTE SOLUTION
-- Here I use a CTE to calculate revenue first,
-- and then I join it with store and address information.
-- ---------------------------------------------------------
WITH store_revenue AS (
    SELECT
        inventory.store_id,
        SUM(payment.amount) AS revenue
    FROM public.inventory AS inventory
    INNER JOIN public.rental AS rental
        ON inventory.inventory_id = rental.inventory_id
    INNER JOIN public.payment AS payment
        ON rental.rental_id = payment.rental_id
    WHERE payment.payment_date >= DATE '2017-04-01'
    GROUP BY inventory.store_id
)
SELECT
    CASE
        WHEN address.address2 IS NULL OR address.address2 = '' THEN address.address
        ELSE address.address || ', ' || address.address2
    END AS store_address,
    store_revenue.revenue
FROM store_revenue
INNER JOIN public.store AS store
    ON store_revenue.store_id = store.store_id
INNER JOIN public.address AS address
    ON store.address_id = address.address_id
ORDER BY store_revenue.revenue DESC, store_address ASC;

-- Advantages / disadvantages / production choice:
-- ---------------------------------------------------------

-- CTE advantages:
-- I think this is the easiest to understand because I separate the steps.
-- It is also easier to test and modify later.

-- CTE disadvantages:
-- It is a bit longer than the JOIN version.

-- Subquery advantages:
-- I keep the revenue calculation in one place.
-- It is a good balance between short and structured.

-- Subquery disadvantages:
-- It can be harder to debug compared to a CTE.

-- JOIN advantages:
-- I think this is very direct and efficient.
-- Everything is done in one query.

-- JOIN disadvantages:
-- The logic can get harder to read if I add more conditions.
-- Also, I need to repeat expressions in GROUP BY.

-- Production choice:
-- I would use the CTE solution in production because it is clearer,
-- easier to maintain, and separates the logic into steps.

/* =========================================================
PART 1 - TASK 3
Conditions:
The marketing department in our stores aims to identify the most successful
actors since 2015 to boost customer interest in their films.
Show top-5 actors by number of movies (released since 2015) they took part in
(columns: first_name, last_name, number_of_movies, sorted by number_of_movies
in descending order).

Expected output example:
first_name, last_name, number_of_movies

JOIN behavior:
- INNER JOIN public.film_actor keeps only valid actor-film links.
- INNER JOIN public.film keeps only linked films that exist.
========================================================= */
/*
My understanding:
-- I count how many films each actor appeared in since 2015.
-- I connect actor → film_actor → film to get this information.
-- Then I group by actor and sort by number of movies. 
-- ---------------------------------------------------------
========================================================= */

-- TASK 3 - JOIN SOLUTION
-- Here I directly join actor, film_actor and film tables
-- and count how many movies each actor has.
------------------------------------------------------------
SELECT
    actor.first_name,
    actor.last_name,
    COUNT(film.film_id) AS number_of_movies
FROM public.actor AS actor
INNER JOIN public.film_actor AS film_actor
    ON actor.actor_id = film_actor.actor_id
INNER JOIN public.film AS film
    ON film_actor.film_id = film.film_id
WHERE film.release_year >= 2015
GROUP BY
    actor.actor_id,
    actor.first_name,
    actor.last_name
ORDER BY
    number_of_movies DESC,
    actor.last_name ASC,
    actor.first_name ASC
LIMIT 5;


-------------------------------------------------------------
-- TASK 3 - SUBQUERY SOLUTION
-- Here I first select all actor-film combinations since 2015,
-- and then I group and count them in the outer query.
-- ---------------------------------------------------------
SELECT
    actor_films.first_name,
    actor_films.last_name,
    COUNT(actor_films.film_id) AS number_of_movies
FROM (
    SELECT
        actor.actor_id,
        actor.first_name,
        actor.last_name,
        film.film_id
    FROM public.actor AS actor
    INNER JOIN public.film_actor AS film_actor
        ON actor.actor_id = film_actor.actor_id
    INNER JOIN public.film AS film
        ON film_actor.film_id = film.film_id
    WHERE film.release_year >= 2015
) AS actor_films
GROUP BY
    actor_films.actor_id,
    actor_films.first_name,
    actor_films.last_name
ORDER BY
    number_of_movies DESC,
    actor_films.last_name ASC,
    actor_films.first_name ASC
LIMIT 5;
--------------------------------------------------
-- TASK 3 - CTE SOLUTION
-- Here I use a CTE to first get all actor-film rows since 2015,
-- and then I aggregate them in the main query.
-- ---------------------------------------------------------
WITH actor_films_since_2015 AS (
    SELECT
        actor.actor_id,
        actor.first_name,
        actor.last_name,
        film.film_id
    FROM public.actor AS actor
    INNER JOIN public.film_actor AS film_actor
        ON actor.actor_id = film_actor.actor_id
    INNER JOIN public.film AS film
        ON film_actor.film_id = film.film_id
    WHERE film.release_year >= 2015
)
SELECT
    actor_films_since_2015.first_name,
    actor_films_since_2015.last_name,
    COUNT(actor_films_since_2015.film_id) AS number_of_movies
FROM actor_films_since_2015
GROUP BY
    actor_films_since_2015.actor_id,
    actor_films_since_2015.first_name,
    actor_films_since_2015.last_name
ORDER BY
    number_of_movies DESC,
    actor_films_since_2015.last_name ASC,
    actor_films_since_2015.first_name ASC
LIMIT 5;

-- Advantages / disadvantages / production choice:

-- CTE advantages:
-- I think this is easy to extend if I need to add more filters later.
-- It is also easier to test the intermediate result.

-- CTE disadvantages:
-- It is longer than needed for a simple aggregation.

-- Subquery advantages:
-- I find this solution compact and clear.
-- It works well when I only need the intermediate result once.

-- Subquery disadvantages:
-- It is slightly less clear than using a named CTE.

-- JOIN advantages:
-- I think this is the simplest and most readable solution.
-- It fits naturally because I am just joining and counting.

-- JOIN disadvantages:
-- It can be less flexible if the logic becomes more complex.

-- Production choice:
-- I would use the JOIN solution in production because it is simple,
-- clear and easy to understand.

/* =========================================================

PART 1 - TASK 4
Conditions:
The marketing team needs to track the production trends of Drama, Travel,
and Documentary films to inform genre-specific marketing strategies.
Show number of Drama, Travel, Documentary per year
(include columns:
 release_year,
 number_of_drama_movies,
 number_of_travel_movies,
 number_of_documentary_movies),
sorted by release year in descending order.
Dealing with NULL values is encouraged.

Expected output example:
release_year, number_of_drama_movies, number_of_travel_movies,
number_of_documentary_movies

JOIN behavior:
- INNER JOIN public.film_category keeps only films linked to categories.
- INNER JOIN public.category keeps only rows with valid category definitions.
- LEFT JOIN in alternative solutions preserves years even if one genre has no rows.

My understanding:
-- I group movies by release year.
-- Then I count how many films belong to each of the three categories.
-- I make sure that if a category has no films in a year,
-- I show 0 instead of NULL.

========================================================= */

-- ---------------------------------------------------------
-- TASK 4 - JOIN SOLUTION
-- Here I use conditional aggregation to count each category
-- directly in one query.
-- ---------------------------------------------------------
SELECT
    film.release_year,
    SUM(CASE WHEN category.name = 'Drama' THEN 1 ELSE 0 END) AS number_of_drama_movies,
    SUM(CASE WHEN category.name = 'Travel' THEN 1 ELSE 0 END) AS number_of_travel_movies,
    SUM(CASE WHEN category.name = 'Documentary' THEN 1 ELSE 0 END) AS number_of_documentary_movies
FROM public.film AS film
INNER JOIN public.film_category AS film_category
    ON film.film_id = film_category.film_id
INNER JOIN public.category AS category
    ON film_category.category_id = category.category_id
WHERE category.name IN ('Drama', 'Travel', 'Documentary')
GROUP BY film.release_year
ORDER BY film.release_year DESC;

-- ---------------------------------------------------------
-- TASK 4 - SUBQUERY SOLUTION
-- Here I calculate counts for each category separately,
-- and then I join them together by release year.
-- I use LEFT JOIN to make sure no years are lost.
-- ---------------------------------------------------------
SELECT
    release_years.release_year,
    COALESCE(drama_counts.number_of_drama_movies, 0) AS number_of_drama_movies,
    COALESCE(travel_counts.number_of_travel_movies, 0) AS number_of_travel_movies,
    COALESCE(documentary_counts.number_of_documentary_movies, 0) AS number_of_documentary_movies
FROM (
    SELECT DISTINCT
        film.release_year
    FROM public.film AS film
    INNER JOIN public.film_category AS film_category
        ON film.film_id = film_category.film_id
    INNER JOIN public.category AS category
        ON film_category.category_id = category.category_id
    WHERE category.name IN ('Drama', 'Travel', 'Documentary')
) AS release_years
LEFT JOIN (
    SELECT
        film.release_year,
        COUNT(*) AS number_of_drama_movies
    FROM public.film AS film
    INNER JOIN public.film_category AS film_category
        ON film.film_id = film_category.film_id
    INNER JOIN public.category AS category
        ON film_category.category_id = category.category_id
    WHERE category.name = 'Drama'
    GROUP BY film.release_year
) AS drama_counts
    ON release_years.release_year = drama_counts.release_year
LEFT JOIN (
    SELECT
        film.release_year,
        COUNT(*) AS number_of_travel_movies
    FROM public.film AS film
    INNER JOIN public.film_category AS film_category
        ON film.film_id = film_category.film_id
    INNER JOIN public.category AS category
        ON film_category.category_id = category.category_id
    WHERE category.name = 'Travel'
    GROUP BY film.release_year
) AS travel_counts
    ON release_years.release_year = travel_counts.release_year
LEFT JOIN (
    SELECT
        film.release_year,
        COUNT(*) AS number_of_documentary_movies
    FROM public.film AS film
    INNER JOIN public.film_category AS film_category
        ON film.film_id = film_category.film_id
    INNER JOIN public.category AS category
        ON film_category.category_id = category.category_id
    WHERE category.name = 'Documentary'
    GROUP BY film.release_year
) AS documentary_counts
    ON release_years.release_year = documentary_counts.release_year
ORDER BY release_years.release_year DESC;


-- ---------------------------------------------------------
-- TASK 4 - CTE SOLUTION
-- Here I first filter only the needed categories in a CTE,
-- and then I aggregate them in the main query.
-- ---------------------------------------------------------
WITH genre_films AS (
    SELECT
        film.release_year,
        category.name AS category_name
    FROM public.film AS film
    INNER JOIN public.film_category AS film_category
        ON film.film_id = film_category.film_id
    INNER JOIN public.category AS category
        ON film_category.category_id = category.category_id
    WHERE category.name IN ('Drama', 'Travel', 'Documentary')
)
SELECT
    genre_films.release_year,
    SUM(CASE WHEN genre_films.category_name = 'Drama' THEN 1 ELSE 0 END) AS number_of_drama_movies,
    SUM(CASE WHEN genre_films.category_name = 'Travel' THEN 1 ELSE 0 END) AS number_of_travel_movies,
    SUM(CASE WHEN genre_films.category_name = 'Documentary' THEN 1 ELSE 0 END) AS number_of_documentary_movies
FROM genre_films
GROUP BY genre_films.release_year
ORDER BY genre_films.release_year DESC;

-- Advantages / disadvantages / production choice:

-- CTE advantages:
-- I think this is very clear because I separate filtering and aggregation.
-- It is also easy to extend with more categories later.

-- CTE disadvantages:
-- It is a bit longer than the JOIN solution.

-- Subquery advantages:
-- I can clearly see how each category is calculated.
-- LEFT JOIN helps me keep all years even if some categories are missing.

-- Subquery disadvantages:
-- It is the longest and repeats similar logic multiple times.

-- JOIN advantages:
-- I think this is the most compact and efficient solution.
-- Conditional aggregation is simple and commonly used.

-- JOIN disadvantages:
-- It is slightly less flexible if I need to change the logic later.

-- Production choice:
-- I would use the JOIN solution in production because it is the most
-- straightforward and clean way to solve this task.




/* =========================================================
PART 2 - TASK 1

Conditions:
The HR department aims to reward top-performing employees in 2017
with bonuses to recognize their contribution to stores revenue.
Show which three employees generated the most revenue in 2017.

Assumptions:
-- staff could work in several stores in a year, please indicate
-- which store the staff worked in (the last one);
-- if staff processed the payment then he works in the same store;
-- take into account only payment_date

Expected output example:
first_name, last_name, revenue_2017, last_store_id, last_store_address

My understanding:
-- I sum all payments processed by each staff member in 2017.
-- Then I find the latest payment_date for each staff member in 2017.
-- I use the store connected to that latest payment as the last store.
========================================================= */

-- ---------------------------------------------------------
-- TASK 1 - JOIN SOLUTION
-- Here I calculate the 2017 revenue per staff member
-- and join it with the last store they worked in during 2017.
-- ---------------------------------------------------------

SELECT
    staff.first_name,
    staff.last_name,
    revenue_summary.revenue_2017,
    last_store_summary.last_store_id,
    last_store_summary.last_store_address
FROM public.staff AS staff
INNER JOIN (
    SELECT
        payment.staff_id,
        SUM(payment.amount) AS revenue_2017
    FROM public.payment AS payment
    WHERE payment.payment_date >= TIMESTAMP '2017-01-01 00:00:00'
      AND payment.payment_date < TIMESTAMP '2018-01-01 00:00:00'
    GROUP BY payment.staff_id
) AS revenue_summary
    ON staff.staff_id = revenue_summary.staff_id
INNER JOIN (
    SELECT
        latest_store_rows.staff_id,
        MIN(latest_store_rows.store_id) AS last_store_id,
        MIN(latest_store_rows.store_address) AS last_store_address
    FROM (
        SELECT
            payment.staff_id,
            inventory.store_id,
            CASE
                WHEN address.address2 IS NULL OR address.address2 = '' THEN address.address
                ELSE address.address || ', ' || address.address2
            END AS store_address,
            payment.payment_date
        FROM public.payment AS payment
        INNER JOIN public.rental AS rental
            ON payment.rental_id = rental.rental_id
        INNER JOIN public.inventory AS inventory
            ON rental.inventory_id = inventory.inventory_id
        INNER JOIN public.store AS store
            ON inventory.store_id = store.store_id
        INNER JOIN public.address AS address
            ON store.address_id = address.address_id
        LEFT JOIN public.payment AS later_payment
            ON payment.staff_id = later_payment.staff_id
           AND later_payment.payment_date >= TIMESTAMP '2017-01-01 00:00:00'
           AND later_payment.payment_date < TIMESTAMP '2018-01-01 00:00:00'
           AND later_payment.payment_date > payment.payment_date
        WHERE payment.payment_date >= TIMESTAMP '2017-01-01 00:00:00'
          AND payment.payment_date < TIMESTAMP '2018-01-01 00:00:00'
          AND later_payment.payment_id IS NULL
    ) AS latest_store_rows
    GROUP BY latest_store_rows.staff_id
) AS last_store_summary
    ON staff.staff_id = last_store_summary.staff_id
ORDER BY
    revenue_summary.revenue_2017 DESC,
    staff.last_name ASC,
    staff.first_name ASC
LIMIT 3;


-- ---------------------------------------------------------
-- TASK 1 - SUBQUERY SOLUTION
-- Here I use subqueries to first calculate revenue,
-- then find the latest payment date,
-- and then connect that date to the last store.
-- ---------------------------------------------------------
SELECT
    staff.first_name,
    staff.last_name,
    revenue_summary.revenue_2017,
    last_store_summary.last_store_id,
    last_store_summary.last_store_address
FROM public.staff AS staff
INNER JOIN (
    SELECT
        payment.staff_id,
        SUM(payment.amount) AS revenue_2017
    FROM public.payment AS payment
    WHERE payment.payment_date >= TIMESTAMP '2017-01-01 00:00:00'
      AND payment.payment_date < TIMESTAMP '2018-01-01 00:00:00'
    GROUP BY payment.staff_id
) AS revenue_summary
    ON staff.staff_id = revenue_summary.staff_id
INNER JOIN (
    SELECT
        latest_store_rows.staff_id,
        MIN(latest_store_rows.store_id) AS last_store_id,
        MIN(latest_store_rows.store_address) AS last_store_address
    FROM (
        SELECT
            payment.staff_id,
            inventory.store_id,
            CASE
                WHEN address.address2 IS NULL OR address.address2 = '' THEN address.address
                ELSE address.address || ', ' || address.address2
            END AS store_address
        FROM public.payment AS payment
        INNER JOIN public.rental AS rental
            ON payment.rental_id = rental.rental_id
        INNER JOIN public.inventory AS inventory
            ON rental.inventory_id = inventory.inventory_id
        INNER JOIN public.store AS store
            ON inventory.store_id = store.store_id
        INNER JOIN public.address AS address
            ON store.address_id = address.address_id
        WHERE payment.payment_date = (
            SELECT MAX(payment_2017.payment_date)
            FROM public.payment AS payment_2017
            WHERE payment_2017.staff_id = payment.staff_id
              AND payment_2017.payment_date >= TIMESTAMP '2017-01-01 00:00:00'
              AND payment_2017.payment_date < TIMESTAMP '2018-01-01 00:00:00'
        )
          AND payment.payment_date >= TIMESTAMP '2017-01-01 00:00:00'
          AND payment.payment_date < TIMESTAMP '2018-01-01 00:00:00'
    ) AS latest_store_rows
    GROUP BY latest_store_rows.staff_id
) AS last_store_summary
    ON staff.staff_id = last_store_summary.staff_id
ORDER BY
    revenue_summary.revenue_2017 DESC,
    staff.last_name ASC,
    staff.first_name ASC
LIMIT 3;


-- ---------------------------------------------------------
-- TASK 1 - CTE SOLUTION
-- Here I split the task into clear steps:
-- 1. get all 2017 payments
-- 2. calculate revenue per staff
-- 3. find each staff member’s latest payment date
-- 4. find the last store connected to that payment
-- ---------------------------------------------------------
WITH payments_2017 AS (
    SELECT
        payment.payment_id,
        payment.staff_id,
        payment.amount,
        payment.payment_date,
        inventory.store_id,
        CASE
            WHEN address.address2 IS NULL OR address.address2 = '' THEN address.address
            ELSE address.address || ', ' || address.address2
        END AS store_address
    FROM public.payment AS payment
    INNER JOIN public.rental AS rental
        ON payment.rental_id = rental.rental_id
    INNER JOIN public.inventory AS inventory
        ON rental.inventory_id = inventory.inventory_id
    INNER JOIN public.store AS store
        ON inventory.store_id = store.store_id
    INNER JOIN public.address AS address
        ON store.address_id = address.address_id
    WHERE payment.payment_date >= TIMESTAMP '2017-01-01 00:00:00'
      AND payment.payment_date < TIMESTAMP '2018-01-01 00:00:00'
),
revenue_per_staff AS (
    SELECT
        payments_2017.staff_id,
        SUM(payments_2017.amount) AS revenue_2017
    FROM payments_2017
    GROUP BY payments_2017.staff_id
),
last_payment_per_staff AS (
    SELECT
        payments_2017.staff_id,
        MAX(payments_2017.payment_date) AS last_payment_date
    FROM payments_2017
    GROUP BY payments_2017.staff_id
),
last_store_per_staff AS (
    SELECT
        payments_2017.staff_id,
        MIN(payments_2017.store_id) AS last_store_id,
        MIN(payments_2017.store_address) AS last_store_address
    FROM payments_2017
    INNER JOIN last_payment_per_staff
        ON payments_2017.staff_id = last_payment_per_staff.staff_id
       AND payments_2017.payment_date = last_payment_per_staff.last_payment_date
    GROUP BY payments_2017.staff_id
)
SELECT
    staff.first_name,
    staff.last_name,
    revenue_per_staff.revenue_2017,
    last_store_per_staff.last_store_id,
    last_store_per_staff.last_store_address
FROM public.staff AS staff
INNER JOIN revenue_per_staff
    ON staff.staff_id = revenue_per_staff.staff_id
INNER JOIN last_store_per_staff
    ON staff.staff_id = last_store_per_staff.staff_id
ORDER BY
    revenue_per_staff.revenue_2017 DESC,
    staff.last_name ASC,
    staff.first_name ASC
LIMIT 3;

-- ---------------------------------------------------------
-- Advantages / disadvantages / production choice:
-- ---------------------------------------------------------

-- CTE advantages:
-- I think this is the easiest to read because I separate each step.
-- It is also easier to test each part on its own.

-- CTE disadvantages:
-- It is longer than the other versions.

-- Subquery advantages:
-- I keep the logic in one query without creating named steps.
-- It works well if I only use each intermediate result once.

-- Subquery disadvantages:
-- It is harder to debug when the logic becomes more complex.

-- JOIN advantages:
-- I still solve the task with explicit joins and clear relationships.
-- It avoids window functions and still gives the correct result.

-- JOIN disadvantages:
-- This is the least simple of the three because the "last store" rule
-- makes the logic more complex.

-- Production choice:
-- I would use the CTE solution in production because this task has
-- several business steps and the CTE version is the easiest to review,
-- test and maintain.


/* =========================================================
PART 2 - TASK 2

Conditions:
The management team wants to identify the most popular movies
and their target audience age groups to optimize marketing efforts.
Show which 5 movies were rented more than others
(number of rentals), and what's the expected age of the audience
for these movies? 

Expected output example:
title, number_of_rentals, expected_age

My understanding:
-- I count rentals for each film.
-- Then I sort from highest to lowest.
-- I use the rating column from public.film
-- to describe the expected audience age.
========================================================= */

-- ---------------------------------------------------------
-- TASK 2 - JOIN SOLUTION
-- Here I directly join film, inventory and rental
-- and count rentals for each film.
-- ---------------------------------------------------------
SELECT
    film.title,
    COUNT(rental.rental_id) AS number_of_rentals,
    CASE
        WHEN film.rating = 'G' THEN 'All ages'
        WHEN film.rating = 'PG' THEN 'Parental guidance suggested'
        WHEN film.rating = 'PG-13' THEN '13+'
        WHEN film.rating = 'R' THEN '17+'
        WHEN film.rating = 'NC-17' THEN '18+'
        ELSE 'Unknown'
    END AS expected_age
FROM public.film AS film
INNER JOIN public.inventory AS inventory
    ON film.film_id = inventory.film_id
INNER JOIN public.rental AS rental
    ON inventory.inventory_id = rental.inventory_id
GROUP BY
    film.film_id,
    film.title,
    film.rating
ORDER BY
    number_of_rentals DESC,
    film.title ASC
LIMIT 5;

-- ---------------------------------------------------------
-- TASK 2 - SUBQUERY SOLUTION
-- Here I first calculate rentals per film in a subquery,
-- and then I join that result back to the film table.
-- ---------------------------------------------------------
SELECT
    film.title,
    film_rentals.number_of_rentals,
    CASE
        WHEN film.rating = 'G' THEN 'All ages'
        WHEN film.rating = 'PG' THEN 'Parental guidance suggested'
        WHEN film.rating = 'PG-13' THEN '13+'
        WHEN film.rating = 'R' THEN '17+'
        WHEN film.rating = 'NC-17' THEN '18+'
        ELSE 'Unknown'
    END AS expected_age
FROM public.film AS film
INNER JOIN (
    SELECT
        inventory.film_id,
        COUNT(rental.rental_id) AS number_of_rentals
    FROM public.inventory AS inventory
    INNER JOIN public.rental AS rental
        ON inventory.inventory_id = rental.inventory_id
    GROUP BY inventory.film_id
) AS film_rentals
    ON film.film_id = film_rentals.film_id
ORDER BY
    film_rentals.number_of_rentals DESC,
    film.title ASC
LIMIT 5;


-- ---------------------------------------------------------
-- TASK 2 - CTE SOLUTION
-- Here I first calculate rentals per film in a CTE,
-- and then I add the expected age in the final query.
-- ---------------------------------------------------------
WITH film_rentals AS (
    SELECT
        inventory.film_id,
        COUNT(rental.rental_id) AS number_of_rentals
    FROM public.inventory AS inventory
    INNER JOIN public.rental AS rental
        ON inventory.inventory_id = rental.inventory_id
    GROUP BY inventory.film_id
)
SELECT
    film.title,
    film_rentals.number_of_rentals,
    CASE
        WHEN film.rating = 'G' THEN 'All ages'
        WHEN film.rating = 'PG' THEN 'Parental guidance suggested'
        WHEN film.rating = 'PG-13' THEN '13+'
        WHEN film.rating = 'R' THEN '17+'
        WHEN film.rating = 'NC-17' THEN '18+'
        ELSE 'Unknown'
    END AS expected_age
FROM public.film AS film
INNER JOIN film_rentals
    ON film.film_id = film_rentals.film_id
ORDER BY
    film_rentals.number_of_rentals DESC,
    film.title ASC
LIMIT 5;
-- ---------------------------------------------------------
-- Advantages / disadvantages / production choice:
-- ---------------------------------------------------------

-- CTE advantages:
-- I think this is very clear because I first calculate rentals
-- and then do the final presentation.

-- CTE disadvantages:
-- It is a little longer than the JOIN version.

-- Subquery advantages:
-- It is compact and still keeps the rental calculation separate.

-- Subquery disadvantages:
-- It is slightly less readable than a named CTE.

-- JOIN advantages:
-- I think this is the most direct solution for this task.
-- It is easy to understand because the join path is simple.

-- JOIN disadvantages:
-- If I add more business rules later, it can become harder to read.

-- Production choice:
-- I would use the JOIN solution in production because the logic is simple,
-- the table relationships are clear, and the query is easy to explain.


/* =========================================================
PART 3 - V1

Conditions:
Which actors/actresses didn't act for a longer period of time than the others?
V1: gap between the latest release_year and current year per each actor.

Expected output example:
first_name, last_name, latest_release_year, inactivity_years

My understanding:
-- I find the latest release_year for each actor.
-- Then I compare it to the current year.
-- The bigger the difference, the longer the actor has been inactive.
========================================================= */

-- ---------------------------------------------------------
-- V1 - JOIN SOLUTION
-- Here I directly join actor, film_actor, and film,
-- find the latest release year per actor,
-- and calculate the gap to the current year.
-- ---------------------------------------------------------
SELECT
    actor.first_name,
    actor.last_name,
    MAX(film.release_year) AS latest_release_year,
    EXTRACT(YEAR FROM CURRENT_DATE) - MAX(film.release_year) AS inactivity_years
FROM public.actor AS actor
INNER JOIN public.film_actor AS film_actor
    ON actor.actor_id = film_actor.actor_id
INNER JOIN public.film AS film
    ON film_actor.film_id = film.film_id
GROUP BY
    actor.actor_id,
    actor.first_name,
    actor.last_name
ORDER BY
    inactivity_years DESC,
    actor.last_name ASC,
    actor.first_name ASC;


-- ---------------------------------------------------------
-- V1 - SUBQUERY SOLUTION
-- Here I first calculate the latest release year per actor
-- in a subquery, and then I calculate inactivity in the outer query.
-- ---------------------------------------------------------
SELECT
    actor_latest_year.first_name,
    actor_latest_year.last_name,
    actor_latest_year.latest_release_year,
    EXTRACT(YEAR FROM CURRENT_DATE) - actor_latest_year.latest_release_year AS inactivity_years
FROM (
    SELECT
        actor.actor_id,
        actor.first_name,
        actor.last_name,
        MAX(film.release_year) AS latest_release_year
    FROM public.actor AS actor
    INNER JOIN public.film_actor AS film_actor
        ON actor.actor_id = film_actor.actor_id
    INNER JOIN public.film AS film
        ON film_actor.film_id = film.film_id
    GROUP BY
        actor.actor_id,
        actor.first_name,
        actor.last_name
) AS actor_latest_year
ORDER BY
    inactivity_years DESC,
    actor_latest_year.last_name ASC,
    actor_latest_year.first_name ASC;

-- ---------------------------------------------------------
-- V1 - CTE SOLUTION
-- Here I use a CTE to first get each actor’s latest release year,
-- and then calculate inactivity in the main query.
-- ---------------------------------------------------------
WITH latest_actor_year AS (
    SELECT
        actor.actor_id,
        actor.first_name,
        actor.last_name,
        MAX(film.release_year) AS latest_release_year
    FROM public.actor AS actor
    INNER JOIN public.film_actor AS film_actor
        ON actor.actor_id = film_actor.actor_id
    INNER JOIN public.film AS film
        ON film_actor.film_id = film.film_id
    GROUP BY
        actor.actor_id,
        actor.first_name,
        actor.last_name
)
SELECT
    latest_actor_year.first_name,
    latest_actor_year.last_name,
    latest_actor_year.latest_release_year,
    EXTRACT(YEAR FROM CURRENT_DATE) - latest_actor_year.latest_release_year AS inactivity_years
FROM latest_actor_year
ORDER BY
    inactivity_years DESC,
    latest_actor_year.last_name ASC,
    latest_actor_year.first_name ASC;
-- ---------------------------------------------------------
-- Advantages / disadvantages / production choice:
-- ---------------------------------------------------------

-- CTE advantages:
-- I think this is easy to read because I separate the latest year step
-- from the final inactivity calculation.

-- CTE disadvantages:
-- It is a bit longer than the JOIN version.

-- Subquery advantages:
-- It keeps the intermediate result in one place
-- and works well for a simple two-step calculation.

-- Subquery disadvantages:
-- It is less descriptive than a named CTE.

-- JOIN advantages:
-- I think this is the most direct solution.
-- It is short and easy to explain.

-- JOIN disadvantages:
-- It is a little less modular if I want to extend the logic later.

-- Production choice:
-- I would use the JOIN solution in production because the logic is simple,
-- clear, and does not need many separate steps.


/* =========================================================
PART 3 - V2

Conditions:
Which actors/actresses didn't act for a longer period of time than the others?
V2: gaps between sequential films per each actor.

Expected output example:
first_name, last_name, max_gap_years

My understanding:
-- I look at each actor’s film years in order.
-- Then I compare one year with the next year for the same actor.
-- I calculate the gap between those years.
-- Finally, I keep the biggest gap for each actor
-- and sort from highest to lowest.

Important note:
-- To avoid counting the same year more than once,
-- I first keep distinct actor-year combinations.
========================================================= */

-- ---------------------------------------------------------
-- V2 - JOIN SOLUTION
-- Here I use self-joins to find the next film year for each actor-year.
-- I also use an anti-join pattern to make sure I keep only
-- the nearest next year.
-- ---------------------------------------------------------
SELECT
    actor_year_start.first_name,
    actor_year_start.last_name,
    MAX(actor_year_next.release_year - actor_year_start.release_year) AS max_gap_years
FROM (
    SELECT DISTINCT
        actor.actor_id,
        actor.first_name,
        actor.last_name,
        film.release_year
    FROM public.actor AS actor
    INNER JOIN public.film_actor AS film_actor
        ON actor.actor_id = film_actor.actor_id
    INNER JOIN public.film AS film
        ON film_actor.film_id = film.film_id
) AS actor_year_start
INNER JOIN (
    SELECT DISTINCT
        actor.actor_id,
        actor.first_name,
        actor.last_name,
        film.release_year
    FROM public.actor AS actor
    INNER JOIN public.film_actor AS film_actor
        ON actor.actor_id = film_actor.actor_id
    INNER JOIN public.film AS film
        ON film_actor.film_id = film.film_id
) AS actor_year_next
    ON actor_year_start.actor_id = actor_year_next.actor_id
   AND actor_year_next.release_year > actor_year_start.release_year
LEFT JOIN (
    SELECT DISTINCT
        actor.actor_id,
        film.release_year
    FROM public.actor AS actor
    INNER JOIN public.film_actor AS film_actor
        ON actor.actor_id = film_actor.actor_id
    INNER JOIN public.film AS film
        ON film_actor.film_id = film.film_id
) AS actor_year_between
    ON actor_year_start.actor_id = actor_year_between.actor_id
   AND actor_year_between.release_year > actor_year_start.release_year
   AND actor_year_between.release_year < actor_year_next.release_year
WHERE actor_year_between.actor_id IS NULL
GROUP BY
    actor_year_start.actor_id,
    actor_year_start.first_name,
    actor_year_start.last_name
ORDER BY
    max_gap_years DESC,
    actor_year_start.last_name ASC,
    actor_year_start.first_name ASC;



-- ---------------------------------------------------------
-- V2 - SUBQUERY SOLUTION
-- Here I first find the next release year for each actor-year
-- using a correlated subquery,
-- and then I calculate the biggest gap per actor.
-- ---------------------------------------------------------
SELECT
    actor_year_gaps.first_name,
    actor_year_gaps.last_name,
    MAX(actor_year_gaps.next_release_year - actor_year_gaps.release_year) AS max_gap_years
FROM (
    SELECT
        actor.actor_id,
        actor.first_name,
        actor.last_name,
        actor_years.release_year,
        (
            SELECT MIN(next_actor_year.release_year)
            FROM (
                SELECT DISTINCT
                    film_actor_inner.actor_id,
                    film_inner.release_year
                FROM public.film_actor AS film_actor_inner
                INNER JOIN public.film AS film_inner
                    ON film_actor_inner.film_id = film_inner.film_id
            ) AS next_actor_year
            WHERE next_actor_year.actor_id = actor.actor_id
              AND next_actor_year.release_year > actor_years.release_year
        ) AS next_release_year
    FROM public.actor AS actor
    INNER JOIN (
        SELECT DISTINCT
            film_actor.actor_id,
            film.release_year
        FROM public.film_actor AS film_actor
        INNER JOIN public.film AS film
            ON film_actor.film_id = film.film_id
    ) AS actor_years
        ON actor.actor_id = actor_years.actor_id
) AS actor_year_gaps
WHERE actor_year_gaps.next_release_year IS NOT NULL
GROUP BY
    actor_year_gaps.actor_id,
    actor_year_gaps.first_name,
    actor_year_gaps.last_name
ORDER BY
    max_gap_years DESC,
    actor_year_gaps.last_name ASC,
    actor_year_gaps.first_name ASC;
-- ---------------------------------------------------------
-- V2 - CTE SOLUTION
-- Here I split the logic into steps:
-- 1. get distinct actor-year rows
-- 2. find the next release year for each row
-- 3. calculate the biggest gap for each actor
-- ---------------------------------------------------------
WITH actor_years AS (
    SELECT DISTINCT
        actor.actor_id,
        actor.first_name,
        actor.last_name,
        film.release_year
    FROM public.actor AS actor
    INNER JOIN public.film_actor AS film_actor
        ON actor.actor_id = film_actor.actor_id
    INNER JOIN public.film AS film
        ON film_actor.film_id = film.film_id
),
next_years AS (
    SELECT
        actor_years.actor_id,
        actor_years.first_name,
        actor_years.last_name,
        actor_years.release_year,
        (
            SELECT MIN(actor_years_next.release_year)
            FROM actor_years AS actor_years_next
            WHERE actor_years_next.actor_id = actor_years.actor_id
              AND actor_years_next.release_year > actor_years.release_year
        ) AS next_release_year
    FROM actor_years
),
gaps AS (
    SELECT
        next_years.actor_id,
        next_years.first_name,
        next_years.last_name,
        next_years.next_release_year - next_years.release_year AS gap_years
    FROM next_years
    WHERE next_years.next_release_year IS NOT NULL
)
SELECT
    gaps.first_name,
    gaps.last_name,
    MAX(gaps.gap_years) AS max_gap_years
FROM gaps
GROUP BY
    gaps.actor_id,
    gaps.first_name,
    gaps.last_name
ORDER BY
    max_gap_years DESC,
    gaps.last_name ASC,
    gaps.first_name ASC;

-- ---------------------------------------------------------
-- Advantages / disadvantages / production choice:
-- ---------------------------------------------------------

-- CTE advantages:
-- I think this is the clearest version for this task
-- because the sequential logic is split into understandable steps.

-- CTE disadvantages:
-- It is the longest version.

-- Subquery advantages:
-- It solves the problem without window functions
-- and still keeps the logic close to the data.

-- Subquery disadvantages:
-- Correlated subqueries can be harder to read and may be slower
-- on larger datasets.

-- JOIN advantages:
-- I can solve the task using explicit joins and an anti-join approach.
-- It avoids window functions and still finds the next sequential year.

-- JOIN disadvantages:
-- I think this is the hardest version to read.
-- It is less natural than the CTE version for this kind of sequential logic.

-- Production choice:
-- I would use the CTE solution in production because this task is more complex,
-- and the CTE version is the easiest to explain, test  and maintain.

-- Note:
-- A pure JOIN-only solution is less natural for this task because
-- finding the nearest next year is a sequential problem.
-- I still provided a JOIN-based version, but I think the CTE version
-- is much better for readability.