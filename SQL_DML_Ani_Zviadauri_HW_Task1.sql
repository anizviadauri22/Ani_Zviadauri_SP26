/* =========================================================
TASK 1
   ========================================================= */


/* ---------------------------------------------------------
   STEP 1 — I'm inserting my 3 favourite films into public.film

   Why a separate transaction?
   I put this in its own transaction so that if something goes
   wrong here, only this step rolls back - the actor and
   inventory work I do later stays safe.

   What happens if this transaction fails?
   Nothing gets inserted into the film table. Since I look up
   film_id by title + year in every later step (never by a
   hard-coded number), I can just fix the problem and re-run
   without touching anything else.

   Is rollback possible?
   Yes, right up until the COMMIT at the end of this block.

   How do I avoid duplicates?
   I use WHERE NOT EXISTS checking both title and release_year
   together. That's the natural business key for a film.

   How do I keep referential integrity?
   I look up language_id live from public.language instead of
   hard-coding the number. That way it always points to a real row.

   Why INSERT … SELECT instead of INSERT … VALUES?
   With INSERT … SELECT I can resolve the language_id on the fly
   inside the same query. If I used VALUES I'd have to hard-code
   the integer, which breaks if the database is restored on a
   different system. INSERT … SELECT is also easier to extend —
   I just add another row to the UNION ALL.

   My 3 films (different years, different genres):
     La La Land (2016)               — Musical/Romance, rate  4.99, 1 week
     Into the Wild (2007)            — Adventure/Drama, rate  9.99, 2 weeks
     The Shawshank Redemption (1994) — Drama,           rate 19.99, 3 weeks
   --------------------------------------------------------- */

BEGIN;

WITH language_english AS (
    -- I look up the English language_id dynamically so I never
    -- hard-code a foreign key integer.
    SELECT language_table.language_id
    FROM   public.language AS language_table
    WHERE  UPPER(language_table.name) = UPPER('English')
    LIMIT  1
),
films_to_add AS (
    -- I define all three films in one place so a single INSERT
    -- handles them all. Much cleaner than three separate statements.
    SELECT
        UPPER('La La Land')::TEXT AS title,
        UPPER(
            'A jazz musician and an aspiring actress fall in love while chasing their dreams in Los Angeles.'
        )::TEXT AS description,
        2016::public."year" AS release_year,
        7::INT AS rental_duration,
        4.99::NUMERIC(4,2) AS rental_rate,
        128::INT AS length,
        24.99::NUMERIC(5,2) AS replacement_cost,
        'PG-13'::public.mpaa_rating AS rating,
        ARRAY[
            UPPER('Trailers'),
            UPPER('Deleted Scenes'),
            UPPER('Behind the Scenes')
        ]::TEXT[] AS special_features

    UNION ALL

    SELECT
        UPPER('Into the Wild')::TEXT,
        UPPER(
            'After graduating from Emory University, Christopher McCandless gives up everything and hitchhikes to the Alaskan wilderness.'
        )::TEXT,
        2007::public."year",
        14::INT,
        9.99::NUMERIC(4,2),
        148::INT,
        27.99::NUMERIC(5,2),
        'R'::public.mpaa_rating,
        ARRAY[
            UPPER('Trailers'),
            UPPER('Commentaries'),
            UPPER('Behind the Scenes')
        ]::TEXT[]

    UNION ALL

    SELECT
        UPPER('The Shawshank Redemption')::TEXT,
        UPPER(
            'Two imprisoned men build a deep friendship and find hope and redemption through small acts of decency over the years.'
        )::TEXT,
        1994::public."year",
        21::INT,
        19.99::NUMERIC(4,2),
        142::INT,
        29.99::NUMERIC(5,2),
        'R'::public.mpaa_rating,
        ARRAY[
            UPPER('Trailers'),
            UPPER('Commentaries'),
            UPPER('Deleted Scenes')
        ]::TEXT[]
)
INSERT INTO public.film
(
    title, description, release_year, language_id,
    rental_duration, rental_rate, length,
    replacement_cost, rating, last_update, special_features
)
SELECT
    film_source.title,
    film_source.description,
    film_source.release_year,
    language_source.language_id,
    film_source.rental_duration,
    film_source.rental_rate,
    film_source.length,
    film_source.replacement_cost,
    film_source.rating,
    current_date,
    film_source.special_features
FROM   films_to_add AS film_source
CROSS  JOIN language_english AS language_source
-- I only insert a film if it doesn't already exist (title + year).
WHERE NOT EXISTS (
    SELECT 1
    FROM   public.film AS existing_film
    WHERE  UPPER(existing_film.title) = UPPER(film_source.title)
      AND  existing_film.release_year::INT = film_source.release_year::INT
)
RETURNING
    film_id,
    UPPER(title) AS title,
    release_year,
    rental_duration,
    rental_rate,
    replacement_cost;

COMMIT;


/* ---------------------------------------------------------
   STEP 2 — I'm linking each film to its genre in public.film_category

   Why a separate transaction?
   Category linkage depends on Step 1 being committed first.
   Keeping it separate means a typo in a category name only
   rolls back this step, not the films I already saved.

   What happens if it fails?
   The films stay in the database but won't have a category.
   I can fix the category name and re-run just this block.

   How do I avoid duplicates?
   I check WHERE NOT EXISTS on (film_id, category_id), which
   is the composite primary key of film_category.

   How do I keep referential integrity?
   Both film_id and category_id are resolved by joining to
   the live film and category tables — no hard-coded integers.

   Categories I'm using (I confirmed these exist in the DB):
     La La Land               -> Music  (row 12)
     Into the Wild            -> Travel (row 16)
     The Shawshank Redemption -> Drama  (row 7)
   --------------------------------------------------------- */

BEGIN;

WITH film_category_map AS (
    -- My mapping of film to category using natural names, not IDs.
    SELECT UPPER('La La Land')::TEXT AS title, 2016::INT AS release_year, UPPER('Music')::TEXT AS category_name
    UNION ALL
    SELECT UPPER('Into the Wild')::TEXT, 2007::INT, UPPER('Travel')::TEXT
    UNION ALL
    SELECT UPPER('The Shawshank Redemption')::TEXT, 1994::INT, UPPER('Drama')::TEXT
),
resolved_category_rows AS (
    -- Here I join to the real tables to get the integer IDs.
    -- No numbers are hard-coded anywhere.
    SELECT
        film_table.film_id,
        category_table.category_id
    FROM   film_category_map AS film_category_source
    INNER  JOIN public.film AS film_table
            ON UPPER(film_table.title) = UPPER(film_category_source.title)
           AND film_table.release_year::INT = film_category_source.release_year
    INNER  JOIN public.category AS category_table
            ON UPPER(category_table.name) = UPPER(film_category_source.category_name)
)
INSERT INTO public.film_category (film_id, category_id, last_update)
SELECT
    resolved_category_rows.film_id,
    resolved_category_rows.category_id,
    current_date
FROM   resolved_category_rows
WHERE NOT EXISTS (
    SELECT 1
    FROM   public.film_category AS existing_film_category
    WHERE  existing_film_category.film_id     = resolved_category_rows.film_id
      AND  existing_film_category.category_id = resolved_category_rows.category_id
)
RETURNING film_id, category_id, last_update;

COMMIT;


/* ---------------------------------------------------------
   STEP 3 — I'm inserting the leading actors into public.actor

   Why a separate transaction?
   Actors are shared reference data. If this step fails for
   some reason, my films (already committed) are unaffected.
   I can fix and re-run this block on its own.

   What happens if it fails?
   No actors are inserted. Steps 4 and 12 will simply find
   zero matching actor rows and insert nothing, which is safe.

   How do I avoid duplicates?
   I check WHERE NOT EXISTS on (first_name, last_name) — the
   natural unique key for an actor in this database. If an
   actor already exists I skip them silently, and the film_actor
   step later picks up the existing row via JOIN.

   My 6 actors (2 per film, meeting the minimum of 6 required):
     La La Land               — Ryan Gosling, Emma Stone
     Into the Wild            — Emile Hirsch, Kristen Stewart
     The Shawshank Redemption — Tim Robbins, Morgan Freeman
   --------------------------------------------------------- */

BEGIN;

WITH actors_to_add AS (
    SELECT UPPER('RYAN')::TEXT AS first_name, UPPER('GOSLING')::TEXT AS last_name
    UNION ALL SELECT UPPER('EMMA')::TEXT,    UPPER('STONE')::TEXT
    UNION ALL SELECT UPPER('EMILE')::TEXT,   UPPER('HIRSCH')::TEXT
    UNION ALL SELECT UPPER('KRISTEN')::TEXT, UPPER('STEWART')::TEXT
    UNION ALL SELECT UPPER('TIM')::TEXT,     UPPER('ROBBINS')::TEXT
    UNION ALL SELECT UPPER('MORGAN')::TEXT,  UPPER('FREEMAN')::TEXT
)
INSERT INTO public.actor (first_name, last_name, last_update)
SELECT
    UPPER(actor_source.first_name),
    UPPER(actor_source.last_name),
    current_date
FROM   actors_to_add AS actor_source
-- I only insert if this exact name doesn't already exist.
WHERE NOT EXISTS (
    SELECT 1
    FROM   public.actor AS existing_actor
    WHERE  UPPER(existing_actor.first_name) = UPPER(actor_source.first_name)
      AND  UPPER(existing_actor.last_name)  = UPPER(actor_source.last_name)
)
RETURNING
    actor_id,
    UPPER(first_name) AS first_name,
    UPPER(last_name) AS last_name,
    last_update;

COMMIT;


/* ---------------------------------------------------------
   STEP 4 — I'm linking actors to films in public.film_actor

   Why a separate transaction?
   This step can only run after both Step 1 (films) and Step 3
   (actors) are committed. Keeping it separate makes that
   dependency clear and lets me re-run just this block if
   the JOIN resolves differently than expected.

   What happens if it fails?
   No film_actor rows are created. Films and actors remain in
   the database untouched. I can re-run this block alone.

   How do I avoid duplicates?
   I check WHERE NOT EXISTS on (actor_id, film_id), which is
   the composite primary key of film_actor.

   How do I keep referential integrity?
   Both film_id and actor_id are resolved by joining to the
   live film and actor tables. I never hard-code an ID.
   --------------------------------------------------------- */

BEGIN;

WITH film_actor_map AS (
    -- I list every actor-film pairing using names, not IDs.
    SELECT UPPER('La La Land')::TEXT AS title, 2016::INT AS release_year, UPPER('RYAN')::TEXT AS actor_first_name, UPPER('GOSLING')::TEXT AS actor_last_name
    UNION ALL SELECT UPPER('La La Land')::TEXT, 2016::INT, UPPER('EMMA')::TEXT, UPPER('STONE')::TEXT
    UNION ALL SELECT UPPER('Into the Wild')::TEXT, 2007::INT, UPPER('EMILE')::TEXT, UPPER('HIRSCH')::TEXT
    UNION ALL SELECT UPPER('Into the Wild')::TEXT, 2007::INT, UPPER('KRISTEN')::TEXT, UPPER('STEWART')::TEXT
    UNION ALL SELECT UPPER('The Shawshank Redemption')::TEXT, 1994::INT, UPPER('TIM')::TEXT, UPPER('ROBBINS')::TEXT
    UNION ALL SELECT UPPER('The Shawshank Redemption')::TEXT, 1994::INT, UPPER('MORGAN')::TEXT, UPPER('FREEMAN')::TEXT
),
resolved_film_actor_rows AS (
    -- Here I resolve the real integer IDs from the live tables.
    SELECT
        film_table.film_id,
        actor_table.actor_id
    FROM   film_actor_map AS film_actor_source
    INNER  JOIN public.film AS film_table
            ON UPPER(film_table.title) = UPPER(film_actor_source.title)
           AND film_table.release_year::INT = film_actor_source.release_year
    INNER  JOIN public.actor AS actor_table
            ON UPPER(actor_table.first_name) = UPPER(film_actor_source.actor_first_name)
           AND UPPER(actor_table.last_name)  = UPPER(film_actor_source.actor_last_name)
)
INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT
    resolved_film_actor_rows.actor_id,
    resolved_film_actor_rows.film_id,
    current_date
FROM   resolved_film_actor_rows
WHERE NOT EXISTS (
    SELECT 1
    FROM   public.film_actor AS existing_film_actor
    WHERE  existing_film_actor.actor_id = resolved_film_actor_rows.actor_id
      AND  existing_film_actor.film_id  = resolved_film_actor_rows.film_id
)
RETURNING actor_id, film_id, last_update;

COMMIT;


/* ---------------------------------------------------------
   STEP 5 — I'm adding my films to store 1's inventory

   Why a separate transaction?
   Inventory is a separate concern from film metadata. If
   something goes wrong here I don't want to roll back the
   films and actors I already committed.

   What happens if it fails?
   No inventory rows are created. The films still exist in
   the film table; I just can't rent them yet. Re-running
   this block after fixing the issue is completely safe.

   How do I avoid duplicates?
   I check WHERE NOT EXISTS on (film_id, store_id) so I only
   ever add one copy of each film per store.

   How do I keep referential integrity?
   film_id is resolved by joining to the live film table.

   Why store 1?
   The task says "any store's inventory" so I chose store 1.
   In Step 11 I make sure to look up inventory from store 1
   specifically so the rental step always finds these rows.
   --------------------------------------------------------- */

BEGIN;

WITH target_films AS (
    -- I look up the film_ids using title + year, no hard-coding.
    SELECT film_table.film_id
    FROM   public.film AS film_table
    WHERE  (UPPER(film_table.title) = UPPER('La La Land')              AND film_table.release_year::INT = 2016)
        OR (UPPER(film_table.title) = UPPER('Into the Wild')            AND film_table.release_year::INT = 2007)
        OR (UPPER(film_table.title) = UPPER('The Shawshank Redemption') AND film_table.release_year::INT = 1994)
)
INSERT INTO public.inventory (film_id, store_id, last_update)
SELECT
    target_films.film_id,
    1,
    current_date
FROM   target_films
WHERE NOT EXISTS (
    SELECT 1
    FROM   public.inventory AS existing_inventory
    WHERE  existing_inventory.film_id  = target_films.film_id
      AND  existing_inventory.store_id = 1
)
RETURNING inventory_id, film_id, store_id, last_update;

COMMIT;


/* ---------------------------------------------------------
   STEP 6 — I'm checking which customer qualifies before I
             overwrite their data

   This is a read-only SELECT. I run it to confirm the
   customer I'm about to update really does have at least
   43 rentals and 43 payments. It's my safety check before
   I commit any changes.
   --------------------------------------------------------- */

BEGIN;

SELECT
    customer_table.customer_id,
    UPPER(customer_table.first_name) AS first_name,
    UPPER(customer_table.last_name)  AS last_name,
    LOWER(customer_table.email)      AS email,
    COUNT(DISTINCT rental_table.rental_id)  AS rental_count,
    COUNT(DISTINCT payment_table.payment_id) AS payment_count
FROM   public.customer AS customer_table
LEFT   JOIN public.rental AS rental_table
       ON rental_table.customer_id = customer_table.customer_id
LEFT   JOIN public.payment AS payment_table
       ON payment_table.customer_id = customer_table.customer_id
GROUP  BY
       customer_table.customer_id,
       customer_table.first_name,
       customer_table.last_name,
       customer_table.email
HAVING COUNT(DISTINCT rental_table.rental_id)  >= 43
   AND COUNT(DISTINCT payment_table.payment_id) >= 43
ORDER  BY customer_table.customer_id
LIMIT  5;

COMMIT;


/* ---------------------------------------------------------
   STEP 7 — I'm replacing a qualifying customer's data with mine

   Why a separate transaction?
   The UPDATE changes personal data. If I make a mistake I
   want to be able to roll back just this step without
   affecting rentals or payments that come later.

   What happens if it fails?
   No customer row is changed. The DELETE steps below will
   find zero rows matching my name and skip cleanly.

   Is rollback possible?
   Yes — until COMMIT. The RETURNING clause lets me inspect
   what was actually written before I decide to commit.

   How do I avoid unintended changes?
   The target_customer CTE picks exactly 1 row (LIMIT 1)
   so only one customer is ever updated.

   Note on the address:
   I'm reusing an existing address_id. The task says not to
   touch the address table, so I just point my customer row
   at an address that already exists.
   --------------------------------------------------------- */

BEGIN;

WITH target_customer AS (
    -- I pick the customer with the lowest customer_id who
    -- meets the 43-rental / 43-payment threshold.
    SELECT customer_table.customer_id
    FROM   public.customer AS customer_table
    LEFT   JOIN public.rental AS rental_table
           ON rental_table.customer_id = customer_table.customer_id
    LEFT   JOIN public.payment AS payment_table
           ON payment_table.customer_id = customer_table.customer_id
    GROUP  BY customer_table.customer_id
    HAVING COUNT(DISTINCT rental_table.rental_id)  >= 43
       AND COUNT(DISTINCT payment_table.payment_id) >= 43
    ORDER  BY customer_table.customer_id
    LIMIT  1
),
target_address AS (
    -- I grab the lowest address_id that already exists so I
    -- don't need to create or modify any address row.
    SELECT address_table.address_id
    FROM   public.address AS address_table
    ORDER  BY address_table.address_id
    LIMIT  1
)
UPDATE public.customer AS customer_table
SET
    first_name  = UPPER('Ani'),
    last_name   = UPPER('Zviadauri'),
    email       = LOWER('ani.zviadauri@example.com'),
    address_id  = target_address.address_id,
    activebool  = TRUE,
    active      = 1,
    last_update = current_date
FROM   target_customer
CROSS  JOIN target_address
WHERE  customer_table.customer_id = target_customer.customer_id
RETURNING
    customer_table.customer_id,
    UPPER(customer_table.first_name) AS first_name,
    UPPER(customer_table.last_name)  AS last_name,
    LOWER(customer_table.email)      AS email,
    customer_table.address_id,
    customer_table.store_id,
    customer_table.last_update;

COMMIT;


/* ---------------------------------------------------------
   STEP 8 — I'm verifying what I'm about to delete

   Before I run any DELETE I want to see exactly how many
   rows belong to me. This is my double-check so I don't
   accidentally remove data I didn't intend to touch.
   The task requires this verification step before committing
   any deletions.
   --------------------------------------------------------- */

BEGIN;

WITH me AS (
    SELECT customer_table.customer_id
    FROM   public.customer AS customer_table
    WHERE  UPPER(customer_table.first_name) = UPPER('Ani')
      AND  UPPER(customer_table.last_name)  = UPPER('Zviadauri')
    LIMIT  1
)
SELECT UPPER('payment') AS table_name, COUNT(*) AS rows_to_delete
FROM   public.payment AS payment_table
INNER  JOIN me ON payment_table.customer_id = me.customer_id

UNION ALL

SELECT UPPER('rental') AS table_name, COUNT(*) AS rows_to_delete
FROM   public.rental AS rental_table
INNER  JOIN me ON rental_table.customer_id = me.customer_id;

COMMIT;


/* ---------------------------------------------------------
   STEP 9 — I'm deleting the old payment records that belong to me

   Why a separate transaction?
   Keeping the delete of payments separate from the delete of
   rentals makes the dependency order explicit and gives me a
   clean rollback point between the two.

   Why payments before rentals?
   public.payment.rental_id has a foreign key pointing to
   public.rental. If I tried to delete a rental row that still
   has a child payment row, PostgreSQL would throw an FK
   violation. So I must remove payments first.

   Is this safe to delete?
   Yes. I scope the DELETE to exactly my customer_id using the
   CTE. No other customer's payments are touched at all. I also
   ran the verification SELECT in Step 8 first, so I know
   exactly how many rows I'm removing.

   Is rollback possible?
   Yes — until COMMIT. If I see something unexpected in the
   RETURNING output I can roll back before committing.
   --------------------------------------------------------- */

BEGIN;

WITH me AS (
    -- I resolve my customer_id by name so I never hard-code an integer.
    SELECT customer_table.customer_id
    FROM   public.customer AS customer_table
    WHERE  UPPER(customer_table.first_name) = UPPER('Ani')
      AND  UPPER(customer_table.last_name)  = UPPER('Zviadauri')
    LIMIT  1
)
DELETE FROM public.payment AS payment_table
USING  me
WHERE  payment_table.customer_id = me.customer_id
RETURNING
    payment_table.payment_id,
    payment_table.customer_id,
    payment_table.rental_id,
    payment_table.amount,
    payment_table.payment_date;

COMMIT;


/* ---------------------------------------------------------
   STEP 10 — I'm deleting the old rental records that belong to me

   Why is this safe now?
   I deleted all my payment rows in Step 9, so there are no
   remaining foreign-key references pointing at my rental rows.
   PostgreSQL will let me remove them without an FK error.

   Is rollback possible?
   Yes — until COMMIT. The RETURNING clause shows me every row
   that was actually deleted so I can verify before committing.

   What data would be affected by a rollback?
   Only my rental rows. Nothing else in the database is touched
   by this DELETE.
   --------------------------------------------------------- */

BEGIN;

WITH me AS (
    SELECT customer_table.customer_id
    FROM   public.customer AS customer_table
    WHERE  UPPER(customer_table.first_name) = UPPER('Ani')
      AND  UPPER(customer_table.last_name)  = UPPER('Zviadauri')
    LIMIT  1
)
DELETE FROM public.rental AS rental_table
USING  me
WHERE  rental_table.customer_id = me.customer_id
RETURNING
    rental_table.rental_id,
    rental_table.customer_id,
    rental_table.inventory_id,
    rental_table.rental_date,
    rental_table.return_date;

COMMIT;


/* ---------------------------------------------------------
   STEP 11 — I'm inserting new rentals for my 3 favourite films

   Why a separate transaction?
   The new rentals are a fresh business event that should only
   happen after the old ones are fully deleted and committed.
   Keeping it separate makes that order clear and safe.

   What happens if it fails?
   No new rental rows are created. My customer row still exists
   and the inventory rows are still there. I can re-run this
   block safely because the WHERE NOT EXISTS guard prevents
   duplicates.

   How do I avoid duplicates?
   I check WHERE NOT EXISTS on (customer_id, inventory_id,
   rental_date). That combination uniquely identifies a rental.

   How do I keep referential integrity?
   customer_id, inventory_id and staff_id are all resolved by
   joining to live tables — I never hard-code an integer ID.

   Why do I join inventory to store 1 specifically?
   I added the inventory to store 1 in Step 5. If I joined on
   the customer's own store_id instead, and the customer
   happened to belong to store 2, I'd get zero results. Pinning
   the inventory lookup to store 1 keeps Steps 5 and 11 consistent.

   Why are dates in the first half of 2017?
   The payment table is partitioned by date and the existing
   partitions cover the first half of 2017. Dates outside that
   range would cause the payment insert in Step 12 to fail.
   --------------------------------------------------------- */

BEGIN;

WITH me AS (
    SELECT customer_table.customer_id
    FROM   public.customer AS customer_table
    WHERE  UPPER(customer_table.first_name) = UPPER('Ani')
      AND  UPPER(customer_table.last_name)  = UPPER('Zviadauri')
    LIMIT  1
),
film_inventory AS (
    -- I look up inventory rows for my films specifically from
    -- store 1, where I added them in Step 5.
    SELECT
        UPPER(film_table.title) AS title,
        film_table.release_year::INT AS release_year,
        inventory_table.inventory_id,
        inventory_table.store_id
    FROM   public.film AS film_table
    INNER  JOIN public.inventory AS inventory_table
            ON inventory_table.film_id  = film_table.film_id
           AND inventory_table.store_id = 1
    WHERE  (UPPER(film_table.title) = UPPER('La La Land')              AND film_table.release_year::INT = 2016)
        OR (UPPER(film_table.title) = UPPER('Into the Wild')            AND film_table.release_year::INT = 2007)
        OR (UPPER(film_table.title) = UPPER('The Shawshank Redemption') AND film_table.release_year::INT = 1994)
),
store_staff AS (
    -- I use the store manager as the staff member for each rental.
    SELECT store_table.store_id, store_table.manager_staff_id AS staff_id
    FROM   public.store AS store_table
    WHERE  store_table.store_id = 1
),
rentals_to_add AS (
    SELECT
        me.customer_id,
        film_inventory.inventory_id,
        store_staff.staff_id,
        -- I assign a distinct rental date per film so each row is
        -- uniquely identifiable and falls inside the 2017 partition.
        CASE UPPER(film_inventory.title)
            WHEN UPPER('La La Land')              THEN TIMESTAMP '2017-01-10 10:00:00'
            WHEN UPPER('Into the Wild')            THEN TIMESTAMP '2017-02-11 11:00:00'
            WHEN UPPER('The Shawshank Redemption') THEN TIMESTAMP '2017-03-12 12:00:00'
        END AS rental_date,
        CASE UPPER(film_inventory.title)
            WHEN UPPER('La La Land')              THEN TIMESTAMP '2017-01-17 10:00:00'  -- 1 week later
            WHEN UPPER('Into the Wild')            THEN TIMESTAMP '2017-02-25 11:00:00'  -- 2 weeks later
            WHEN UPPER('The Shawshank Redemption') THEN TIMESTAMP '2017-04-02 12:00:00'  -- 3 weeks later
        END AS return_date
    FROM   me
    CROSS  JOIN film_inventory
    INNER  JOIN store_staff
            ON store_staff.store_id = film_inventory.store_id
)
INSERT INTO public.rental
    (rental_date, inventory_id, customer_id, return_date, staff_id, last_update)
SELECT
    rental_source.rental_date,
    rental_source.inventory_id,
    rental_source.customer_id,
    rental_source.return_date,
    rental_source.staff_id,
    current_date
FROM   rentals_to_add AS rental_source
WHERE NOT EXISTS (
    SELECT 1
    FROM   public.rental AS existing_rental
    WHERE  existing_rental.customer_id  = rental_source.customer_id
      AND  existing_rental.inventory_id = rental_source.inventory_id
      AND  existing_rental.rental_date  = rental_source.rental_date
)
RETURNING
    rental_id, rental_date, inventory_id,
    customer_id, return_date, staff_id, last_update;

COMMIT;


/* ---------------------------------------------------------
   STEP 12 — I'm inserting payments for the rentals I just created

   Why a separate transaction?
   The payment rows need rental_ids that only exist after
   Step 11 is committed. Keeping this separate makes the
   dependency explicit and lets me re-run safely.

   What happens if it fails?
   No payment rows are created. The rental rows from Step 11
   remain intact. Re-running this block after fixing the issue
   is safe because the WHERE NOT EXISTS guard prevents double
   payments.

   How do I avoid duplicates?
   I check WHERE NOT EXISTS on rental_id. Each rental should
   have exactly one payment.

   Important fix — AND/OR precedence:
   In my earlier draft the AND rental_date IN (...) at the
   bottom only applied to the last OR branch (Shawshank),
   which was a logic bug. I've fixed this by wrapping all
   three OR conditions in outer parentheses so the AND filter
   applies to all three films together.

   Payment amount:
   I use each film's rental_rate as the payment amount, which
   matches the natural business logic — the customer pays what
   the film is listed at.
   --------------------------------------------------------- */

BEGIN;

WITH me AS (
    SELECT customer_table.customer_id
    FROM   public.customer AS customer_table
    WHERE  UPPER(customer_table.first_name) = UPPER('Ani')
      AND  UPPER(customer_table.last_name)  = UPPER('Zviadauri')
    LIMIT  1
),
target_rentals AS (
    -- I join through inventory to get the film and its rental_rate,
    -- then filter to only the three specific rental dates I used in
    -- Step 11. The outer parentheses around the OR block make sure
    -- the AND rental_date filter applies to all three films, not
    -- just the last one.
    SELECT
        rental_table.rental_id,
        rental_table.customer_id,
        rental_table.staff_id,
        rental_table.rental_date,
        UPPER(film_table.title) AS title,
        film_table.rental_rate
    FROM   public.rental AS rental_table
    INNER  JOIN public.inventory AS inventory_table
            ON inventory_table.inventory_id = rental_table.inventory_id
    INNER  JOIN public.film AS film_table
            ON film_table.film_id = inventory_table.film_id
    INNER  JOIN me
            ON me.customer_id = rental_table.customer_id
    WHERE (
            (UPPER(film_table.title) = UPPER('La La Land')              AND film_table.release_year::INT = 2016)
         OR (UPPER(film_table.title) = UPPER('Into the Wild')            AND film_table.release_year::INT = 2007)
         OR (UPPER(film_table.title) = UPPER('The Shawshank Redemption') AND film_table.release_year::INT = 1994)
          )
      AND rental_table.rental_date IN (
              TIMESTAMP '2017-01-10 10:00:00',
              TIMESTAMP '2017-02-11 11:00:00',
              TIMESTAMP '2017-03-12 12:00:00'
          )
)
INSERT INTO public.payment
    (customer_id, staff_id, rental_id, amount, payment_date)
SELECT
    target_rentals.customer_id,
    target_rentals.staff_id,
    target_rentals.rental_id,
    target_rentals.rental_rate,
    target_rentals.rental_date + INTERVAL '1 hour'   -- paid one hour after picking up the film
FROM   target_rentals
WHERE NOT EXISTS (
    SELECT 1
    FROM   public.payment AS existing_payment
    WHERE  existing_payment.rental_id = target_rentals.rental_id
)
RETURNING
    payment_id, customer_id, staff_id,
    rental_id, amount, payment_date;

COMMIT;