--Final task
--Topic: household appliances store

-- DESCRIPTION:
--   Physical implementation of the Household Appliances Store logical data model.
--   The schema is in Third Normal Form (3NF): every non-key attribute
--   depends only on its table's primary key. Stable status values are stored
--   as ENUM types, while business entities such as categories, suppliers,
--   cities, job titles, brands, and product models are stored in separate
--   tables and linked with foreign keys.
--
-- NOTE ON RERUNNABILITY:
--   I made this script rerunnable by dropping and recreating the schema
--   household_appliances_store using CASCADE. This removes existing objects
--   from the schema and gives a clean state on each run. INSERT statements
--   use conflict-safe logic or natural-key checks to avoid duplicates.
-- =============================================================================


-- STEP 1: CREATE DATABASE (run separately)
-- =============================================================================
-- This statement creates the project database.
-- It must be executed separately before running the rest of the script,
-- because PostgreSQL does not allow switching databases within standard SQL.

CREATE DATABASE household_appliances_store_db;

-- =============================================================================
-- NOTE ON DATABASE EXECUTION:
-- After creating the database, I manually switched the connection
-- to 'household_appliances_store_db' (for example, in DBeaver)
-- before executing the remaining script.
-- =============================================================================

DROP SCHEMA IF EXISTS household_appliances_store CASCADE;
CREATE SCHEMA household_appliances_store;
SET search_path TO household_appliances_store;

-- =========================================================
-- 2. ENUM TYPES
-- =========================================================

-- I use ENUM for stable and fixed values.
-- These values are small and controlled, so ENUM fits well here.

DO
$$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type
        WHERE typname = 'transaction_status_enum'
    ) THEN
        CREATE TYPE household_appliances_store.transaction_status_enum AS ENUM
        ('pending', 'paid', 'shipped', 'delivered', 'cancelled');
    END IF;
END;
$$;

DO
$$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type
        WHERE typname = 'payment_method_enum'
    ) THEN
        CREATE TYPE household_appliances_store.payment_method_enum AS ENUM
        ('cash', 'card', 'bank_transfer');
    END IF;
END;
$$;

DO
$$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type
        WHERE typname = 'procurement_status_enum'
    ) THEN
        CREATE TYPE household_appliances_store.procurement_status_enum AS ENUM
        ('ordered', 'in_transit', 'received');
    END IF;
END;
$$;

-- =========================================================
-- 3. TABLES
-- ========================================================= 

-- I create customer table to store customer information 
CREATE TABLE household_appliances_store.customer (
    customer_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    full_name VARCHAR(210) GENERATED ALWAYS AS (
        trim(first_name) || ' ' || trim(last_name)
    ) STORED,
    email VARCHAR(255) NOT NULL UNIQUE,
    phone VARCHAR(30) NOT NULL UNIQUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP -- CHANGED
);

-- I create city table to avoid repeating city values in supplier table
CREATE TABLE household_appliances_store.city (
    city_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    city_name VARCHAR(100) NOT NULL UNIQUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- I create job_title table to avoid repeating job title values in employee table
CREATE TABLE household_appliances_store.job_title (
    job_title_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_title_name VARCHAR(50) NOT NULL UNIQUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- I create brand table because brand is a reusable business entity
CREATE TABLE household_appliances_store.brand (
    brand_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    brand_name VARCHAR(100) NOT NULL UNIQUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- I create product_model table because model depends on brand.
-- Warranty is stored here because it depends on the product model.
CREATE TABLE household_appliances_store.product_model (
    product_model_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    brand_id BIGINT NOT NULL,
    model_name VARCHAR(100) NOT NULL,
    warranty_months INTEGER NOT NULL DEFAULT 12,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_product_model_brand
        FOREIGN KEY (brand_id)
        REFERENCES household_appliances_store.brand (brand_id),
    CONSTRAINT uq_product_model_brand_model UNIQUE (brand_id, model_name)
);

-- I create employee table to store employees working in the store
CREATE TABLE household_appliances_store.employee (
    employee_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    full_name VARCHAR(210) GENERATED ALWAYS AS (
        trim(first_name) || ' ' || trim(last_name)
    ) STORED,
    email VARCHAR(255) NOT NULL UNIQUE,
    phone VARCHAR(30) NOT NULL UNIQUE,
    job_title_id BIGINT NOT NULL, -- CHANGED
    hire_date DATE NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- ADDED
    CONSTRAINT fk_employee_job_title
        FOREIGN KEY (job_title_id)
        REFERENCES household_appliances_store.job_title (job_title_id)
);

-- I create category table to classify products
CREATE TABLE household_appliances_store.category (
    category_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL UNIQUE,
    category_description VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP -- ADDED
);

-- I create supplier table to store supplier information
CREATE TABLE household_appliances_store.supplier (
    supplier_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supplier_name VARCHAR(150) NOT NULL UNIQUE,
    contact_email VARCHAR(255) NOT NULL UNIQUE,
    phone VARCHAR(30) NOT NULL UNIQUE,
    city_id BIGINT NOT NULL, -- CHANGED
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- CHANGED
    CONSTRAINT fk_supplier_city
        FOREIGN KEY (city_id)
        REFERENCES household_appliances_store.city (city_id)
);

-- I create product table to store products and link them to model, category and supplier
CREATE TABLE household_appliances_store.product (
    product_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_name VARCHAR(150) NOT NULL,
    product_model_id BIGINT NOT NULL, -- CHANGED
    category_id BIGINT NOT NULL,
    supplier_id BIGINT NOT NULL,
    unit_price NUMERIC(10,2) NOT NULL,
    stock_quantity INTEGER NOT NULL DEFAULT 0,
    product_display_name VARCHAR(300), -- CHANGED
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- CHANGED
    CONSTRAINT fk_product_product_model
        FOREIGN KEY (product_model_id)
        REFERENCES household_appliances_store.product_model (product_model_id),
    CONSTRAINT fk_product_category
        FOREIGN KEY (category_id)
        REFERENCES household_appliances_store.category (category_id),
    CONSTRAINT fk_product_supplier
        FOREIGN KEY (supplier_id)
        REFERENCES household_appliances_store.supplier (supplier_id)
);

-- I create sales_transaction table to store transaction header data
CREATE TABLE household_appliances_store.sales_transaction (
    sales_transaction_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transaction_number VARCHAR(30) NOT NULL UNIQUE,
    customer_id BIGINT NOT NULL,
    employee_id BIGINT NOT NULL,
    transaction_date DATE NOT NULL DEFAULT CURRENT_DATE,
    transaction_status household_appliances_store.transaction_status_enum NOT NULL DEFAULT 'pending',
    payment_method household_appliances_store.payment_method_enum NOT NULL DEFAULT 'card',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_sales_transaction_customer
        FOREIGN KEY (customer_id)
        REFERENCES household_appliances_store.customer (customer_id),
    CONSTRAINT fk_sales_transaction_employee
        FOREIGN KEY (employee_id)
        REFERENCES household_appliances_store.employee (employee_id)
);

-- I create sales_transaction_item table to store products in each transaction and resolve many-to-many relationship.
-- CHANGED: I use a composite primary key instead of both a surrogate key and a unique pair.
CREATE TABLE household_appliances_store.sales_transaction_item (
    sales_transaction_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price NUMERIC(10,2) NOT NULL,
    line_total NUMERIC(12,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    CONSTRAINT pk_sales_transaction_item
        PRIMARY KEY (sales_transaction_id, product_id),
    CONSTRAINT fk_sales_transaction_item_transaction
        FOREIGN KEY (sales_transaction_id)
        REFERENCES household_appliances_store.sales_transaction (sales_transaction_id),
    CONSTRAINT fk_sales_transaction_item_product
        FOREIGN KEY (product_id)
        REFERENCES household_appliances_store.product (product_id)
);

-- I create procurement table to track product restocking from suppliers
CREATE TABLE household_appliances_store.procurement (
    procurement_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    procurement_number VARCHAR(30) NOT NULL UNIQUE,
    supplier_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    quantity INTEGER NOT NULL,
    unit_cost NUMERIC(10,2) NOT NULL,
    delivery_date DATE NOT NULL,
    procurement_status household_appliances_store.procurement_status_enum NOT NULL DEFAULT 'received',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_procurement_supplier
        FOREIGN KEY (supplier_id)
        REFERENCES household_appliances_store.supplier (supplier_id),
    CONSTRAINT fk_procurement_product
        FOREIGN KEY (product_id)
        REFERENCES household_appliances_store.product (product_id)
);

-- =========================================================
-- 4. CONSTRAINTS ADDED WITH ALTER TABLE
-- =========================================================

-- I add these constraints after CREATE TABLE because the task asks me
-- to use ALTER TABLE and give meaningful names.

ALTER TABLE household_appliances_store.customer
ADD CONSTRAINT chk_customer_email_lowercase
CHECK (email = lower(trim(email)));

ALTER TABLE household_appliances_store.employee
ADD CONSTRAINT chk_employee_email_lowercase
CHECK (email = lower(trim(email)));


ALTER TABLE household_appliances_store.city
ADD CONSTRAINT chk_city_name_not_blank
CHECK (length(trim(city_name)) > 0);


ALTER TABLE household_appliances_store.job_title
ADD CONSTRAINT chk_job_title_name_not_blank
CHECK (length(trim(job_title_name)) > 0);


ALTER TABLE household_appliances_store.brand
ADD CONSTRAINT chk_brand_name_not_blank
CHECK (length(trim(brand_name)) > 0);


ALTER TABLE household_appliances_store.product_model
ADD CONSTRAINT chk_product_model_name_not_blank
CHECK (length(trim(model_name)) > 0);


ALTER TABLE household_appliances_store.product_model
ADD CONSTRAINT chk_product_model_warranty_months_non_negative
CHECK (warranty_months >= 0);

ALTER TABLE household_appliances_store.product
ADD CONSTRAINT chk_product_name_not_blank
CHECK (length(trim(product_name)) > 0);

ALTER TABLE household_appliances_store.product
ADD CONSTRAINT chk_product_unit_price_positive
CHECK (unit_price > 0);

ALTER TABLE household_appliances_store.product
ADD CONSTRAINT chk_product_stock_quantity_non_negative
CHECK (stock_quantity >= 0);

ALTER TABLE household_appliances_store.sales_transaction
ADD CONSTRAINT chk_sales_transaction_date_after_2026_01_01
CHECK (transaction_date > DATE '2026-01-01');

ALTER TABLE household_appliances_store.sales_transaction_item
ADD CONSTRAINT chk_sales_transaction_item_quantity_positive
CHECK (quantity > 0);

ALTER TABLE household_appliances_store.sales_transaction_item
ADD CONSTRAINT chk_sales_transaction_item_unit_price_positive
CHECK (unit_price > 0);

ALTER TABLE household_appliances_store.procurement
ADD CONSTRAINT chk_procurement_quantity_positive
CHECK (quantity > 0);

ALTER TABLE household_appliances_store.procurement
ADD CONSTRAINT chk_procurement_unit_cost_positive
CHECK (unit_cost > 0);

ALTER TABLE household_appliances_store.procurement
ADD CONSTRAINT chk_procurement_delivery_date_after_2026_01_01
CHECK (delivery_date > DATE '2026-01-01');

-- =========================================================
-- 5. SAMPLE DATA
-- I insert at least 6 rows into each table.
-- I keep the dates within the last 3 months.
-- I do not insert surrogate keys manually.
-- =========================================================

-- 5.1 CATEGORY

INSERT INTO household_appliances_store.category (
    category_name,
    category_description,
    created_at -- ADDED
)
VALUES
    ('refrigerator', 'cooling appliances for food storage', CURRENT_TIMESTAMP - INTERVAL '84 days'),
    ('washing machine', 'laundry appliances for household use', CURRENT_TIMESTAMP - INTERVAL '79 days'),
    ('dishwasher', 'appliances for dish cleaning', CURRENT_TIMESTAMP - INTERVAL '73 days'),
    ('microwave', 'compact heating appliances', CURRENT_TIMESTAMP - INTERVAL '67 days'),
    ('vacuum cleaner', 'cleaning appliances for floors and carpets', CURRENT_TIMESTAMP - INTERVAL '62 days'),
    ('air conditioner', 'climate control appliances', CURRENT_TIMESTAMP - INTERVAL '57 days')
ON CONFLICT (category_name) DO NOTHING;

-- 5.2 CITY 

INSERT INTO household_appliances_store.city (
    city_name,
    created_at
)
VALUES
    ('tbilisi', CURRENT_TIMESTAMP - INTERVAL '84 days'),
    ('batumi', CURRENT_TIMESTAMP - INTERVAL '79 days'),
    ('kutaisi', CURRENT_TIMESTAMP - INTERVAL '73 days'),
    ('rustavi', CURRENT_TIMESTAMP - INTERVAL '67 days'),
    ('gori', CURRENT_TIMESTAMP - INTERVAL '62 days'),
    ('zugdidi', CURRENT_TIMESTAMP - INTERVAL '57 days')
ON CONFLICT (city_name) DO NOTHING;

-- 5.3 JOB TITLE 
INSERT INTO household_appliances_store.job_title (
    job_title_name,
    created_at
)
VALUES
    ('sales manager', CURRENT_TIMESTAMP - INTERVAL '84 days'),
    ('sales consultant', CURRENT_TIMESTAMP - INTERVAL '79 days'),
    ('inventory specialist', CURRENT_TIMESTAMP - INTERVAL '73 days'),
    ('procurement specialist', CURRENT_TIMESTAMP - INTERVAL '67 days'),
    ('store manager', CURRENT_TIMESTAMP - INTERVAL '62 days'),
    ('cashier', CURRENT_TIMESTAMP - INTERVAL '57 days')
ON CONFLICT (job_title_name) DO NOTHING;

-- 5.4 BRAND 

INSERT INTO household_appliances_store.brand (
    brand_name,
    created_at
)
VALUES
    ('samsung', CURRENT_TIMESTAMP - INTERVAL '84 days'),
    ('lg', CURRENT_TIMESTAMP - INTERVAL '79 days'),
    ('bosch', CURRENT_TIMESTAMP - INTERVAL '73 days'),
    ('whirlpool', CURRENT_TIMESTAMP - INTERVAL '67 days'),
    ('philips', CURRENT_TIMESTAMP - INTERVAL '62 days'),
    ('midea', CURRENT_TIMESTAMP - INTERVAL '57 days')
ON CONFLICT (brand_name) DO NOTHING;

-- 5.5 PRODUCT MODEL 

INSERT INTO household_appliances_store.product_model (
    brand_id,
    model_name,
    warranty_months,
    created_at
)
SELECT
    household_appliances_store.brand.brand_id,
    product_model_seed.model_name,
    product_model_seed.warranty_months,
    product_model_seed.created_at
FROM (
    VALUES
        ('samsung', 'rb34t600esa', 24, CURRENT_TIMESTAMP - INTERVAL '82 days'),
        ('lg', 'f2v5s8s0', 24, CURRENT_TIMESTAMP - INTERVAL '77 days'),
        ('bosch', 'sms2iti33e', 24, CURRENT_TIMESTAMP - INTERVAL '71 days'),
        ('whirlpool', 'mwp338sx', 12, CURRENT_TIMESTAMP - INTERVAL '66 days'),
        ('philips', 'xb2123', 12, CURRENT_TIMESTAMP - INTERVAL '61 days'),
        ('midea', 'msagbu-12hrfn8', 24, CURRENT_TIMESTAMP - INTERVAL '56 days')
) AS product_model_seed (
    brand_name,
    model_name,
    warranty_months,
    created_at
)
INNER JOIN household_appliances_store.brand
    ON household_appliances_store.brand.brand_name = product_model_seed.brand_name
ON CONFLICT (brand_id, model_name) DO NOTHING;

-- 5.6 SUPPLIER 

INSERT INTO household_appliances_store.supplier (
    supplier_name,
    contact_email,
    phone,
    city_id,
    created_at
)
SELECT
    supplier_seed.supplier_name,
    supplier_seed.contact_email,
    supplier_seed.phone,
    household_appliances_store.city.city_id,
    supplier_seed.created_at
FROM (
    VALUES
        ('geotech distribution', 'sales@geotech.example', '+995555000101', 'tbilisi', CURRENT_TIMESTAMP - INTERVAL '80 days'),
        ('homeplus import', 'contact@homeplus.example', '+995555000102', 'batumi', CURRENT_TIMESTAMP - INTERVAL '76 days'),
        ('euroappliance supply', 'office@euroappliance.example', '+995555000103', 'kutaisi', CURRENT_TIMESTAMP - INTERVAL '72 days'),
        ('nordic trade group', 'info@nordictrade.example', '+995555000104', 'rustavi', CURRENT_TIMESTAMP - INTERVAL '68 days'),
        ('smartliving wholesale', 'team@smartliving.example', '+995555000105', 'gori', CURRENT_TIMESTAMP - INTERVAL '64 days'),
        ('megaelectro partners', 'orders@megaelectro.example', '+995555000106', 'zugdidi', CURRENT_TIMESTAMP - INTERVAL '60 days')
) AS supplier_seed (
    supplier_name,
    contact_email,
    phone,
    city_name,
    created_at
)
INNER JOIN household_appliances_store.city
    ON household_appliances_store.city.city_name = supplier_seed.city_name
ON CONFLICT (supplier_name) DO NOTHING;

-- 5.7 CUSTOMER

INSERT INTO household_appliances_store.customer (
    first_name,
    last_name,
    email,
    phone,
    created_at
)
VALUES
    ('ani', 'zviadauri', 'ani.zviadauri@example.com', '+995599000001', CURRENT_TIMESTAMP - INTERVAL '84 days'),
    ('nino', 'beridze', 'nino.beridze@example.com', '+995599000002', CURRENT_TIMESTAMP - INTERVAL '79 days'),
    ('luka', 'gogoladze', 'luka.gogoladze@example.com', '+995599000003', CURRENT_TIMESTAMP - INTERVAL '73 days'),
    ('mariam', 'kapanadze', 'mariam.kapanadze@example.com', '+995599000004', CURRENT_TIMESTAMP - INTERVAL '67 days'),
    ('sandro', 'gelashvili', 'sandro.gelashvili@example.com', '+995599000005', CURRENT_TIMESTAMP - INTERVAL '62 days'),
    ('tekla', 'japaridze', 'tekla.japaridze@example.com', '+995599000006', CURRENT_TIMESTAMP - INTERVAL '57 days')
ON CONFLICT (email) DO NOTHING;

-- 5.8 EMPLOYEE 

INSERT INTO household_appliances_store.employee (
    first_name,
    last_name,
    email,
    phone,
    job_title_id,
    hire_date,
    created_at
)
SELECT
    employee_seed.first_name,
    employee_seed.last_name,
    employee_seed.email,
    employee_seed.phone,
    household_appliances_store.job_title.job_title_id,
    employee_seed.hire_date,
    employee_seed.created_at
FROM (
    VALUES
        ('irakli', 'mchedlishvili', 'irakli.mchedlishvili@store.example', '+995577100001', 'sales manager', DATE '2026-01-15', CURRENT_TIMESTAMP - INTERVAL '84 days'),
        ('tamta', 'melikidze', 'tamta.melikidze@store.example', '+995577100002', 'sales consultant', DATE '2026-01-22', CURRENT_TIMESTAMP - INTERVAL '79 days'),
        ('giorgi', 'kiknadze', 'giorgi.kiknadze@store.example', '+995577100003', 'sales consultant', DATE '2026-02-01', CURRENT_TIMESTAMP - INTERVAL '73 days'),
        ('elene', 'shengelia', 'elene.shengelia@store.example', '+995577100004', 'inventory specialist', DATE '2026-02-10', CURRENT_TIMESTAMP - INTERVAL '67 days'),
        ('dato', 'tsiklauri', 'dato.tsiklauri@store.example', '+995577100005', 'procurement specialist', DATE '2026-02-18', CURRENT_TIMESTAMP - INTERVAL '62 days'),
        ('salome', 'otaraashvili', 'salome.otaraashvili@store.example', '+995577100006', 'sales consultant', DATE '2026-03-02', CURRENT_TIMESTAMP - INTERVAL '57 days')
) AS employee_seed (
    first_name,
    last_name,
    email,
    phone,
    job_title_name,
    hire_date,
    created_at
)
INNER JOIN household_appliances_store.job_title
    ON household_appliances_store.job_title.job_title_name = employee_seed.job_title_name
ON CONFLICT (email) DO NOTHING;

-- 5.9 PRODUCT 


INSERT INTO household_appliances_store.product (
    product_name,
    product_model_id,
    category_id,
    supplier_id,
    unit_price,
    stock_quantity,
    product_display_name,
    created_at
)
SELECT
    product_seed.product_name,
    household_appliances_store.product_model.product_model_id,
    household_appliances_store.category.category_id,
    household_appliances_store.supplier.supplier_id,
    product_seed.unit_price,
    product_seed.stock_quantity,
    trim(product_seed.brand_name) || ' ' || trim(product_seed.model_name) || ' - ' || trim(product_seed.product_name),
    product_seed.created_at
FROM (
    VALUES
        ('no frost refrigerator', 'samsung', 'rb34t600esa', 'refrigerator', 'geotech distribution', 1899.00, 8, CURRENT_TIMESTAMP - INTERVAL '82 days'),
        ('front load washer', 'lg', 'f2v5s8s0', 'washing machine', 'homeplus import', 1499.00, 10, CURRENT_TIMESTAMP - INTERVAL '77 days'),
        ('compact dishwasher', 'bosch', 'sms2iti33e', 'dishwasher', 'euroappliance supply', 1299.00, 7, CURRENT_TIMESTAMP - INTERVAL '71 days'),
        ('grill microwave', 'whirlpool', 'mwp338sx', 'microwave', 'nordic trade group', 499.00, 14, CURRENT_TIMESTAMP - INTERVAL '66 days'),
        ('bagless vacuum', 'philips', 'xb2123', 'vacuum cleaner', 'smartliving wholesale', 359.00, 16, CURRENT_TIMESTAMP - INTERVAL '61 days'),
        ('split ac 12000 btu', 'midea', 'msagbu-12hrfn8', 'air conditioner', 'megaelectro partners', 1699.00, 6, CURRENT_TIMESTAMP - INTERVAL '56 days')
) AS product_seed (
    product_name,
    brand_name,
    model_name,
    category_name,
    supplier_name,
    unit_price,
    stock_quantity,
    created_at
)
INNER JOIN household_appliances_store.brand
    ON household_appliances_store.brand.brand_name = product_seed.brand_name
INNER JOIN household_appliances_store.product_model
    ON household_appliances_store.product_model.brand_id = household_appliances_store.brand.brand_id
   AND household_appliances_store.product_model.model_name = product_seed.model_name
INNER JOIN household_appliances_store.category
    ON household_appliances_store.category.category_name = product_seed.category_name
INNER JOIN household_appliances_store.supplier
    ON household_appliances_store.supplier.supplier_name = product_seed.supplier_name
WHERE NOT EXISTS (
    SELECT 1
    FROM household_appliances_store.product
    WHERE household_appliances_store.product.product_model_id =
          household_appliances_store.product_model.product_model_id
);

-- 5.10 PROCUREMENT 

INSERT INTO household_appliances_store.procurement (
    procurement_number,
    supplier_id,
    product_id,
    quantity,
    unit_cost,
    delivery_date,
    procurement_status,
    created_at
)
SELECT
    procurement_seed.procurement_number,
    household_appliances_store.supplier.supplier_id,
    household_appliances_store.product.product_id,
    procurement_seed.quantity,
    procurement_seed.unit_cost,
    procurement_seed.delivery_date,
    procurement_seed.procurement_status::household_appliances_store.procurement_status_enum,
    procurement_seed.created_at
FROM (
    VALUES
        ('PR-2026-001', 'geotech distribution', 'samsung', 'rb34t600esa', 5, 1500.00, CURRENT_DATE - 82, 'received', CURRENT_TIMESTAMP - INTERVAL '82 days'),
        ('PR-2026-002', 'homeplus import', 'lg', 'f2v5s8s0', 6, 1180.00, CURRENT_DATE - 76, 'received', CURRENT_TIMESTAMP - INTERVAL '76 days'),
        ('PR-2026-003', 'euroappliance supply', 'bosch', 'sms2iti33e', 4, 980.00, CURRENT_DATE - 70, 'received', CURRENT_TIMESTAMP - INTERVAL '70 days'),
        ('PR-2026-004', 'nordic trade group', 'whirlpool', 'mwp338sx', 10, 320.00, CURRENT_DATE - 64, 'received', CURRENT_TIMESTAMP - INTERVAL '64 days'),
        ('PR-2026-005', 'smartliving wholesale', 'philips', 'xb2123', 12, 220.00, CURRENT_DATE - 59, 'received', CURRENT_TIMESTAMP - INTERVAL '59 days'),
        ('PR-2026-006', 'megaelectro partners', 'midea', 'msagbu-12hrfn8', 3, 1350.00, CURRENT_DATE - 52, 'received', CURRENT_TIMESTAMP - INTERVAL '52 days')
) AS procurement_seed (
    procurement_number,
    supplier_name,
    brand_name,
    model_name,
    quantity,
    unit_cost,
    delivery_date,
    procurement_status,
    created_at
)
INNER JOIN household_appliances_store.supplier
    ON household_appliances_store.supplier.supplier_name = procurement_seed.supplier_name
INNER JOIN household_appliances_store.brand
    ON household_appliances_store.brand.brand_name = procurement_seed.brand_name
INNER JOIN household_appliances_store.product_model
    ON household_appliances_store.product_model.brand_id = household_appliances_store.brand.brand_id
   AND household_appliances_store.product_model.model_name = procurement_seed.model_name
INNER JOIN household_appliances_store.product
    ON household_appliances_store.product.product_model_id = household_appliances_store.product_model.product_model_id
ON CONFLICT (procurement_number) DO NOTHING;

-- 5.11 SALES TRANSACTION

INSERT INTO household_appliances_store.sales_transaction (
    transaction_number,
    customer_id,
    employee_id,
    transaction_date,
    transaction_status,
    payment_method,
    created_at
)
SELECT
    transaction_seed.transaction_number,
    household_appliances_store.customer.customer_id,
    household_appliances_store.employee.employee_id,
    transaction_seed.transaction_date,
    transaction_seed.transaction_status::household_appliances_store.transaction_status_enum,
    transaction_seed.payment_method::household_appliances_store.payment_method_enum,
    transaction_seed.created_at
FROM (
    VALUES
        ('TR-2026-001', 'ani.zviadauri@example.com', 'tamta.melikidze@store.example', CURRENT_DATE - 44, 'delivered', 'card', CURRENT_TIMESTAMP - INTERVAL '44 days'),
        ('TR-2026-002', 'nino.beridze@example.com', 'giorgi.kiknadze@store.example', CURRENT_DATE - 39, 'paid', 'cash', CURRENT_TIMESTAMP - INTERVAL '39 days'),
        ('TR-2026-003', 'luka.gogoladze@example.com', 'salome.otaraashvili@store.example', CURRENT_DATE - 31, 'shipped', 'card', CURRENT_TIMESTAMP - INTERVAL '31 days'),
        ('TR-2026-004', 'mariam.kapanadze@example.com', 'tamta.melikidze@store.example', CURRENT_DATE - 24, 'delivered', 'bank_transfer', CURRENT_TIMESTAMP - INTERVAL '24 days'),
        ('TR-2026-005', 'sandro.gelashvili@example.com', 'giorgi.kiknadze@store.example', CURRENT_DATE - 17, 'pending', 'card', CURRENT_TIMESTAMP - INTERVAL '17 days'),
        ('TR-2026-006', 'tekla.japaridze@example.com', 'salome.otaraashvili@store.example', CURRENT_DATE - 8, 'paid', 'cash', CURRENT_TIMESTAMP - INTERVAL '8 days')
) AS transaction_seed (
    transaction_number,
    customer_email,
    employee_email,
    transaction_date,
    transaction_status,
    payment_method,
    created_at
)
INNER JOIN household_appliances_store.customer
    ON household_appliances_store.customer.email = transaction_seed.customer_email
INNER JOIN household_appliances_store.employee
    ON household_appliances_store.employee.email = transaction_seed.employee_email
ON CONFLICT (transaction_number) DO NOTHING;

-- 5.12 SALES TRANSACTION ITEM 

INSERT INTO household_appliances_store.sales_transaction_item (
    sales_transaction_id,
    product_id,
    quantity,
    unit_price
)
SELECT
    household_appliances_store.sales_transaction.sales_transaction_id,
    household_appliances_store.product.product_id,
    item_seed.quantity,
    item_seed.unit_price
FROM (
    VALUES
        ('TR-2026-001', 'samsung', 'rb34t600esa', 1, 1899.00),
        ('TR-2026-001', 'whirlpool', 'mwp338sx', 1, 499.00),
        ('TR-2026-002', 'philips', 'xb2123', 2, 359.00),
        ('TR-2026-003', 'lg', 'f2v5s8s0', 1, 1499.00),
        ('TR-2026-004', 'bosch', 'sms2iti33e', 1, 1299.00),
        ('TR-2026-005', 'midea', 'msagbu-12hrfn8', 1, 1699.00),
        ('TR-2026-006', 'whirlpool', 'mwp338sx', 1, 499.00),
        ('TR-2026-006', 'philips', 'xb2123', 1, 359.00)
) AS item_seed (
    transaction_number,
    brand_name,
    model_name,
    quantity,
    unit_price
)
INNER JOIN household_appliances_store.sales_transaction
    ON household_appliances_store.sales_transaction.transaction_number = item_seed.transaction_number
INNER JOIN household_appliances_store.brand
    ON household_appliances_store.brand.brand_name = item_seed.brand_name
INNER JOIN household_appliances_store.product_model
    ON household_appliances_store.product_model.brand_id = household_appliances_store.brand.brand_id
   AND household_appliances_store.product_model.model_name = item_seed.model_name
INNER JOIN household_appliances_store.product
    ON household_appliances_store.product.product_model_id = household_appliances_store.product_model.product_model_id
ON CONFLICT (sales_transaction_id, product_id) DO NOTHING;

-- =========================================================
-- 6. FUNCTION 1
-- I make a function that updates one chosen column in the product table.
-- I keep it controlled with a whitelist of allowed columns.
-- CHANGED: brand, model, and warranty_months are not updated here because
-- they now belong to brand and product_model tables.
-- =========================================================

CREATE OR REPLACE FUNCTION household_appliances_store.update_product_column(
    p_product_id BIGINT,
    p_column_name TEXT,
    p_new_value TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS
$$
BEGIN
    IF lower(trim(p_column_name)) NOT IN (
        'product_name',
        'unit_price',
        'stock_quantity',
        'product_display_name',
        'created_at'
    ) THEN
        RAISE EXCEPTION 'Column % is not allowed.', p_column_name;
    END IF;

    IF lower(trim(p_column_name)) = 'product_name' THEN
        UPDATE household_appliances_store.product
        SET product_name = lower(trim(p_new_value))
        WHERE product_id = p_product_id;

    ELSIF lower(trim(p_column_name)) = 'unit_price' THEN
        UPDATE household_appliances_store.product
        SET unit_price = p_new_value::NUMERIC(10,2)
        WHERE product_id = p_product_id;

    ELSIF lower(trim(p_column_name)) = 'stock_quantity' THEN
        UPDATE household_appliances_store.product
        SET stock_quantity = p_new_value::INTEGER
        WHERE product_id = p_product_id;

    ELSIF lower(trim(p_column_name)) = 'product_display_name' THEN
        UPDATE household_appliances_store.product
        SET product_display_name = lower(trim(p_new_value))
        WHERE product_id = p_product_id;

    ELSIF lower(trim(p_column_name)) = 'created_at' THEN
        UPDATE household_appliances_store.product
        SET created_at = p_new_value::TIMESTAMP
        WHERE product_id = p_product_id;
    END IF;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product with id % was not found.', p_product_id;
    END IF;

    RAISE NOTICE 'Product % updated successfully.', p_product_id;
END;
$$;

-- =========================================================
-- 7. FUNCTION 2
-- I make a function that inserts a new sales transaction.
-- I use natural keys so I do not need to pass surrogate keys manually.
-- I insert one header row and one item row.
-- I also decrease stock after the sale.
-- CHANGED: brand name and model name are used together as the natural key
-- for product model lookup.
-- =========================================================

CREATE OR REPLACE FUNCTION household_appliances_store.add_sales_transaction(
    p_transaction_number VARCHAR(30),
    p_customer_email VARCHAR(255),
    p_employee_email VARCHAR(255),
    p_brand_name VARCHAR(100), -- ADDED
    p_model_name VARCHAR(100), -- CHANGED
    p_quantity INTEGER,
    p_transaction_date DATE DEFAULT CURRENT_DATE,
    p_transaction_status household_appliances_store.transaction_status_enum DEFAULT 'pending',
    p_payment_method household_appliances_store.payment_method_enum DEFAULT 'card'
)
RETURNS VOID
LANGUAGE plpgsql
AS
$$
DECLARE
    v_customer_id BIGINT;
    v_employee_id BIGINT;
    v_product_id BIGINT;
    v_unit_price NUMERIC(10,2);
    v_sales_transaction_id BIGINT;
BEGIN
    SELECT household_appliances_store.customer.customer_id
    INTO v_customer_id
    FROM household_appliances_store.customer
    WHERE household_appliances_store.customer.email = lower(trim(p_customer_email));

    IF v_customer_id IS NULL THEN
        RAISE EXCEPTION 'Customer with email % was not found.', p_customer_email;
    END IF;

    SELECT household_appliances_store.employee.employee_id
    INTO v_employee_id
    FROM household_appliances_store.employee
    WHERE household_appliances_store.employee.email = lower(trim(p_employee_email));

    IF v_employee_id IS NULL THEN
        RAISE EXCEPTION 'Employee with email % was not found.', p_employee_email;
    END IF;

    SELECT
        household_appliances_store.product.product_id,
        household_appliances_store.product.unit_price
    INTO
        v_product_id,
        v_unit_price
    FROM household_appliances_store.product
    INNER JOIN household_appliances_store.product_model
        ON household_appliances_store.product_model.product_model_id = household_appliances_store.product.product_model_id
    INNER JOIN household_appliances_store.brand
        ON household_appliances_store.brand.brand_id = household_appliances_store.product_model.brand_id
    WHERE household_appliances_store.brand.brand_name = lower(trim(p_brand_name))
      AND household_appliances_store.product_model.model_name = lower(trim(p_model_name));

    IF v_product_id IS NULL THEN
        RAISE EXCEPTION 'Product with brand % and model % was not found.', p_brand_name, p_model_name;
    END IF;

    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'Quantity must be greater than zero.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM household_appliances_store.sales_transaction
        WHERE household_appliances_store.sales_transaction.transaction_number = p_transaction_number
    ) THEN
        RAISE EXCEPTION 'Transaction number % already exists.', p_transaction_number;
    END IF;

    IF (
        SELECT household_appliances_store.product.stock_quantity
        FROM household_appliances_store.product
        WHERE household_appliances_store.product.product_id = v_product_id
    ) < p_quantity THEN
        RAISE EXCEPTION 'Not enough stock for brand % and model %.', p_brand_name, p_model_name;
    END IF;

    INSERT INTO household_appliances_store.sales_transaction (
        transaction_number,
        customer_id,
        employee_id,
        transaction_date,
        transaction_status,
        payment_method
    )
    VALUES (
        p_transaction_number,
        v_customer_id,
        v_employee_id,
        p_transaction_date,
        p_transaction_status,
        p_payment_method
    )
    RETURNING sales_transaction_id
    INTO v_sales_transaction_id;

    INSERT INTO household_appliances_store.sales_transaction_item (
        sales_transaction_id,
        product_id,
        quantity,
        unit_price
    )
    VALUES (
        v_sales_transaction_id,
        v_product_id,
        p_quantity,
        v_unit_price
    );

    UPDATE household_appliances_store.product
    SET stock_quantity = stock_quantity - p_quantity
    WHERE product_id = v_product_id;

    RAISE NOTICE 'Transaction % inserted successfully.', p_transaction_number;
END;
$$;

-- =========================================================
-- 8. VIEW
-- I make one analytics view for the most recent quarter in the data.
-- I exclude surrogate keys from the result.
-- I group the data so I do not get duplicates.
-- CHANGED: brand and model are now selected from normalized tables.
-- =========================================================

CREATE OR REPLACE VIEW household_appliances_store.vw_latest_quarter_sales_analytics AS
WITH latest_quarter AS (
    SELECT
        date_trunc('quarter', MAX(household_appliances_store.sales_transaction.transaction_date))::DATE AS quarter_start_date
    FROM household_appliances_store.sales_transaction
),
quarter_transactions AS (
    SELECT
        household_appliances_store.sales_transaction.sales_transaction_id,
        household_appliances_store.sales_transaction.transaction_number,
        household_appliances_store.sales_transaction.transaction_date
    FROM household_appliances_store.sales_transaction
    INNER JOIN latest_quarter
        ON household_appliances_store.sales_transaction.transaction_date >= latest_quarter.quarter_start_date
       AND household_appliances_store.sales_transaction.transaction_date < latest_quarter.quarter_start_date + INTERVAL '3 months'
)
SELECT
    latest_quarter.quarter_start_date,
    to_char(quarter_transactions.transaction_date, 'YYYY-MM') AS transaction_month,
    household_appliances_store.category.category_name,
    household_appliances_store.product.product_name,
    household_appliances_store.brand.brand_name,
    household_appliances_store.product_model.model_name,
    SUM(household_appliances_store.sales_transaction_item.quantity) AS total_units_sold,
    SUM(household_appliances_store.sales_transaction_item.line_total) AS total_revenue,
    COUNT(DISTINCT quarter_transactions.transaction_number) AS total_transactions
FROM quarter_transactions
INNER JOIN latest_quarter
    ON 1 = 1
INNER JOIN household_appliances_store.sales_transaction_item
    ON household_appliances_store.sales_transaction_item.sales_transaction_id = quarter_transactions.sales_transaction_id
INNER JOIN household_appliances_store.product
    ON household_appliances_store.product.product_id = household_appliances_store.sales_transaction_item.product_id
INNER JOIN household_appliances_store.product_model
    ON household_appliances_store.product_model.product_model_id = household_appliances_store.product.product_model_id
INNER JOIN household_appliances_store.brand
    ON household_appliances_store.brand.brand_id = household_appliances_store.product_model.brand_id
INNER JOIN household_appliances_store.category
    ON household_appliances_store.category.category_id = household_appliances_store.product.category_id
GROUP BY
    latest_quarter.quarter_start_date,
    to_char(quarter_transactions.transaction_date, 'YYYY-MM'),
    household_appliances_store.category.category_name,
    household_appliances_store.product.product_name,
    household_appliances_store.brand.brand_name,
    household_appliances_store.product_model.model_name
ORDER BY
    transaction_month,
    category_name,
    product_name;

-- =========================================================
-- 9. READ-ONLY ROLE
-- I create a manager role that can log in and run SELECT only.
-- I do not give write permissions.
-- In a real system I would set the password safely outside the script.
-- =========================================================

DO
$$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'manager_readonly'
    ) THEN
        CREATE ROLE manager_readonly
            LOGIN
            PASSWORD 'ChangeMe_ManagerReadOnly_2026!'
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOINHERIT;
    END IF;
END;
$$;

GRANT CONNECT ON DATABASE household_appliances_store_db TO manager_readonly;
GRANT USAGE ON SCHEMA household_appliances_store TO manager_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA household_appliances_store TO manager_readonly;

ALTER DEFAULT PRIVILEGES IN SCHEMA household_appliances_store
GRANT SELECT ON TABLES TO manager_readonly;
