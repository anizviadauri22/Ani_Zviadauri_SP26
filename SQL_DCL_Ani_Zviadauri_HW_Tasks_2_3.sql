
-- ============================================================
-- TASK 2. ROLE-BASED AUTHENTICATION MODEL
-- ============================================================

-- I create rentaluser with a password and only the ability to connect.
-- No table permissions are given yet.
CREATE USER rentaluser WITH PASSWORD 'rentalpassword';
GRANT CONNECT ON DATABASE dvdrental TO rentaluser;

-- I also grant usage on the public schema so rentaluser can see the tables inside it.
-- Without this, even a SELECT grant on a table would be blocked.
GRANT USAGE ON SCHEMA public TO rentaluser;


-- I grant rentaluser the ability to read the customer table.
GRANT SELECT ON TABLE public.customer TO rentaluser;

-- I verify the grant was created.
SELECT
    table_grants.grantee,
    table_grants.table_schema,
    table_grants.table_name,
    table_grants.privilege_type
FROM information_schema.role_table_grants AS table_grants
WHERE
    LOWER(table_grants.table_schema) = LOWER('public')
    AND LOWER(table_grants.table_name) = LOWER('customer')
    AND LOWER(table_grants.grantee) = LOWER('rentaluser');

-- I test that rentaluser can read the customer table.
-- IMPORTANT: this test must be executed as rentaluser.
-- I first run: SET ROLE rentaluser;
-- If I do not switch the role, PostgreSQL will execute the query as the current user
-- such as postgres, and no permission error will be shown because the superuser bypasses restrictions.
SET ROLE rentaluser;

SELECT
    customer.customer_id,
    LOWER(customer.first_name) AS first_name,
    LOWER(customer.last_name) AS last_name,
    LOWER(customer.email) AS email
FROM public.customer AS customer;
-- Expected: all rows from customer are returned

RESET ROLE;


-- I create the rental group role and add rentaluser to it.
CREATE ROLE rental;
GRANT rental TO rentaluser;

-- I verify the membership.
SELECT
    group_role.rolname AS granted_role,
    member_role.rolname AS member_role
FROM pg_auth_members AS auth_members
INNER JOIN pg_roles AS group_role
    ON group_role.oid = auth_members.roleid
INNER JOIN pg_roles AS member_role
    ON member_role.oid = auth_members.member
WHERE LOWER(group_role.rolname) = LOWER('rental');


-- I give the rental group INSERT and UPDATE on the rental table.
GRANT INSERT, UPDATE ON TABLE public.rental TO rental;

-- I also grant usage on the sequence so INSERT can generate a new rental_id.
GRANT USAGE, SELECT ON SEQUENCE public.rental_rental_id_seq TO rental;


-- I test INSERT as rentaluser. This should succeed.
-- IMPORTANT: I must switch to rentaluser before testing.
SET ROLE rentaluser;

INSERT INTO public.rental (
    rental_date,
    inventory_id,
    customer_id,
    staff_id,
    return_date,
    last_update
)
VALUES (
    NOW(),
    1,
    1,
    1,
    NULL,
    NOW()
);
-- Expected: INSERT 0 1

-- I test UPDATE as rentaluser. This should also succeed.
UPDATE public.rental
SET return_date = NOW()
WHERE rental_id = (
    SELECT MAX(rental.rental_id)
    FROM public.rental AS rental
);
-- Expected: UPDATE 1

RESET ROLE;


-- I revoke INSERT from the rental group.
REVOKE INSERT ON TABLE public.rental FROM rental;

-- I try INSERT again as rentaluser. It should now fail.
-- IMPORTANT: I must switch to rentaluser again before testing.
SET ROLE rentaluser;

INSERT INTO public.rental (
    rental_date,
    inventory_id,
    customer_id,
    staff_id,
    return_date,
    last_update
)
VALUES (
    NOW(),
    1,
    1,
    1,
    NULL,
    NOW()
);
-- Expected error:
-- ERROR: permission denied for table rental

RESET ROLE;


-- I find a real customer who has both rental and payment history.
-- I use INNER JOIN on both tables so I only get customers who appear in both.
SELECT
    customer.customer_id,
    LOWER(customer.first_name) AS first_name,
    LOWER(customer.last_name) AS last_name,
    COUNT(DISTINCT rental.rental_id) AS rental_count,
    COUNT(DISTINCT payment.payment_id) AS payment_count
FROM public.customer AS customer
INNER JOIN public.rental AS rental
    ON rental.customer_id = customer.customer_id
INNER JOIN public.payment AS payment
    ON payment.customer_id = customer.customer_id
GROUP BY customer.customer_id, customer.first_name, customer.last_name
HAVING
    COUNT(DISTINCT rental.rental_id) > 0
    AND COUNT(DISTINCT payment.payment_id) > 0
ORDER BY customer.customer_id
LIMIT 1;

-- Result: customer_id=1, first_name=mary, last_name=smith
-- I create the personalized role following the pattern client_{first_name}_{last_name}.
CREATE ROLE client_mary_smith LOGIN PASSWORD 'clientpassword';


-- ============================================================
-- TASK 3. ROW-LEVEL SECURITY
-- ============================================================

-- I enable RLS on the rental and payment tables.
ALTER TABLE public.rental ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment ENABLE ROW LEVEL SECURITY;

-- I confirm RLS is now active.
SELECT
    pg_class.relname AS table_name,
    pg_class.relrowsecurity AS rls_enabled
FROM pg_class AS pg_class
INNER JOIN pg_namespace AS pg_namespace
    ON pg_namespace.oid = pg_class.relnamespace
WHERE
    LOWER(pg_namespace.nspname) = LOWER('public')
    AND LOWER(pg_class.relname) IN (LOWER('rental'), LOWER('payment'));


-- I create RLS policies for client_mary_smith.
-- The policy finds the customer_id dynamically by matching the role name
-- against the pattern client_{first_name}_{last_name} in the customer table.
-- This way I do not need to hardcode any ID.
-- This approach also scales better because the policy logic is based on the role name.

CREATE POLICY rental_own_data_policy
    ON public.rental
    FOR SELECT
    TO client_mary_smith
    USING (
        customer_id = (
            SELECT customer.customer_id
            FROM public.customer AS customer
            WHERE
                LOWER('client_' || LOWER(customer.first_name) || '_' || LOWER(customer.last_name))
                = LOWER(current_user)
            LIMIT 1
        )
    );

CREATE POLICY payment_own_data_policy
    ON public.payment
    FOR SELECT
    TO client_mary_smith
    USING (
        customer_id = (
            SELECT customer.customer_id
            FROM public.customer AS customer
            WHERE
                LOWER('client_' || LOWER(customer.first_name) || '_' || LOWER(customer.last_name))
                = LOWER(current_user)
            LIMIT 1
        )
    );


-- I grant SELECT on both tables so the role can actually read them.
GRANT SELECT ON TABLE public.rental TO client_mary_smith;
GRANT SELECT ON TABLE public.payment TO client_mary_smith;
GRANT SELECT ON TABLE public.customer TO client_mary_smith;


-- I test that client_mary_smith sees only her own data.
-- IMPORTANT: I must switch to the client role before testing RLS.
-- If I stay as postgres, I will see all rows because superusers bypass row-level security.
SET ROLE client_mary_smith;

-- This returns only Mary's rentals (customer_id = 1).
SELECT
    rental.rental_id,
    rental.rental_date,
    rental.return_date,
    rental.customer_id
FROM public.rental AS rental;
-- Expected: rows where customer_id = 1 only

-- This returns only Mary's payments (customer_id = 1).
SELECT
    payment.payment_id,
    payment.payment_date,
    payment.amount,
    payment.customer_id
FROM public.payment AS payment;
-- Expected: rows where customer_id = 1 only


-- I try to read another customer's data to confirm access is blocked.
-- PostgreSQL does not raise an error here.
-- Row-Level Security silently filters out rows that do not match the policy.
-- That is why the query returns 0 rows instead of showing unauthorized data.
SELECT
    rental.rental_id,
    rental.customer_id
FROM public.rental AS rental
WHERE rental.customer_id = 2;
-- Expected: 0 rows


-- I reset the role back to the superuser session.
RESET ROLE;