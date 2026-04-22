-- ============================================================
-- TASK 2. ROLE-BASED AUTHENTICATION MODEL
-- ============================================================

-- I create rentaluser with a password and only the ability to connect.
-- No table permissions are given yet.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'rentaluser'
    ) THEN
        CREATE USER rentaluser WITH PASSWORD 'rentalpassword';
    END IF;
END
$$;

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

-- I test that rentaluser CANNOT read the rental table.
SET ROLE rentaluser;

SELECT
    rental.rental_id,
    rental.rental_date,
    rental.inventory_id,
    rental.customer_id
FROM public.rental AS rental;
-- Expected error:
-- ERROR: permission denied for table rental

RESET ROLE;


-- I create the rental group role and add rentaluser to it.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'rental'
    ) THEN
        CREATE ROLE rental;
    END IF;
END
$$;

GRANT rental TO rentaluser;

-- Explanation:
-- CREATE ROLE and CREATE GROUP are effectively the same in PostgreSQL.
-- GROUP is just an older term. A "group" is a role used to manage permissions.
-- In modern PostgreSQL, CREATE ROLE is preferred because it is more flexible.

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
-- I also grant SELECT on the rental table because my UPDATE test query
-- uses a subquery with MAX(rental_id), which reads from the same table.
-- Without SELECT, the UPDATE would fail even though UPDATE permission is granted.
GRANT SELECT, INSERT, UPDATE ON TABLE public.rental TO rental;

-- I also grant usage on the sequence so INSERT can generate a new rental_id.
-- This is necessary because rental_id is generated using nextval().
-- Without this permission, INSERT would fail even if table INSERT is granted.
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

-- I test that rentaluser still cannot DELETE from rental.
SET ROLE rentaluser;

DELETE FROM public.rental
WHERE rental_id = -1;
-- Expected error:
-- ERROR: permission denied for table rental

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

-- I test that UPDATE still works after INSERT was revoked.
SET ROLE rentaluser;

UPDATE public.rental
SET return_date = NOW()
WHERE rental_id = (
    SELECT MAX(rental.rental_id)
    FROM public.rental AS rental
);
-- Expected: UPDATE 1

RESET ROLE;


-- I find a real customer who has both rental and payment history.
-- The mentor asked for a dynamic and rerunnable approach, so I wrap this in a function.
-- The function finds the first customer who appears in both the rental and payment tables,
-- builds the role name in the format client_{first_name}_{last_name},
-- revokes and drops the role if it already exists, then recreates it fresh.
-- This makes the script fully rerunnable without manual cleanup.
 
CREATE OR REPLACE FUNCTION create_client_role()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    found_first_name TEXT;
    found_last_name  TEXT;
    role_name        TEXT;
BEGIN
    -- Find the first customer who has at least one rental and one payment.
    -- INNER JOIN on both tables ensures the customer appears in both.
    SELECT
        LOWER(customer.first_name),
        LOWER(customer.last_name)
    INTO found_first_name, found_last_name
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
 
    -- Build the role name following the required pattern.
    role_name := 'client_' || found_first_name || '_' || found_last_name;
 
    -- If the role already exists, revoke all its privileges before dropping it.
    -- PostgreSQL refuses to drop a role that still holds privileges on objects.
    IF EXISTS (
        SELECT 1 FROM pg_roles WHERE LOWER(rolname) = LOWER(role_name)
    ) THEN
        EXECUTE format('REVOKE SELECT ON TABLE public.rental FROM %I', role_name);
        EXECUTE format('REVOKE SELECT ON TABLE public.payment FROM %I', role_name);
        EXECUTE format('REVOKE SELECT ON TABLE public.customer FROM %I', role_name);
        EXECUTE format('DROP ROLE %I', role_name);
    END IF;
 
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD ''clientpassword''', role_name);
 
    RETURN role_name;
END;
$$;
 
-- I call the function. It returns the role name so I can confirm which customer was selected.
SELECT create_client_role();
-- Expected output: client_ani_zviadauri
 
 
-- ============================================================
-- TASK 3. ROW-LEVEL SECURITY
-- ============================================================
 
-- I clean up any existing policies before creating new ones so the script is rerunnable.
DROP POLICY IF EXISTS rental_own_data_policy ON public.rental;
DROP POLICY IF EXISTS payment_own_data_policy ON public.payment;
DROP POLICY IF EXISTS rental_insert_policy ON public.rental;
DROP POLICY IF EXISTS rental_update_policy ON public.rental;
 
-- I disable RLS first so re-enabling it is safe even on repeated runs.
ALTER TABLE public.rental DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment DISABLE ROW LEVEL SECURITY;
 
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
 
 
-- I create RLS policies for client_ani_zviadauri.
-- The policy finds the customer_id dynamically by matching the role name
-- against the pattern client_{first_name}_{last_name} in the customer table.
-- This way I do not need to hardcode any ID and the logic works for any client role.

-- I also add a policy that allows the rental group to INSERT into the rental table.
-- When RLS is enabled, it applies to ALL commands including INSERT.
-- Without this policy, even a role with INSERT privilege would be blocked by RLS.
-- This policy uses WITH CHECK (true) which means any new row is allowed for this role.
CREATE POLICY rental_insert_policy
    ON public.rental
    FOR INSERT
    TO rental
    WITH CHECK (true);

-- I also add an UPDATE policy for the rental group for the same reason.
-- Without it, RLS blocks UPDATE even if the role has the UPDATE privilege.
CREATE POLICY rental_update_policy
    ON public.rental
    FOR UPDATE
    TO rental
    USING (true)
    WITH CHECK (true);

CREATE POLICY rental_own_data_policy
    ON public.rental
    FOR SELECT
    TO client_ani_zviadauri
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
    TO client_ani_zviadauri
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


-- I grant SELECT on rental and payment so the role can read those tables.
GRANT SELECT ON TABLE public.rental TO client_ani_zviadauri;
GRANT SELECT ON TABLE public.payment TO client_ani_zviadauri;
GRANT SELECT ON TABLE public.customer TO client_ani_zviadauri;

-- I also grant SELECT on the customer table because the RLS policy subquery
-- reads from customer to resolve the customer_id from the role name.
-- Without this grant the policy subquery is blocked, and the role cannot see
-- its own rows in rental and payment.


-- SUCCESSFUL ACCESS: client_ani_zviadauri reads only own data.
-- I switch to the client role because superusers bypass RLS completely.
SET ROLE client_ani_zviadauri;

-- Returns only Ani's rentals (customer_id = 1).
SELECT
    rental.rental_id,
    rental.rental_date,
    rental.return_date,
    rental.customer_id
FROM public.rental AS rental;
-- Expected: rows where customer_id = 1 only

-- Returns only Ani's payments (customer_id = 1).
SELECT
    payment.payment_id,
    payment.payment_date,
    payment.amount,
    payment.customer_id
FROM public.payment AS payment;
-- Expected: rows where customer_id = 1 only

RESET ROLE;


-- DENIED ACCESS: client_ani_zviadauri tries to read another customer's data.
-- RLS does not raise an error. It silently filters out rows that do not match the policy.
-- The result is 0 rows, which confirms the policy is working correctly.
SET ROLE client_ani_zviadauri;

SELECT
    rental.rental_id,
    rental.customer_id
FROM public.rental AS rental
WHERE rental.customer_id = 2;
-- Expected: 0 rows (RLS blocks access to other customers' data)

RESET ROLE;