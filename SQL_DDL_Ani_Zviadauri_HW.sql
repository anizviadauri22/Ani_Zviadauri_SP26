-- =============================================================================
-- Task: create a physical DB

-- DESCRIPTION:
--   Physical implementation of the Healthcare Clinic logical data model.
--   The schema is in Third Normal Form (3NF): every non-key attribute
--   depends only on its table's primary key. Redundant data (specializations,
--   staff roles, manufacturers) is moved to separate lookup tables and
--   referenced via foreign keys.

-- NOTE ON RERUNNABILITY:
-- I made this script rerunnable by dropping and recreating the schema
-- healthcare_clinic using CASCADE. This removes existing objects and ensures
-- a clean state on each run. INSERT statements use WHERE NOT EXISTS to
-- prevent duplicate data.
-- =============================================================================
 

-- STEP 1: CREATE DATABASE (run separately)
-- =============================================================================
-- This statement creates the project database.
-- It must be executed separately before running the rest of the script,
-- because PostgreSQL does not allow switching databases within standard SQL.

CREATE DATABASE healthcare_clinic_db;

-- =============================================================================
-- NOTE ON DATABASE EXECUTION:
-- After creating the database, I manually switched the connection
-- to 'healthcare_clinic_db' (e.g., in DBeaver) before executing the
-- remaining script.
-- =============================================================================


DROP SCHEMA IF EXISTS healthcare_clinic CASCADE;
CREATE SCHEMA healthcare_clinic;
SET search_path TO healthcare_clinic;


-- =============================================================================
-- WHY DDL ORDER MATTERS
-- =============================================================================
-- PostgreSQL resolves FOREIGN KEY references at CREATE TABLE time.
-- If a child table is created before its parent, PostgreSQL raises:
--   ERROR: relation "<parent>" does not exist
-- or
--   ERROR: there is no unique constraint matching given keys
--         for referenced table "<parent>"
--
-- The correct order is: parent tables first, then child tables.
-- The DROP SCHEMA CASCADE above handles reverse-order cleanup automatically.
-- =============================================================================
 
 
-- =============================================================================
-- TABLE 1: staff_roles   (parent -> staff)
-- =============================================================================
-- DATA TYPE RATIONALE:
--   role_name VARCHAR(100): role labels are short human-readable strings.
--   Risk of wrong type: using a numeric type would prevent storing text
--   values at all. Using CHAR(100) would pad every value with blanks,
--   wasting storage and causing subtle equality-check bugs.
--
-- CONSTRAINT: UNIQUE (constraint 4)
--   Prevents two rows both storing 'Nurse', which would make the lookup
--   table ambiguous. Without UNIQUE, duplicate role names could be inserted
--   and JOINs or application logic depending on a single canonical row
--   would silently return unexpected results.
--
-- CONSTRAINT: NOT NULL on role_name (constraint 5)
--   A role record with no name is meaningless and would break any UI or
--   report that displays the role. Without NOT NULL, NULL rows could
--   accumulate silently.
-- =============================================================================
 
CREATE TABLE healthcare_clinic.staff_roles (
    staff_role_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_name       VARCHAR(100) NOT NULL UNIQUE
);
 
 
-- =============================================================================
-- TABLE 2: specializations   (parent -> doctors)
-- =============================================================================
-- DATA TYPE RATIONALE:
--   name VARCHAR(100): specialization names are text labels.
--   Risk: too-small VARCHAR would silently truncate long names (PostgreSQL
--   actually raises an error on overflow, but MySQL would silently truncate).
--
-- CONSTRAINT: UNIQUE on name (constraint 4)
--   Prevents 'Cardiology' being stored as two separate rows, which would
--   create ambiguity when doctors reference it.
--   Without UNIQUE, duplicate specializations accumulate and aggregation
--   queries (e.g., count doctors per specialization) return wrong totals.
--
-- CONSTRAINT: NOT NULL on name (constraint 5)
--   A specialization with no name cannot be meaningfully displayed or joined.
-- =============================================================================
 
CREATE TABLE healthcare_clinic.specializations (
    specialization_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name                VARCHAR(100) NOT NULL UNIQUE
);
 
 
-- =============================================================================
-- TABLE 3: manufacturers   (parent -> medications)
-- =============================================================================
-- 3NF ADDITION NOTE:
--   The logical model document (section 8) explicitly includes manufacturers
--   as a separate table to avoid repeating company names across medication rows.
--   Storing manufacturer as a VARCHAR column directly inside medications would
--   create a transitive dependency (medication_id -> manufacturer_name ->
--   manufacturer_address etc.) and violate 3NF.
--   This table is therefore part of the approved logical model.
--
-- DATA TYPE RATIONALE:
--   name VARCHAR(200): pharmaceutical company names can be long.
--   Risk: VARCHAR(50) might truncate real names such as
--   'F. Hoffmann-La Roche AG', causing INSERT errors or data loss.
--
-- CONSTRAINT: UNIQUE on name (constraint 4)
--   Prevents the same manufacturer being stored with two different IDs,
--   which would break FK integrity of the medications table.
--
-- CONSTRAINT: NOT NULL on name (constraint 5)
--   A manufacturer record with no name cannot be identified or displayed.
-- =============================================================================
 
CREATE TABLE healthcare_clinic.manufacturers (
    manufacturer_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name              VARCHAR(200) NOT NULL UNIQUE
);
 
 
-- =============================================================================
-- TABLE 4: patients   (parent -> appointments)
-- =============================================================================
-- DATA TYPE RATIONALE:
--   date_of_birth DATE: only the calendar date matters; storing as TIMESTAMP
--   would waste 4 extra bytes per row and add false time-precision.
--   Risk of wrong type: VARCHAR('1990-05-13') allows invalid values like
--   '1990-13-99' and makes age calculations impossible without casting.
--
--   gender VARCHAR(10) with CHECK: the logical model specifies an ENUM of
--   ('Male','Female','Other'). PostgreSQL supports CREATE TYPE ... AS ENUM,
--   but VARCHAR + CHECK is more portable and easier to ALTER later (adding
--   a new valid value requires only changing the CHECK, not dropping and
--   recreating the ENUM type).
--
--   phone VARCHAR(20): phone numbers contain '+', spaces, and dashes.
--   Risk: storing as INT or BIGINT drops the leading '+' and all formatting.
--
--   email VARCHAR(255): 254 is the RFC 5321 maximum; 255 is standard practice.
--   Risk: VARCHAR(50) would reject long but valid email addresses.
--
-- NOTE ON email UNIQUENESS:
--   The logical model document explicitly states: "I did not define email as
--   a UNIQUE attribute in the patients table because multiple patients from
--   the same household/family may share the same contact email address."
--   UNIQUE is therefore intentionally absent here.
--
-- CONSTRAINT 1 - date > 2000-01-01:
--   Prevents test/placeholder dates like '1900-01-01' or '0001-01-01'.
--   Without this CHECK, bad ETL loads or manual mistakes could insert
--   impossible dates that distort age calculations and reporting filters.
--
-- CONSTRAINT 3 - restricted value set for gender:
--   Prevents free-text variants like 'M', 'male', 'MALE', 'Fmale'.
--   Without this CHECK, GROUP BY gender in reports would produce dozens
--   of distinct values instead of three, making the column useless for BI.
--
-- CONSTRAINT 5 - NOT NULL on first_name, last_name, date_of_birth:
--   A patient record without a name or date of birth cannot be identified
--   clinically or legally. Without NOT NULL, incomplete records could
--   accumulate and pass silently through application validation.
-- =============================================================================
 
CREATE TABLE healthcare_clinic.patients (
    patient_id      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name      VARCHAR(100)    NOT NULL,
    last_name       VARCHAR(100)    NOT NULL,
    date_of_birth   DATE            NOT NULL,
    gender          VARCHAR(10),
    phone           VARCHAR(20),
    email           VARCHAR(255),
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
 
    -- Constraint 1: date must be after 2000-01-01
    CONSTRAINT chk_patients_dob_after_2000
        CHECK (date_of_birth > DATE '2000-01-01'),
 
    -- Constraint 3: gender restricted to logical-model values
    CONSTRAINT chk_patients_gender
        CHECK (gender IN ('Male', 'Female', 'Other'))
);
 
 
-- =============================================================================
-- TABLE 5: staff   (self-referencing)
-- =============================================================================
-- DATA TYPE RATIONALE:
--   hire_date DATE: staff hire dates have no time component needed.
--   Risk: VARCHAR would allow '2020-25-99' as a value, making date
--   comparisons and tenure calculations impossible.
--
--   supervisor_id INT: must match the PK type to allow FK creation.
--   Risk: mismatched types (e.g., BIGINT vs INT) prevent FK creation.
--
-- FOREIGN KEY - staff_role_id -> staff_roles:
--   If FK is missing, staff rows could store any integer as staff_role_id,
--   including IDs of deleted or non-existent roles. Role-based access
--   control and reports grouped by role would silently return wrong results.
--
-- FOREIGN KEY - supervisor_id -> staff (self-reference):
--   Enforces that a supervisor must themselves be a staff member.
--   If FK is missing, supervisor_id could reference a deleted employee,
--   creating ghost entries in org-chart queries.
--   NULL is allowed: top-level managers have no supervisor.
--   ON DELETE SET NULL: if a supervisor is deleted, their reports'
--   supervisor_id is set to NULL rather than blocking the delete.
--
-- CONSTRAINT 1 - hire_date > 2000-01-01:
--   Prevents obviously incorrect hire dates such as '1850-01-01'.
--   Without this, historical data migrations could import junk dates
--   that skew tenure statistics and payroll calculations.
--
-- CONSTRAINT 5 - NOT NULL on first_name, last_name, staff_role_id:
--   A staff record must have a name and a role to be operationally useful.
-- =============================================================================
 
CREATE TABLE healthcare_clinic.staff (
    staff_id        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name      VARCHAR(100)    NOT NULL,
    last_name       VARCHAR(100)    NOT NULL,
    staff_role_id   INT             NOT NULL,
    supervisor_id   INT,
    hire_date       DATE,
 
    CONSTRAINT chk_staff_hire_date
        CHECK (hire_date IS NULL OR hire_date > DATE '2000-01-01'),
 
    CONSTRAINT fk_staff_role
        FOREIGN KEY (staff_role_id)
        REFERENCES healthcare_clinic.staff_roles (staff_role_id),
 
    CONSTRAINT fk_staff_supervisor
        FOREIGN KEY (supervisor_id)
        REFERENCES healthcare_clinic.staff (staff_id)
        ON DELETE SET NULL
);
 
 
-- =============================================================================
-- TABLE 6: doctors   (parent -> appointments, prescriptions)
-- =============================================================================
-- DATA TYPE RATIONALE:
--   license_number VARCHAR(50): license numbers are alphanumeric codes.
--   Risk: INT type would fail for codes containing letters (e.g. 'LIC456').
--   Risk: TEXT with no length limit allows arbitrarily long values that
--   would fail external validation systems expecting short codes.
--
-- FOREIGN KEY - specialization_id -> specializations:
--   If FK is missing, a doctor could reference a deleted or non-existent
--   specialization, giving patients incorrect information about the
--   doctor's expertise and breaking specialty-based routing logic.
--   ON DELETE SET NULL: if a specialization is retired, the doctor row
--   is kept but specialization_id is cleared rather than blocking the delete.
--
-- CONSTRAINT 4 - UNIQUE on license_number:
--   Two doctors cannot legally share the same medical license number.
--   Without UNIQUE, duplicate license numbers could be inserted, making
--   license-based lookups and regulatory reporting unreliable.
--
-- CONSTRAINT 1 - hire_date > 2000-01-01:
--   Prevents placeholder or migration-artifact dates.
--   Without this, invalid dates would distort tenure and payroll reports.
--
-- CONSTRAINT 5 - NOT NULL on first_name, last_name, license_number:
--   A doctor record without a name or license is legally and clinically
--   meaningless and could create liability issues.
-- =============================================================================
 
CREATE TABLE healthcare_clinic.doctors (
    doctor_id           INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name          VARCHAR(100)    NOT NULL,
    last_name           VARCHAR(100)    NOT NULL,
    specialization_id   INT,
    license_number      VARCHAR(50)     NOT NULL UNIQUE,
    hire_date           DATE,
 
    CONSTRAINT chk_doctors_hire_date
        CHECK (hire_date IS NULL OR hire_date > DATE '2000-01-01'),
 
    CONSTRAINT fk_doctors_specialization
        FOREIGN KEY (specialization_id)
        REFERENCES healthcare_clinic.specializations (specialization_id)
        ON DELETE SET NULL
);
 
 
-- =============================================================================
-- TABLE 7: appointments   (central hub; parent -> treatments, diagnostic_tests,
--                          prescriptions, bills)
-- =============================================================================
-- DATA TYPE RATIONALE:
--   appointment_time TIMESTAMP: appointments have both a date and a time.
--   Risk: DATE type loses the time component, making it impossible to
--   detect or prevent double-booking of the same doctor at the same time.
--
--   status VARCHAR(20) with CHECK: logical model specifies ENUM of
--   ('scheduled','completed','cancelled'). VARCHAR + CHECK is used for
--   the same portability reason explained in the patients table.
--
-- FOREIGN KEY - patient_id -> patients:
--   If FK is missing, an appointment could reference a deleted or
--   non-existent patient, making scheduling, billing and clinical records
--   impossible to reconcile.
--
-- FOREIGN KEY - doctor_id -> doctors:
--   If FK is missing, an appointment could reference a non-existent doctor,
--   breaking clinical workflow, liability tracking and scheduling reports.
--
-- CONSTRAINT 1 - appointment_time > 2000-01-01:
--   Prevents test/placeholder timestamps.
--   Without this, invalid appointments could skew scheduling analytics.
--
-- CONSTRAINT 3 - restricted status values:
--   Prevents typos like 'schedueld', 'done', 'in progress'.
--   Without this CHECK, GROUP BY status in reporting would produce
--   inconsistent results and downstream billing logic would silently fail.
--
-- CONSTRAINT 4 - UNIQUE (patient_id, doctor_id, appointment_time):
--   Prevents the same patient being booked with the same doctor at the
--   exact same moment, which is a logical impossibility.
--   Without this, duplicate scheduling rows could be inserted by
--   concurrent requests or repeated script runs.
--
-- CONSTRAINT 5 - NOT NULL on patient_id, doctor_id, appointment_time, status:
--   An appointment must always have a patient, a doctor, a scheduled time
--   and a status. Without NOT NULL, incomplete records would break all
--   dependent clinical and financial queries.
-- =============================================================================
 
CREATE TABLE healthcare_clinic.appointments (
    appointment_id      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id          INT             NOT NULL,
    doctor_id           INT             NOT NULL,
    appointment_time    TIMESTAMP       NOT NULL,
    status              VARCHAR(20)     NOT NULL,
    reason              TEXT,
    created_at          TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
 
    CONSTRAINT chk_appointments_time
        CHECK (appointment_time > TIMESTAMP '2000-01-01 00:00:00'),
 
    CONSTRAINT chk_appointments_status
        CHECK (status IN ('scheduled', 'completed', 'cancelled')),
 
    CONSTRAINT uq_appointments_slot
        UNIQUE (patient_id, doctor_id, appointment_time),
 
    CONSTRAINT fk_appointments_patient
        FOREIGN KEY (patient_id)
        REFERENCES healthcare_clinic.patients (patient_id),
 
    CONSTRAINT fk_appointments_doctor
        FOREIGN KEY (doctor_id)
        REFERENCES healthcare_clinic.doctors (doctor_id)
);
 
 
-- =============================================================================
-- TABLE 8: treatments   (child of appointments)
-- =============================================================================
-- DATA TYPE RATIONALE:
--   description TEXT: treatment descriptions have no predictable length limit.
--   Risk: VARCHAR(200) would truncate long clinical descriptions, losing
--   medically important detail that could affect continuity of care.
--
--   treatment_date TIMESTAMP: a treatment has a specific date and time
--   (e.g., surgery at 09:30), not just a date.
--   Risk: DATE type loses intra-day ordering for multiple treatments
--   performed during the same appointment.
--
-- FOREIGN KEY - appointment_id -> appointments:
--   If FK is missing, treatment records could reference non-existent
--   appointments, creating orphan clinical records with no patient or
--   doctor context. Such records would be invisible in appointment-based
--   queries and impossible to audit or bill against.
--
-- CONSTRAINT 1 - treatment_date > 2000-01-01: prevents placeholder dates.
--
-- CONSTRAINT 5 - NOT NULL on appointment_id, treatment_date:
--   Without NOT NULL on appointment_id, treatments would be orphaned.
-- =============================================================================
 
CREATE TABLE healthcare_clinic.treatments (
    treatment_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_id  INT         NOT NULL,
    description     TEXT,
    treatment_date  TIMESTAMP   NOT NULL,
 
    CONSTRAINT chk_treatments_date
        CHECK (treatment_date > TIMESTAMP '2000-01-01 00:00:00'),
 
    CONSTRAINT fk_treatments_appointment
        FOREIGN KEY (appointment_id)
        REFERENCES healthcare_clinic.appointments (appointment_id)
);
 
 
-- =============================================================================
-- TABLE 9: diagnostic_tests   (child of appointments)
-- =============================================================================
-- DATA TYPE RATIONALE:
--   test_name VARCHAR(200): test names like 'High-Resolution Computed
--   Tomography (HRCT) Chest' can be long. VARCHAR(50) would truncate.
--
--   result TEXT: lab result text varies wildly in length. A full
--   pathology report can be thousands of characters.
--   Risk: VARCHAR(255) would truncate or reject long results,
--   causing loss of critical diagnostic information.
--
-- FOREIGN KEY - appointment_id -> appointments:
--   If FK is missing, test records could exist with no appointment context,
--   making it impossible to attribute them to a patient, doctor, or visit.
--
-- CONSTRAINT 1 - test_date > 2000-01-01: prevents invalid dates.
--
-- CONSTRAINT 5 - NOT NULL on appointment_id, test_name, test_date:
--   A test without a name cannot be identified; without an appointment
--   it cannot be billed or reviewed in a clinical context.
-- =============================================================================
 
CREATE TABLE healthcare_clinic.diagnostic_tests (
    diagnostic_test_id  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_id      INT             NOT NULL,
    test_name           VARCHAR(200)    NOT NULL,
    result              TEXT,
    test_date           TIMESTAMP       NOT NULL,
 
    CONSTRAINT chk_diagnostic_tests_date
        CHECK (test_date > TIMESTAMP '2000-01-01 00:00:00'),
 
    CONSTRAINT fk_diagnostic_tests_appointment
        FOREIGN KEY (appointment_id)
        REFERENCES healthcare_clinic.appointments (appointment_id)
);
 
 
-- =============================================================================
-- TABLE 10: prescriptions   (child of appointments & doctors;
--                            parent -> prescription_items)
-- =============================================================================
-- FOREIGN KEY - appointment_id -> appointments:
--   If FK is missing, prescriptions could be created with no clinical
--   context, making it impossible to trace which visit generated them.
--   This creates legal liability and billing gaps.
--
-- FOREIGN KEY - doctor_id -> doctors:
--   The logical model explicitly stores doctor_id on prescriptions
--   separately from the appointment's doctor_id to record which doctor
--   authorized the prescription (may differ in edge cases such as
--   co-signing or on-call cover).
--   If FK is missing, a prescription could reference a doctor who no
--   longer exists, creating a medico-legal liability.
--
-- CONSTRAINT 5 - NOT NULL on appointment_id, doctor_id:
--   A prescription must always have a clinical and authoring context.
-- =============================================================================
 
CREATE TABLE healthcare_clinic.prescriptions (
    prescription_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_id  INT         NOT NULL,
    doctor_id       INT         NOT NULL,
    created_at      TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
 
    CONSTRAINT fk_prescriptions_appointment
        FOREIGN KEY (appointment_id)
        REFERENCES healthcare_clinic.appointments (appointment_id),
 
    CONSTRAINT fk_prescriptions_doctor
        FOREIGN KEY (doctor_id)
        REFERENCES healthcare_clinic.doctors (doctor_id)
);
 
 
-- =============================================================================
-- TABLE 11: medications   (parent -> prescription_items)
-- =============================================================================
-- DATA TYPE RATIONALE:
--   name VARCHAR(200): drug trade names can be long
--   (e.g., 'Acetylsalicylic Acid Dispersible Tablets 300mg').
--   Risk: VARCHAR(50) would reject or truncate legitimate names.
--
-- FOREIGN KEY - manufacturer_id -> manufacturers:
--   If FK is missing, a medication could reference a deleted or non-existent
--   manufacturer, making drug provenance tracking impossible and violating
--   pharmaceutical regulatory requirements.
--   ON DELETE SET NULL: if a manufacturer is removed, the medication is
--   retained but its manufacturer link is cleared.
--
-- CONSTRAINT 4 - UNIQUE on name:
--   Prevents the same drug name being inserted twice.
--   Without UNIQUE, duplicate medication rows would lead to split
--   prescription histories and incorrect dispensing counts.
--
-- CONSTRAINT 5 - NOT NULL on name:
--   A medication with no name cannot be identified by pharmacists or
--   clinical systems.
-- =============================================================================
 
CREATE TABLE healthcare_clinic.medications (
    medication_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(200)    NOT NULL UNIQUE,
    manufacturer_id INT,
 
    CONSTRAINT fk_medications_manufacturer
        FOREIGN KEY (manufacturer_id)
        REFERENCES healthcare_clinic.manufacturers (manufacturer_id)
        ON DELETE SET NULL
);
 
 
-- =============================================================================
-- TABLE 12: prescription_items   (junction; child of prescriptions & medications)
-- =============================================================================
-- DATA TYPE RATIONALE:
--   dosage VARCHAR(50): dosages are text like '500mg', '2 x 20mg'.
--   Risk: NUMERIC would fail for expressions like '1-2 tablets'.
--   frequency VARCHAR(50): free text like 'Once a day', 'Every 8 hours'.
--   Risk: too restrictive a CHECK set would reject valid clinical instructions.
--
-- COMPOSITE PRIMARY KEY (constraint 4 - UNIQUE):
--   Prevents the same medication being listed twice in the same prescription.
--   Without the composite PK, a pharmacist could receive a prescription
--   with 'Ibuprofen' on two lines with different dosages, creating a
--   dangerous ambiguity about which instruction to follow.
--
-- FOREIGN KEY - prescription_id -> prescriptions:
--   If FK is missing, prescription_items could reference deleted prescriptions,
--   orphaning medication line items that can no longer be traced to a patient.
--
-- FOREIGN KEY - medication_id -> medications:
--   If FK is missing, an item could reference a deleted medication,
--   making dispensing records untraceable.
--
-- CONSTRAINT 5 - NOT NULL on dosage, frequency:
--   A prescription item without a dosage or frequency is clinically
--   incomplete and potentially dangerous. A pharmacist cannot safely
--   dispense medication without both fields.
-- =============================================================================
 
CREATE TABLE healthcare_clinic.prescription_items (
    prescription_id INT NOT NULL,
    medication_id   INT NOT NULL,
    dosage          VARCHAR(50) NOT NULL,
    frequency       VARCHAR(50) NOT NULL,
 
    CONSTRAINT pk_prescription_items
        PRIMARY KEY (prescription_id, medication_id),
 
    CONSTRAINT fk_prescription_items_prescription
        FOREIGN KEY (prescription_id)
        REFERENCES healthcare_clinic.prescriptions (prescription_id),
 
    CONSTRAINT fk_prescription_items_medication
        FOREIGN KEY (medication_id)
        REFERENCES healthcare_clinic.medications (medication_id)
);
 
 
-- =============================================================================
-- TABLE 13: bills   (child of appointments; parent -> payments)
-- =============================================================================
-- DATA TYPE RATIONALE:
--   amount NUMERIC(10,2): exact decimal arithmetic is essential for money.
--   Risk: FLOAT or REAL uses IEEE 754 binary floating point, which cannot
--   represent 0.1 exactly. Summing many FLOAT amounts (e.g., 0.1 + 0.2)
--   produces values like 0.30000000000000004, causing penny-rounding
--   errors that are unacceptable in financial records and audits.
--
-- FOREIGN KEY - appointment_id -> appointments:
--   If FK is missing, bills could reference deleted appointments,
--   making it impossible to reconcile charges against clinical services.
--   Revenue reports would include amounts with no supporting visit record.
--
-- CONSTRAINT 2 - amount >= 0:
--   Prevents negative bill amounts which are logically impossible for a
--   charge. Without this CHECK, bad ETL or application bugs could insert
--   negative amounts, corrupting revenue totals and allowing fraudulent
--   credit entries.
--
-- CONSTRAINT 3 - restricted status values:
--   Prevents free-text variants like 'PAID', 'Payed', 'open'.
--   Without this CHECK, billing dashboards and payment reconciliation
--   logic filtering on status would return inconsistent results.
--
-- CONSTRAINT 5 - NOT NULL on appointment_id, amount, status:
--   A bill without an amount or status has no financial meaning.
-- =============================================================================
 
CREATE TABLE healthcare_clinic.bills (
    bill_id         INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_id  INT             NOT NULL,
    amount          NUMERIC(10,2)   NOT NULL,
    status          VARCHAR(20)     NOT NULL,
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
 
    CONSTRAINT chk_bills_amount_nonnegative
        CHECK (amount >= 0),
 
    CONSTRAINT chk_bills_status
        CHECK (status IN ('pending', 'paid', 'cancelled')),
 
    CONSTRAINT fk_bills_appointment
        FOREIGN KEY (appointment_id)
        REFERENCES healthcare_clinic.appointments (appointment_id)
);
 
 
-- =============================================================================
-- TABLE 14: payments   (child of bills)
-- =============================================================================
-- DATA TYPE RATIONALE:
--   payment_date TIMESTAMP: a payment occurs at a specific date and time,
--   needed for audit trails and same-day sequencing.
--   Risk: DATE type loses the time component, making it impossible to
--   sequence multiple payments made on the same day.
--
--   amount NUMERIC(10,2): same money-precision reasoning as bills.amount.
--   Risk: FLOAT causes binary rounding errors that make payment totals
--   diverge from bill amounts, breaking reconciliation.
--
--   method VARCHAR(20) with CHECK: logical model specifies ENUM of
--   ('cash','card','transfer').
--
-- FOREIGN KEY - bill_id -> bills:
--   If FK is missing, a payment could reference a deleted bill, creating
--   financial records with no corresponding charge. This would break
--   accounts-receivable reconciliation and regulatory audits.
--
-- CONSTRAINT 1 - payment_date > 2000-01-01:
--   Prevents invalid dates. Without this, system-clock bugs or bad ETL
--   could insert payments dated in the past century.
--
-- CONSTRAINT 2 - amount >= 0:
--   Prevents negative payment amounts. Without this, a refund could be
--   represented as a negative payment, corrupting revenue totals.
--   Refunds should be modelled as a separate event if required.
--
-- CONSTRAINT 3 - restricted method values:
--   Prevents free-text like 'Credit Card', 'CASH', 'wire'.
--   Without this CHECK, payment method analysis would produce many
--   spurious categories instead of three clean ones.
--
-- CONSTRAINT 5 - NOT NULL on bill_id, payment_date, amount, method:
--   A payment must always have a bill to pay against, a date, an amount
--   and a method. Without NOT NULL, incomplete payment records would
--   pass silently into financial reports.
-- =============================================================================
 
CREATE TABLE healthcare_clinic.payments (
    payment_id      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bill_id         INT             NOT NULL,
    payment_date    TIMESTAMP       NOT NULL,
    amount          NUMERIC(10,2)   NOT NULL,
    method          VARCHAR(20)     NOT NULL,
 
    CONSTRAINT chk_payments_date
        CHECK (payment_date > TIMESTAMP '2000-01-01 00:00:00'),
 
    CONSTRAINT chk_payments_amount_nonnegative
        CHECK (amount >= 0),
 
    CONSTRAINT chk_payments_method
        CHECK (method IN ('cash', 'card', 'transfer')),
 
    CONSTRAINT fk_payments_bill
        FOREIGN KEY (bill_id)
        REFERENCES healthcare_clinic.bills (bill_id)
);
 
 
-- =============================================================================
-- INDEXES ON FOREIGN KEY COLUMNS
-- =============================================================================
-- PostgreSQL automatically indexes PRIMARY KEY and UNIQUE columns.
-- Foreign key columns are NOT automatically indexed.
-- Without these indexes, every FK lookup (e.g., finding all appointments
-- for a patient) requires a full sequential scan of the child table,
-- which becomes very slow as data grows.
-- These indexes also speed up ON DELETE constraint checks on parent tables.
-- =============================================================================
 
CREATE INDEX idx_staff_role_id            ON healthcare_clinic.staff            (staff_role_id);
CREATE INDEX idx_staff_supervisor_id      ON healthcare_clinic.staff            (supervisor_id);
CREATE INDEX idx_doctors_spec_id          ON healthcare_clinic.doctors          (specialization_id);
CREATE INDEX idx_appointments_patient_id  ON healthcare_clinic.appointments     (patient_id);
CREATE INDEX idx_appointments_doctor_id   ON healthcare_clinic.appointments     (doctor_id);
CREATE INDEX idx_treatments_appt_id       ON healthcare_clinic.treatments       (appointment_id);
CREATE INDEX idx_diag_tests_appt_id       ON healthcare_clinic.diagnostic_tests (appointment_id);
CREATE INDEX idx_prescriptions_appt_id    ON healthcare_clinic.prescriptions    (appointment_id);
CREATE INDEX idx_prescriptions_doctor_id  ON healthcare_clinic.prescriptions    (doctor_id);
CREATE INDEX idx_medications_mfr_id       ON healthcare_clinic.medications      (manufacturer_id);
CREATE INDEX idx_bills_appt_id            ON healthcare_clinic.bills            (appointment_id);
CREATE INDEX idx_payments_bill_id         ON healthcare_clinic.payments         (bill_id);
 
 
-- =============================================================================
-- DATA INSERTION
-- =============================================================================
-- HOW CONSISTENCY IS ENSURED AND RELATIONSHIPS PRESERVED:
--   1. Rows are inserted into parent tables first, then child tables,
--      mirroring the DDL order. This guarantees FK references already
--      exist when child rows are inserted.
--   2. WHERE NOT EXISTS subqueries prevent duplicate rows on reruns
--      by checking a business key unique to each row before inserting.
--   3. Foreign-key column values in child inserts are resolved via
--      subqueries on business keys (e.g., license_number, role_name)
--      rather than hardcoded identity values. This means the script
--      works regardless of which identity value GENERATED ALWAYS AS
--      IDENTITY assigns, keeping it truly rerunnable.
--   4. LOWER() is used on both sides of text comparisons in WHERE clauses
--      to guard against accidental case mismatches in lookup values.
--   5. All NOT NULL columns are supplied; all CHECK constraints are
--      satisfied by the inserted values.
-- =============================================================================
 
-- ----------------------------------------------------------------------------
-- staff_roles  (2 rows from logical model + 3 additional for realism)
-- ----------------------------------------------------------------------------
INSERT INTO healthcare_clinic.staff_roles (role_name)
SELECT v.role_name
FROM (VALUES
    ('Nurse'),
    ('Administrator'),
    ('Receptionist'),
    ('Lab Technician'),
    ('Pharmacist')
) AS v (role_name)
WHERE NOT EXISTS (
    SELECT 1
    FROM   healthcare_clinic.staff_roles AS staff_role
    WHERE  LOWER(staff_role.role_name) = LOWER(v.role_name)
);
 
-- ----------------------------------------------------------------------------
-- specializations  (2 rows from logical model + 3 additional)
-- ----------------------------------------------------------------------------
INSERT INTO healthcare_clinic.specializations (name)
SELECT v.name
FROM (VALUES
    ('Endocrinology'),
    ('Otolaryngology'),
    ('Cardiology'),
    ('Pediatrics'),
    ('General Practice')
) AS v (name)
WHERE NOT EXISTS (
    SELECT 1
    FROM   healthcare_clinic.specializations AS specialization
    WHERE  LOWER(specialization.name) = LOWER(v.name)
);
 
-- ----------------------------------------------------------------------------
-- manufacturers  (2 rows from logical model + 2 additional)
-- ----------------------------------------------------------------------------
INSERT INTO healthcare_clinic.manufacturers (name)
SELECT v.name
FROM (VALUES
    ('BASF'),
    ('Roche'),
    ('Pfizer'),
    ('Novartis')
) AS v (name)
WHERE NOT EXISTS (
    SELECT 1
    FROM   healthcare_clinic.manufacturers AS manufacturer
    WHERE  LOWER(manufacturer.name) = LOWER(v.name)
);
 
-- ----------------------------------------------------------------------------
-- medications  (2 rows from logical model + 2 additional)
-- manufacturer_id resolved by name to avoid hardcoding identity values.
-- LOWER() used on both sides for case-safe manufacturer name lookup.
-- ----------------------------------------------------------------------------
INSERT INTO healthcare_clinic.medications (name, manufacturer_id)
SELECT v.medication_name, manufacturer.manufacturer_id
FROM (VALUES
    ('Ibuprofen',   'BASF'),
    ('Tamiflu',     'Roche'),
    ('Amoxicillin', 'Pfizer'),
    ('Paracetamol', 'Novartis')
) AS v (medication_name, manufacturer_name)
INNER JOIN healthcare_clinic.manufacturers AS manufacturer
    ON LOWER(manufacturer.name) = LOWER(v.manufacturer_name)
WHERE NOT EXISTS (
    SELECT 1
    FROM   healthcare_clinic.medications AS medication
    WHERE  LOWER(medication.name) = LOWER(v.medication_name)
);
 
-- ----------------------------------------------------------------------------
-- patients  (2 rows from logical model + 2 additional)
-- Business key for duplicate check: (first_name, last_name, date_of_birth).
-- email is intentionally not UNIQUE per the logical model document.
-- date_of_birth values satisfy CHECK > 2000-01-01.
-- gender values satisfy CHECK IN ('Male','Female','Other').
-- LOWER() used on name comparisons.
-- ----------------------------------------------------------------------------
INSERT INTO healthcare_clinic.patients
    (first_name, last_name, date_of_birth, gender, phone, email)
SELECT v.first_name, v.last_name, v.dob, v.gender, v.phone, v.email
FROM (VALUES
    ('Maia',   'Dolidze',        DATE '2001-05-13', 'Female', '595677733', 'maia.dolidze@gmail.com'),
    ('Luka',   'Avaliani',       DATE '2001-02-24', 'Male',   '599025414', 'avalianiuka@gmail.com'),
    ('Nino',   'Tkeshelashvili', DATE '2003-08-17', 'Female', '599111222', 'nino.tke@gmail.com'),
    ('Giorgi', 'Meparidze',      DATE '2002-11-30', 'Male',   '598333444', 'giorgi.me@gmail.com')
) AS v (first_name, last_name, dob, gender, phone, email)
WHERE NOT EXISTS (
    SELECT 1
    FROM   healthcare_clinic.patients AS patient
    WHERE  LOWER(patient.first_name)    = LOWER(v.first_name)
      AND  LOWER(patient.last_name)     = LOWER(v.last_name)
      AND  patient.date_of_birth        = v.dob
);
 
-- ----------------------------------------------------------------------------
-- staff  (2 rows from logical model + 1 additional)
-- Top-level manager inserted first (supervisor_id = NULL).
-- Subordinates resolve supervisor by last_name to avoid hardcoding ID.
-- LOWER() used on all name comparisons.
-- ----------------------------------------------------------------------------
INSERT INTO healthcare_clinic.staff
    (first_name, last_name, staff_role_id, supervisor_id, hire_date)
SELECT
    'Anna',
    'Barbakadze',
    (SELECT staff_role_id
     FROM   healthcare_clinic.staff_roles AS staff_role
     WHERE  LOWER(staff_role.role_name) = LOWER('Nurse')),
    NULL,
    DATE '2023-02-11'
WHERE NOT EXISTS (
    SELECT 1
    FROM   healthcare_clinic.staff AS staff_member
    WHERE  LOWER(staff_member.first_name) = LOWER('Anna')
      AND  LOWER(staff_member.last_name)  = LOWER('Barbakadze')
);
 
INSERT INTO healthcare_clinic.staff
    (first_name, last_name, staff_role_id, supervisor_id, hire_date)
SELECT
    'Goga',
    'Telia',
    (SELECT staff_role_id
     FROM   healthcare_clinic.staff_roles AS staff_role
     WHERE  LOWER(staff_role.role_name) = LOWER('Administrator')),
    (SELECT staff_id
     FROM   healthcare_clinic.staff AS staff_member
     WHERE  LOWER(staff_member.last_name) = LOWER('Barbakadze')
     LIMIT  1),
    DATE '2020-04-21'
WHERE NOT EXISTS (
    SELECT 1
    FROM   healthcare_clinic.staff AS staff_member
    WHERE  LOWER(staff_member.first_name) = LOWER('Goga')
      AND  LOWER(staff_member.last_name)  = LOWER('Telia')
);
 
INSERT INTO healthcare_clinic.staff
    (first_name, last_name, staff_role_id, supervisor_id, hire_date)
SELECT
    'Salome',
    'Kvariani',
    (SELECT staff_role_id
     FROM   healthcare_clinic.staff_roles AS staff_role
     WHERE  LOWER(staff_role.role_name) = LOWER('Receptionist')),
    (SELECT staff_id
     FROM   healthcare_clinic.staff AS staff_member
     WHERE  LOWER(staff_member.last_name) = LOWER('Barbakadze')
     LIMIT  1),
    DATE '2021-09-01'
WHERE NOT EXISTS (
    SELECT 1
    FROM   healthcare_clinic.staff AS staff_member
    WHERE  LOWER(staff_member.first_name) = LOWER('Salome')
      AND  LOWER(staff_member.last_name)  = LOWER('Kvariani')
);
 
-- ----------------------------------------------------------------------------
-- doctors  (2 rows from logical model + 1 additional)
-- specialization_id resolved by name with LOWER() for case safety.
-- license_number is the business key for duplicate detection.
-- hire_date values satisfy CHECK > 2000-01-01.
-- ----------------------------------------------------------------------------
INSERT INTO healthcare_clinic.doctors
    (first_name, last_name, specialization_id, license_number, hire_date)
SELECT
    'Giorgi',
    'Bakhtadze',
    (SELECT specialization_id
     FROM   healthcare_clinic.specializations AS specialization
     WHERE  LOWER(specialization.name) = LOWER('Endocrinology')),
    'LIC456',
    DATE '2020-02-10'
WHERE NOT EXISTS (
    SELECT 1
    FROM   healthcare_clinic.doctors AS doctor
    WHERE  doctor.license_number = 'LIC456'
);
 
INSERT INTO healthcare_clinic.doctors
    (first_name, last_name, specialization_id, license_number, hire_date)
SELECT
    'Tamuna',
    'Tsabadze',
    (SELECT specialization_id
     FROM   healthcare_clinic.specializations AS specialization
     WHERE  LOWER(specialization.name) = LOWER('Otolaryngology')),
    'LIC880',
    DATE '2017-09-15'
WHERE NOT EXISTS (
    SELECT 1
    FROM   healthcare_clinic.doctors AS doctor
    WHERE  doctor.license_number = 'LIC880'
);
 
INSERT INTO healthcare_clinic.doctors
    (first_name, last_name, specialization_id, license_number, hire_date)
SELECT
    'Lasha',
    'Beridze',
    (SELECT specialization_id
     FROM   healthcare_clinic.specializations AS specialization
     WHERE  LOWER(specialization.name) = LOWER('Cardiology')),
    'LIC321',
    DATE '2015-03-20'
WHERE NOT EXISTS (
    SELECT 1
    FROM   healthcare_clinic.doctors AS doctor
    WHERE  doctor.license_number = 'LIC321'
);
 
-- ----------------------------------------------------------------------------
-- appointments  (2 rows from logical model + 2 additional)
-- patient_id and doctor_id resolved via business keys with LOWER().
-- appointment_time satisfies CHECK > 2000-01-01.
-- status satisfies CHECK IN ('scheduled','completed','cancelled').
-- Duplicate check uses the UNIQUE constraint columns.
-- ----------------------------------------------------------------------------
INSERT INTO healthcare_clinic.appointments
    (patient_id, doctor_id, appointment_time, status, reason)
SELECT
    patient.patient_id,
    doctor.doctor_id,
    TIMESTAMP '2025-05-15 15:05:00',
    'scheduled',
    'Vaccination'
FROM       healthcare_clinic.patients AS patient
INNER JOIN healthcare_clinic.doctors  AS doctor
        ON doctor.license_number = 'LIC456'
WHERE LOWER(patient.first_name) = LOWER('Maia')
  AND LOWER(patient.last_name)  = LOWER('Dolidze')
  AND NOT EXISTS (
      SELECT 1
      FROM   healthcare_clinic.appointments AS appointment
      WHERE  appointment.patient_id       = patient.patient_id
        AND  appointment.doctor_id        = doctor.doctor_id
        AND  appointment.appointment_time = TIMESTAMP '2025-05-15 15:05:00'
  );
 
INSERT INTO healthcare_clinic.appointments
    (patient_id, doctor_id, appointment_time, status, reason)
SELECT
    patient.patient_id,
    doctor.doctor_id,
    TIMESTAMP '2025-06-13 11:02:00',
    'completed',
    'Acne consultation'
FROM       healthcare_clinic.patients AS patient
INNER JOIN healthcare_clinic.doctors  AS doctor
        ON doctor.license_number = 'LIC880'
WHERE LOWER(patient.first_name) = LOWER('Luka')
  AND LOWER(patient.last_name)  = LOWER('Avaliani')
  AND NOT EXISTS (
      SELECT 1
      FROM   healthcare_clinic.appointments AS appointment
      WHERE  appointment.patient_id       = patient.patient_id
        AND  appointment.doctor_id        = doctor.doctor_id
        AND  appointment.appointment_time = TIMESTAMP '2025-06-13 11:02:00'
  );
 
INSERT INTO healthcare_clinic.appointments
    (patient_id, doctor_id, appointment_time, status, reason)
SELECT
    patient.patient_id,
    doctor.doctor_id,
    TIMESTAMP '2025-07-01 09:30:00',
    'completed',
    'Cardiac screening'
FROM       healthcare_clinic.patients AS patient
INNER JOIN healthcare_clinic.doctors  AS doctor
        ON doctor.license_number = 'LIC321'
WHERE LOWER(patient.first_name) = LOWER('Nino')
  AND LOWER(patient.last_name)  = LOWER('Tkeshelashvili')
  AND NOT EXISTS (
      SELECT 1
      FROM   healthcare_clinic.appointments AS appointment
      WHERE  appointment.patient_id       = patient.patient_id
        AND  appointment.doctor_id        = doctor.doctor_id
        AND  appointment.appointment_time = TIMESTAMP '2025-07-01 09:30:00'
  );
 
INSERT INTO healthcare_clinic.appointments
    (patient_id, doctor_id, appointment_time, status, reason)
SELECT
    patient.patient_id,
    doctor.doctor_id,
    TIMESTAMP '2025-07-15 14:00:00',
    'cancelled',
    'Endocrinology follow-up'
FROM       healthcare_clinic.patients AS patient
INNER JOIN healthcare_clinic.doctors  AS doctor
        ON doctor.license_number = 'LIC456'
WHERE LOWER(patient.first_name) = LOWER('Giorgi')
  AND LOWER(patient.last_name)  = LOWER('Meparidze')
  AND NOT EXISTS (
      SELECT 1
      FROM   healthcare_clinic.appointments AS appointment
      WHERE  appointment.patient_id       = patient.patient_id
        AND  appointment.doctor_id        = doctor.doctor_id
        AND  appointment.appointment_time = TIMESTAMP '2025-07-15 14:00:00'
  );
 
-- ----------------------------------------------------------------------------
-- treatments  (2 rows from logical model — both for Maia Dolidze's appointment)
-- ----------------------------------------------------------------------------
INSERT INTO healthcare_clinic.treatments
    (appointment_id, description, treatment_date)
SELECT
    appointment.appointment_id,
    'Intramuscular Injection',
    TIMESTAMP '2025-05-15 15:10:00'
FROM       healthcare_clinic.appointments AS appointment
INNER JOIN healthcare_clinic.patients     AS patient
        ON patient.patient_id = appointment.patient_id
WHERE LOWER(patient.first_name) = LOWER('Maia')
  AND LOWER(patient.last_name)  = LOWER('Dolidze')
  AND NOT EXISTS (
      SELECT 1
      FROM   healthcare_clinic.treatments AS treatment
      WHERE  treatment.appointment_id = appointment.appointment_id
        AND  treatment.description    = 'Intramuscular Injection'
        AND  treatment.treatment_date = TIMESTAMP '2025-05-15 15:10:00'
  );
 
INSERT INTO healthcare_clinic.treatments
    (appointment_id, description, treatment_date)
SELECT
    appointment.appointment_id,
    'Chemical Peel',
    TIMESTAMP '2025-05-15 15:25:00'
FROM       healthcare_clinic.appointments AS appointment
INNER JOIN healthcare_clinic.patients     AS patient
        ON patient.patient_id = appointment.patient_id
WHERE LOWER(patient.first_name) = LOWER('Maia')
  AND LOWER(patient.last_name)  = LOWER('Dolidze')
  AND NOT EXISTS (
      SELECT 1
      FROM   healthcare_clinic.treatments AS treatment
      WHERE  treatment.appointment_id = appointment.appointment_id
        AND  treatment.description    = 'Chemical Peel'
        AND  treatment.treatment_date = TIMESTAMP '2025-05-15 15:25:00'
  );
 
-- ----------------------------------------------------------------------------
-- diagnostic_tests  (2 rows from logical model)
-- ----------------------------------------------------------------------------
INSERT INTO healthcare_clinic.diagnostic_tests
    (appointment_id, test_name, result, test_date)
SELECT
    appointment.appointment_id,
    'Temperature Check',
    'Normal',
    TIMESTAMP '2025-05-15 13:20:00'
FROM       healthcare_clinic.appointments    AS appointment
INNER JOIN healthcare_clinic.patients        AS patient
        ON patient.patient_id = appointment.patient_id
WHERE LOWER(patient.first_name) = LOWER('Maia')
  AND LOWER(patient.last_name)  = LOWER('Dolidze')
  AND NOT EXISTS (
      SELECT 1
      FROM   healthcare_clinic.diagnostic_tests AS diag_test
      WHERE  diag_test.appointment_id = appointment.appointment_id
        AND  diag_test.test_name      = 'Temperature Check'
        AND  diag_test.test_date      = TIMESTAMP '2025-05-15 13:20:00'
  );
 
INSERT INTO healthcare_clinic.diagnostic_tests
    (appointment_id, test_name, result, test_date)
SELECT
    appointment.appointment_id,
    'Skin Swab Culture',
    'Positive',
    TIMESTAMP '2025-06-13 15:10:00'
FROM       healthcare_clinic.appointments    AS appointment
INNER JOIN healthcare_clinic.patients        AS patient
        ON patient.patient_id = appointment.patient_id
WHERE LOWER(patient.first_name) = LOWER('Luka')
  AND LOWER(patient.last_name)  = LOWER('Avaliani')
  AND NOT EXISTS (
      SELECT 1
      FROM   healthcare_clinic.diagnostic_tests AS diag_test
      WHERE  diag_test.appointment_id = appointment.appointment_id
        AND  diag_test.test_name      = 'Skin Swab Culture'
        AND  diag_test.test_date      = TIMESTAMP '2025-06-13 15:10:00'
  );
 
-- ----------------------------------------------------------------------------
-- bills  (2 rows from logical model + 2 additional)
-- amount >= 0 satisfied; status IN ('pending','paid','cancelled') satisfied.
-- ----------------------------------------------------------------------------
INSERT INTO healthcare_clinic.bills (appointment_id, amount, status)
SELECT appointment.appointment_id, 100.00, 'paid'
FROM       healthcare_clinic.appointments AS appointment
INNER JOIN healthcare_clinic.patients     AS patient
        ON patient.patient_id = appointment.patient_id
WHERE LOWER(patient.first_name) = LOWER('Maia')
  AND LOWER(patient.last_name)  = LOWER('Dolidze')
  AND NOT EXISTS (
      SELECT 1
      FROM   healthcare_clinic.bills AS bill
      WHERE  bill.appointment_id = appointment.appointment_id
        AND  bill.amount         = 100.00
        AND  bill.status         = 'paid'
  );
 
INSERT INTO healthcare_clinic.bills (appointment_id, amount, status)
SELECT appointment.appointment_id, 55.00, 'pending'
FROM       healthcare_clinic.appointments AS appointment
INNER JOIN healthcare_clinic.patients     AS patient
        ON patient.patient_id = appointment.patient_id
WHERE LOWER(patient.first_name) = LOWER('Luka')
  AND LOWER(patient.last_name)  = LOWER('Avaliani')
  AND NOT EXISTS (
      SELECT 1
      FROM   healthcare_clinic.bills AS bill
      WHERE  bill.appointment_id = appointment.appointment_id
        AND  bill.amount         = 55.00
        AND  bill.status         = 'pending'
  );
 
INSERT INTO healthcare_clinic.bills (appointment_id, amount, status)
SELECT appointment.appointment_id, 200.00, 'paid'
FROM       healthcare_clinic.appointments AS appointment
INNER JOIN healthcare_clinic.patients     AS patient
        ON patient.patient_id = appointment.patient_id
WHERE LOWER(patient.first_name) = LOWER('Nino')
  AND LOWER(patient.last_name)  = LOWER('Tkeshelashvili')
  AND NOT EXISTS (
      SELECT 1
      FROM   healthcare_clinic.bills AS bill
      WHERE  bill.appointment_id = appointment.appointment_id
        AND  bill.amount         = 200.00
        AND  bill.status         = 'paid'
  );
 
INSERT INTO healthcare_clinic.bills (appointment_id, amount, status)
SELECT appointment.appointment_id, 0.00, 'cancelled'
FROM       healthcare_clinic.appointments AS appointment
INNER JOIN healthcare_clinic.patients     AS patient
        ON patient.patient_id = appointment.patient_id
WHERE LOWER(patient.first_name) = LOWER('Giorgi')
  AND LOWER(patient.last_name)  = LOWER('Meparidze')
  AND NOT EXISTS (
      SELECT 1
      FROM   healthcare_clinic.bills AS bill
      WHERE  bill.appointment_id = appointment.appointment_id
        AND  bill.amount         = 0.00
        AND  bill.status         = 'cancelled'
  );
 
-- ----------------------------------------------------------------------------
-- payments  (2 rows from logical model + 1 additional)
-- amount >= 0; method IN ('cash','card','transfer'); date > 2000-01-01.
-- ----------------------------------------------------------------------------
INSERT INTO healthcare_clinic.payments (bill_id, payment_date, amount, method)
SELECT bill.bill_id, TIMESTAMP '2025-05-15 16:00:00', 100.00, 'cash'
FROM       healthcare_clinic.bills        AS bill
INNER JOIN healthcare_clinic.appointments AS appointment
        ON appointment.appointment_id = bill.appointment_id
INNER JOIN healthcare_clinic.patients     AS patient
        ON patient.patient_id = appointment.patient_id
WHERE LOWER(patient.first_name) = LOWER('Maia')
  AND LOWER(patient.last_name)  = LOWER('Dolidze')
  AND NOT EXISTS (
      SELECT 1
      FROM   healthcare_clinic.payments AS payment
      WHERE  payment.bill_id      = bill.bill_id
        AND  payment.payment_date = TIMESTAMP '2025-05-15 16:00:00'
        AND  payment.amount       = 100.00
        AND  payment.method       = 'cash'
  );
 
INSERT INTO healthcare_clinic.payments (bill_id, payment_date, amount, method)
SELECT bill.bill_id, TIMESTAMP '2025-06-13 17:00:00', 25.00, 'card'
FROM       healthcare_clinic.bills        AS bill
INNER JOIN healthcare_clinic.appointments AS appointment
        ON appointment.appointment_id = bill.appointment_id
INNER JOIN healthcare_clinic.patients     AS patient
        ON patient.patient_id = appointment.patient_id
WHERE LOWER(patient.first_name) = LOWER('Luka')
  AND LOWER(patient.last_name)  = LOWER('Avaliani')
  AND NOT EXISTS (
      SELECT 1
      FROM   healthcare_clinic.payments AS payment
      WHERE  payment.bill_id      = bill.bill_id
        AND  payment.payment_date = TIMESTAMP '2025-06-13 17:00:00'
        AND  payment.amount       = 25.00
        AND  payment.method       = 'card'
  );
 
INSERT INTO healthcare_clinic.payments (bill_id, payment_date, amount, method)
SELECT bill.bill_id, TIMESTAMP '2025-07-02 10:00:00', 200.00, 'transfer'
FROM       healthcare_clinic.bills        AS bill
INNER JOIN healthcare_clinic.appointments AS appointment
        ON appointment.appointment_id = bill.appointment_id
INNER JOIN healthcare_clinic.patients     AS patient
        ON patient.patient_id = appointment.patient_id
WHERE LOWER(patient.first_name) = LOWER('Nino')
  AND LOWER(patient.last_name)  = LOWER('Tkeshelashvili')
  AND NOT EXISTS (
      SELECT 1
      FROM   healthcare_clinic.payments AS payment
      WHERE  payment.bill_id      = bill.bill_id
        AND  payment.payment_date = TIMESTAMP '2025-07-02 10:00:00'
        AND  payment.amount       = 200.00
        AND  payment.method       = 'transfer'
  );
 
-- ----------------------------------------------------------------------------
-- prescriptions  (2 rows from logical model)
-- ----------------------------------------------------------------------------
INSERT INTO healthcare_clinic.prescriptions (appointment_id, doctor_id)
SELECT appointment.appointment_id, appointment.doctor_id
FROM       healthcare_clinic.appointments AS appointment
INNER JOIN healthcare_clinic.patients     AS patient
        ON patient.patient_id = appointment.patient_id
WHERE LOWER(patient.first_name) = LOWER('Maia')
  AND LOWER(patient.last_name)  = LOWER('Dolidze')
  AND NOT EXISTS (
      SELECT 1
      FROM   healthcare_clinic.prescriptions AS prescription
      WHERE  prescription.appointment_id = appointment.appointment_id
        AND  prescription.doctor_id      = appointment.doctor_id
  );
 
INSERT INTO healthcare_clinic.prescriptions (appointment_id, doctor_id)
SELECT appointment.appointment_id, appointment.doctor_id
FROM       healthcare_clinic.appointments AS appointment
INNER JOIN healthcare_clinic.patients     AS patient
        ON patient.patient_id = appointment.patient_id
WHERE LOWER(patient.first_name) = LOWER('Luka')
  AND LOWER(patient.last_name)  = LOWER('Avaliani')
  AND NOT EXISTS (
      SELECT 1
      FROM   healthcare_clinic.prescriptions AS prescription
      WHERE  prescription.appointment_id = appointment.appointment_id
        AND  prescription.doctor_id      = appointment.doctor_id
  );
 
-- ----------------------------------------------------------------------------
-- prescription_items  (2 rows from logical model + 1 additional)
-- Composite PK prevents the same medication appearing twice per prescription.
-- dosage and frequency are NOT NULL.
-- LOWER() used on medication name lookup.
-- ----------------------------------------------------------------------------
INSERT INTO healthcare_clinic.prescription_items
    (prescription_id, medication_id, dosage, frequency)
SELECT
    prescription.prescription_id,
    medication.medication_id,
    '500mg',
    'Once a day'
FROM       healthcare_clinic.prescriptions  AS prescription
INNER JOIN healthcare_clinic.appointments   AS appointment
        ON appointment.appointment_id = prescription.appointment_id
INNER JOIN healthcare_clinic.patients       AS patient
        ON patient.patient_id = appointment.patient_id
INNER JOIN healthcare_clinic.medications    AS medication
        ON LOWER(medication.name) = LOWER('Ibuprofen')
WHERE LOWER(patient.first_name) = LOWER('Maia')
  AND LOWER(patient.last_name)  = LOWER('Dolidze')
  AND NOT EXISTS (
      SELECT 1
      FROM   healthcare_clinic.prescription_items AS presc_item
      WHERE  presc_item.prescription_id = prescription.prescription_id
        AND  presc_item.medication_id   = medication.medication_id
  );
 
INSERT INTO healthcare_clinic.prescription_items
    (prescription_id, medication_id, dosage, frequency)
SELECT
    prescription.prescription_id,
    medication.medication_id,
    '200mg',
    'Twice a day'
FROM       healthcare_clinic.prescriptions  AS prescription
INNER JOIN healthcare_clinic.appointments   AS appointment
        ON appointment.appointment_id = prescription.appointment_id
INNER JOIN healthcare_clinic.patients       AS patient
        ON patient.patient_id = appointment.patient_id
INNER JOIN healthcare_clinic.medications    AS medication
        ON LOWER(medication.name) = LOWER('Tamiflu')
WHERE LOWER(patient.first_name) = LOWER('Maia')
  AND LOWER(patient.last_name)  = LOWER('Dolidze')
  AND NOT EXISTS (
      SELECT 1
      FROM   healthcare_clinic.prescription_items AS presc_item
      WHERE  presc_item.prescription_id = prescription.prescription_id
        AND  presc_item.medication_id   = medication.medication_id
  );
 
INSERT INTO healthcare_clinic.prescription_items
    (prescription_id, medication_id, dosage, frequency)
SELECT
    prescription.prescription_id,
    medication.medication_id,
    '250mg',
    'Three times a day'
FROM       healthcare_clinic.prescriptions  AS prescription
INNER JOIN healthcare_clinic.appointments   AS appointment
        ON appointment.appointment_id = prescription.appointment_id
INNER JOIN healthcare_clinic.patients       AS patient
        ON patient.patient_id = appointment.patient_id
INNER JOIN healthcare_clinic.medications    AS medication
        ON LOWER(medication.name) = LOWER('Amoxicillin')
WHERE LOWER(patient.first_name) = LOWER('Luka')
  AND LOWER(patient.last_name)  = LOWER('Avaliani')
  AND NOT EXISTS (
      SELECT 1
      FROM   healthcare_clinic.prescription_items AS presc_item
      WHERE  presc_item.prescription_id = prescription.prescription_id
        AND  presc_item.medication_id   = medication.medication_id
  );
 
 
-- =============================================================================
-- STEP 8: Add record_ts to every table via ALTER TABLE
-- =============================================================================
-- WHY THREE STEPS:
--   The task requires adding record_ts AFTER the inserts so that existing
--   rows are visible during the backfill. Adding NOT NULL directly on
--   ADD COLUMN would fail because existing rows would have no value.
--   The safe sequence is:
--     1. Add the column as nullable (existing rows are accepted with NULL).
--     2. Set DEFAULT CURRENT_DATE for all future inserts.
--     3. Backfill existing rows: UPDATE ... WHERE record_ts IS NULL.
--     4. Enforce NOT NULL now that every row has a value.
-- =============================================================================
 
ALTER TABLE healthcare_clinic.staff_roles         ADD COLUMN IF NOT EXISTS record_ts DATE;
ALTER TABLE healthcare_clinic.specializations     ADD COLUMN IF NOT EXISTS record_ts DATE;
ALTER TABLE healthcare_clinic.manufacturers       ADD COLUMN IF NOT EXISTS record_ts DATE;
ALTER TABLE healthcare_clinic.patients            ADD COLUMN IF NOT EXISTS record_ts DATE;
ALTER TABLE healthcare_clinic.staff               ADD COLUMN IF NOT EXISTS record_ts DATE;
ALTER TABLE healthcare_clinic.doctors             ADD COLUMN IF NOT EXISTS record_ts DATE;
ALTER TABLE healthcare_clinic.appointments        ADD COLUMN IF NOT EXISTS record_ts DATE;
ALTER TABLE healthcare_clinic.treatments          ADD COLUMN IF NOT EXISTS record_ts DATE;
ALTER TABLE healthcare_clinic.diagnostic_tests    ADD COLUMN IF NOT EXISTS record_ts DATE;
ALTER TABLE healthcare_clinic.prescriptions       ADD COLUMN IF NOT EXISTS record_ts DATE;
ALTER TABLE healthcare_clinic.medications         ADD COLUMN IF NOT EXISTS record_ts DATE;
ALTER TABLE healthcare_clinic.prescription_items  ADD COLUMN IF NOT EXISTS record_ts DATE;
ALTER TABLE healthcare_clinic.bills               ADD COLUMN IF NOT EXISTS record_ts DATE;
ALTER TABLE healthcare_clinic.payments            ADD COLUMN IF NOT EXISTS record_ts DATE;
 
ALTER TABLE healthcare_clinic.staff_roles         ALTER COLUMN record_ts SET DEFAULT CURRENT_DATE;
ALTER TABLE healthcare_clinic.specializations     ALTER COLUMN record_ts SET DEFAULT CURRENT_DATE;
ALTER TABLE healthcare_clinic.manufacturers       ALTER COLUMN record_ts SET DEFAULT CURRENT_DATE;
ALTER TABLE healthcare_clinic.patients            ALTER COLUMN record_ts SET DEFAULT CURRENT_DATE;
ALTER TABLE healthcare_clinic.staff               ALTER COLUMN record_ts SET DEFAULT CURRENT_DATE;
ALTER TABLE healthcare_clinic.doctors             ALTER COLUMN record_ts SET DEFAULT CURRENT_DATE;
ALTER TABLE healthcare_clinic.appointments        ALTER COLUMN record_ts SET DEFAULT CURRENT_DATE;
ALTER TABLE healthcare_clinic.treatments          ALTER COLUMN record_ts SET DEFAULT CURRENT_DATE;
ALTER TABLE healthcare_clinic.diagnostic_tests    ALTER COLUMN record_ts SET DEFAULT CURRENT_DATE;
ALTER TABLE healthcare_clinic.prescriptions       ALTER COLUMN record_ts SET DEFAULT CURRENT_DATE;
ALTER TABLE healthcare_clinic.medications         ALTER COLUMN record_ts SET DEFAULT CURRENT_DATE;
ALTER TABLE healthcare_clinic.prescription_items  ALTER COLUMN record_ts SET DEFAULT CURRENT_DATE;
ALTER TABLE healthcare_clinic.bills               ALTER COLUMN record_ts SET DEFAULT CURRENT_DATE;
ALTER TABLE healthcare_clinic.payments            ALTER COLUMN record_ts SET DEFAULT CURRENT_DATE;
 
UPDATE healthcare_clinic.staff_roles        SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
UPDATE healthcare_clinic.specializations    SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
UPDATE healthcare_clinic.manufacturers      SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
UPDATE healthcare_clinic.patients           SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
UPDATE healthcare_clinic.staff              SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
UPDATE healthcare_clinic.doctors            SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
UPDATE healthcare_clinic.appointments       SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
UPDATE healthcare_clinic.treatments         SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
UPDATE healthcare_clinic.diagnostic_tests   SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
UPDATE healthcare_clinic.prescriptions      SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
UPDATE healthcare_clinic.medications        SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
UPDATE healthcare_clinic.prescription_items SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
UPDATE healthcare_clinic.bills              SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
UPDATE healthcare_clinic.payments           SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
 
ALTER TABLE healthcare_clinic.staff_roles         ALTER COLUMN record_ts SET NOT NULL;
ALTER TABLE healthcare_clinic.specializations     ALTER COLUMN record_ts SET NOT NULL;
ALTER TABLE healthcare_clinic.manufacturers       ALTER COLUMN record_ts SET NOT NULL;
ALTER TABLE healthcare_clinic.patients            ALTER COLUMN record_ts SET NOT NULL;
ALTER TABLE healthcare_clinic.staff               ALTER COLUMN record_ts SET NOT NULL;
ALTER TABLE healthcare_clinic.doctors             ALTER COLUMN record_ts SET NOT NULL;
ALTER TABLE healthcare_clinic.appointments        ALTER COLUMN record_ts SET NOT NULL;
ALTER TABLE healthcare_clinic.treatments          ALTER COLUMN record_ts SET NOT NULL;
ALTER TABLE healthcare_clinic.diagnostic_tests    ALTER COLUMN record_ts SET NOT NULL;
ALTER TABLE healthcare_clinic.prescriptions       ALTER COLUMN record_ts SET NOT NULL;
ALTER TABLE healthcare_clinic.medications         ALTER COLUMN record_ts SET NOT NULL;
ALTER TABLE healthcare_clinic.prescription_items  ALTER COLUMN record_ts SET NOT NULL;
ALTER TABLE healthcare_clinic.bills               ALTER COLUMN record_ts SET NOT NULL;
ALTER TABLE healthcare_clinic.payments            ALTER COLUMN record_ts SET NOT NULL;
 
 
-- =============================================================================
-- VERIFICATION: record_ts must be set for every existing row
-- total_rows must equal ts_set in every result row (zero NULLs)
-- =============================================================================
 
SELECT 'appointments'        AS table_name, COUNT(*) AS total_rows, COUNT(record_ts) AS ts_set FROM healthcare_clinic.appointments
UNION ALL
SELECT 'bills',              COUNT(*), COUNT(record_ts) FROM healthcare_clinic.bills
UNION ALL
SELECT 'diagnostic_tests',   COUNT(*), COUNT(record_ts) FROM healthcare_clinic.diagnostic_tests
UNION ALL
SELECT 'doctors',            COUNT(*), COUNT(record_ts) FROM healthcare_clinic.doctors
UNION ALL
SELECT 'manufacturers',      COUNT(*), COUNT(record_ts) FROM healthcare_clinic.manufacturers
UNION ALL
SELECT 'medications',        COUNT(*), COUNT(record_ts) FROM healthcare_clinic.medications
UNION ALL
SELECT 'patients',           COUNT(*), COUNT(record_ts) FROM healthcare_clinic.patients
UNION ALL
SELECT 'payments',           COUNT(*), COUNT(record_ts) FROM healthcare_clinic.payments
UNION ALL
SELECT 'prescription_items', COUNT(*), COUNT(record_ts) FROM healthcare_clinic.prescription_items
UNION ALL
SELECT 'prescriptions',      COUNT(*), COUNT(record_ts) FROM healthcare_clinic.prescriptions
UNION ALL
SELECT 'specializations',    COUNT(*), COUNT(record_ts) FROM healthcare_clinic.specializations
UNION ALL
SELECT 'staff',              COUNT(*), COUNT(record_ts) FROM healthcare_clinic.staff
UNION ALL
SELECT 'staff_roles',        COUNT(*), COUNT(record_ts) FROM healthcare_clinic.staff_roles
UNION ALL
SELECT 'treatments',         COUNT(*), COUNT(record_ts) FROM healthcare_clinic.treatments
ORDER BY table_name;
 
-- Expected: total_rows = ts_set for every row (no NULLs in record_ts)
-- Row counts: appointments=4, bills=4, diagnostic_tests=2, doctors=3,
--             manufacturers=4, medications=4, patients=4, payments=3,
--             prescription_items=3, prescriptions=2, specializations=5,
--             staff=3, staff_roles=5, treatments=2  =>  TOTAL = 48 rows