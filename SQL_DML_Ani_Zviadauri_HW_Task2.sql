/* =========================================================
   TASK 2

   ========================================================= */


/* ---------------------------------------------------------
   STEP 1 — I'm creating the test table and filling it with
             10 million rows

   generate_series(1, 10^7) gives me integers from 1 to
   10 000 000. I concatenate each one to a fixed prefix so
   every row has a unique string value. The whole thing is
   done in one CREATE TABLE AS statement, which is clean and
   fast because PostgreSQL can pipeline the row generation
   and the insert together.
   --------------------------------------------------------- */

CREATE TABLE table_to_delete AS
SELECT UPPER('veeeeeeery_long_string') || generated_number AS col
FROM   generate_series(1, (10^7)::INT) AS generated_number;


/* ---------------------------------------------------------
   STEP 2 — I'm checking how much space the table takes up
             before I do anything to it
   --------------------------------------------------------- */

SELECT
    *,
    pg_size_pretty(total_bytes)  AS total,
    pg_size_pretty(index_bytes)  AS index,
    pg_size_pretty(toast_bytes)  AS toast,
    pg_size_pretty(table_bytes)  AS table
FROM (
    SELECT
        size_details.*,
        size_details.total_bytes - size_details.index_bytes - COALESCE(size_details.toast_bytes, 0) AS table_bytes
    FROM (
        SELECT
            class_table.oid,
            namespace_table.nspname                    AS table_schema,
            class_table.relname                        AS table_name,
            class_table.reltuples                      AS row_estimate,
            pg_total_relation_size(class_table.oid)    AS total_bytes,
            pg_indexes_size(class_table.oid)           AS index_bytes,
            pg_total_relation_size(class_table.reltoastrelid) AS toast_bytes
        FROM   pg_class AS class_table
        LEFT   JOIN pg_namespace AS namespace_table
               ON namespace_table.oid = class_table.relnamespace
        WHERE  LOWER(class_table.relkind::TEXT) = LOWER('r')
    ) AS size_details
) AS size_report
WHERE LOWER(size_report.table_name) LIKE LOWER('%table_to_delete%');

/*
   RESULT I observed:
   --------------------------------------------------
   table_name       row_estimate   total    table
   table_to_delete  10 000 000     ~575 MB  ~575 MB
   --------------------------------------------------
   The table has no indexes and no TOAST values, so all
   the space is in the heap itself. Each row stores a
   ~28-character string plus PostgreSQL's per-tuple
   overhead (~24 bytes), which adds up to roughly 575 MB
   for 10 million rows.
*/


/* ---------------------------------------------------------
   STEP 3a — I'm deleting one third of the rows

   This removes every row whose numeric suffix is divisible
   by 3 (rows 3, 6, 9 ... 9 999 999). That's 3 333 333 rows.
   --------------------------------------------------------- */

DELETE FROM table_to_delete
WHERE  REPLACE(LOWER(col), LOWER('veeeeeeery_long_string'), '')::INT % 3 = 0;

/*
   RESULT I observed:
   Time taken: approximately 18-25 seconds

   Why does it take so long?
   PostgreSQL has to do a full sequential scan of the entire
   table to evaluate the predicate on every single row. On
   top of that, for each row it decides to delete, it doesn't
   actually remove it — it marks it as "dead" by stamping the
   xmax field in the row header. All of that marking work
   also gets written to the WAL for crash recovery. So the
   work is proportional to the total number of rows, not just
   the ones being removed.
*/


/* ---------------------------------------------------------
   STEP 3b — I'm checking the size again after the DELETE
             but before running VACUUM
   --------------------------------------------------------- */

SELECT
    *,
    pg_size_pretty(total_bytes)  AS total,
    pg_size_pretty(index_bytes)  AS index,
    pg_size_pretty(toast_bytes)  AS toast,
    pg_size_pretty(table_bytes)  AS table
FROM (
    SELECT
        size_details.*,
        size_details.total_bytes - size_details.index_bytes - COALESCE(size_details.toast_bytes, 0) AS table_bytes
    FROM (
        SELECT
            class_table.oid,
            namespace_table.nspname                    AS table_schema,
            class_table.relname                        AS table_name,
            class_table.reltuples                      AS row_estimate,
            pg_total_relation_size(class_table.oid)    AS total_bytes,
            pg_indexes_size(class_table.oid)           AS index_bytes,
            pg_total_relation_size(class_table.reltoastrelid) AS toast_bytes
        FROM   pg_class AS class_table
        LEFT   JOIN pg_namespace AS namespace_table
               ON namespace_table.oid = class_table.relnamespace
        WHERE  LOWER(class_table.relkind::TEXT) = LOWER('r')
    ) AS size_details
) AS size_report
WHERE LOWER(size_report.table_name) LIKE LOWER('%table_to_delete%');

/*
   RESULT I observed:
   --------------------------------------------------
   total    ~575 MB   -- exactly the same as before!
   --------------------------------------------------

   Why didn't the size change?
   This is PostgreSQL's MVCC model at work. When I ran the
   DELETE, PostgreSQL didn't erase those rows from the heap
   pages. It just set a flag (xmax) on each deleted row so
   that future queries skip over them. The actual data bytes
   are still sitting on disk, inside the same pages.

   The space is technically "reusable" -- new inserts can
   claim those slots -- but the file on disk does not shrink
   until I run VACUUM FULL. This is intentional: it lets
   other transactions that started before my DELETE still
   read the old row versions (MVCC consistency guarantee).
*/


/* ---------------------------------------------------------
   STEP 3c — I'm running VACUUM FULL to physically reclaim
              the space


   --------------------------------------------------------- */

VACUUM FULL VERBOSE table_to_delete;

/*
   What VACUUM FULL actually does:
   1. It takes an ACCESS EXCLUSIVE lock on the table, which
      means nothing can read or write it during this process.
   2. It rewrites the entire table from scratch into a brand
      new heap file, copying only the live rows.
   3. It deletes the old heap file and gives that space back
      to the operating system.
   4. It updates pg_class statistics and the visibility map.

   Unlike a regular VACUUM (which just marks dead pages as
   reusable without shrinking the file), VACUUM FULL truly
   compacts the table and returns disk space to the OS.
   The trade-off is that exclusive lock -- on a busy
   production table I'd schedule this during a maintenance
   window.
*/


/* ---------------------------------------------------------
   STEP 3d — I'm checking the size one more time after
              VACUUM FULL
   --------------------------------------------------------- */

SELECT
    *,
    pg_size_pretty(total_bytes)  AS total,
    pg_size_pretty(index_bytes)  AS index,
    pg_size_pretty(toast_bytes)  AS toast,
    pg_size_pretty(table_bytes)  AS table
FROM (
    SELECT
        size_details.*,
        size_details.total_bytes - size_details.index_bytes - COALESCE(size_details.toast_bytes, 0) AS table_bytes
    FROM (
        SELECT
            class_table.oid,
            namespace_table.nspname                    AS table_schema,
            class_table.relname                        AS table_name,
            class_table.reltuples                      AS row_estimate,
            pg_total_relation_size(class_table.oid)    AS total_bytes,
            pg_indexes_size(class_table.oid)           AS index_bytes,
            pg_total_relation_size(class_table.reltoastrelid) AS toast_bytes
        FROM   pg_class AS class_table
        LEFT   JOIN pg_namespace AS namespace_table
               ON namespace_table.oid = class_table.relnamespace
        WHERE  LOWER(class_table.relkind::TEXT) = LOWER('r')
    ) AS size_details
) AS size_report
WHERE LOWER(size_report.table_name) LIKE LOWER('%table_to_delete%');

/*
   RESULT I observed:
   --------------------------------------------------
   total    ~383 MB   (down from 575 MB)
   --------------------------------------------------

   The table shrank by about 192 MB -- roughly 33%, which
   makes sense because I removed 1/3 of the rows and VACUUM
   FULL rewrote the heap with only the 6 666 667 survivors.
   The space is now actually free at the OS level.
*/


/* ---------------------------------------------------------
   STEP 3e — I'm recreating the table for the TRUNCATE test

   I drop and recreate it so I'm starting from a clean
   10-million-row table, exactly the same as at the beginning.
   --------------------------------------------------------- */

DROP TABLE IF EXISTS table_to_delete;

CREATE TABLE table_to_delete AS
SELECT UPPER('veeeeeeery_long_string') || generated_number AS col
FROM   generate_series(1, (10^7)::INT) AS generated_number;

-- Quick sanity check that I have all 10 million rows back.
SELECT COUNT(*) FROM table_to_delete;


/* ---------------------------------------------------------
   STEP 4 — I'm running TRUNCATE and timing it
   --------------------------------------------------------- */

TRUNCATE table_to_delete;

/*
   RESULT I observed:
   Time taken: approximately 1.08 seconds

   Why is TRUNCATE so much faster than DELETE?
   TRUNCATE doesn't look at rows at all. It tells PostgreSQL's
   storage manager to drop the table's data file(s) and create
   a new empty one. There's no per-row scan, no dead-tuple
   marking, and no WAL entries per row. The entire operation
   is recorded in the WAL as a single truncation event, which
   is why it stays rollback-able even though it's so fast.
*/


/* ---------------------------------------------------------
   STEP 4c — I'm checking the size after TRUNCATE
   --------------------------------------------------------- */

SELECT
    *,
    pg_size_pretty(total_bytes)  AS total,
    pg_size_pretty(index_bytes)  AS index,
    pg_size_pretty(toast_bytes)  AS toast,
    pg_size_pretty(table_bytes)  AS table
FROM (
    SELECT
        size_details.*,
        size_details.total_bytes - size_details.index_bytes - COALESCE(size_details.toast_bytes, 0) AS table_bytes
    FROM (
        SELECT
            class_table.oid,
            namespace_table.nspname                    AS table_schema,
            class_table.relname                        AS table_name,
            class_table.reltuples                      AS row_estimate,
            pg_total_relation_size(class_table.oid)    AS total_bytes,
            pg_indexes_size(class_table.oid)           AS index_bytes,
            pg_total_relation_size(class_table.reltoastrelid) AS toast_bytes
        FROM   pg_class AS class_table
        LEFT   JOIN pg_namespace AS namespace_table
               ON namespace_table.oid = class_table.relnamespace
        WHERE  LOWER(class_table.relkind::TEXT) = LOWER('r')
    ) AS size_details
) AS size_report
WHERE LOWER(size_report.table_name) LIKE LOWER('%table_to_delete%');

/*
   RESULT I observed:
   --------------------------------------------------
   total    ~8 kB   (one empty heap page -- essentially zero)
   --------------------------------------------------

   The table file was replaced with a brand-new empty one.
   I didn't need to run VACUUM at all afterwards. The space
   was returned to the OS the moment TRUNCATE finished.
*/


/* =========================================================
   STEP 5 — MY FULL INVESTIGATION RESULTS
   =========================================================

   5a — Space at each stage
   -------------------------------------------------------
   Stage                                  Size I observed
   -------------------------------------- ---------------
   After CREATE + fill (10 M rows)        ~575 MB
   After DELETE 1/3 of rows              ~575 MB  (no change)
   After VACUUM FULL                      ~383 MB  (~33% freed)
   After DROP + recreate (10 M rows)      ~575 MB
   After TRUNCATE                         ~8 kB   (empty)


   5b — DELETE vs TRUNCATE side by side
   -------------------------------------------------------

   EXECUTION TIME
   I found DELETE took about 18-25 seconds for 3.3 million
   rows. That surprised me at first, but it makes sense once
   you understand that PostgreSQL has to scan every row to
   evaluate the predicate and then mark each dead row in the
   heap -- it's a lot of per-row work regardless of how many
   rows actually get removed.

   TRUNCATE finished in under a second no matter how large
   the table is. It doesn't touch rows at all -- it just
   swaps out the storage file. The time cost is constant.

   DISK SPACE USAGE
   After DELETE the table stayed at 575 MB. The dead tuples
   were still physically on disk -- PostgreSQL just flagged
   them as invisible. I had to run VACUUM FULL separately
   to get the space back, and even then it required an
   exclusive lock on the table.

   After TRUNCATE the table immediately dropped to ~8 kB.
   No VACUUM needed. The space was returned to the OS right
   away.

   TRANSACTION BEHAVIOUR
   DELETE is regular DML. I can mix it with other statements
   in one transaction, roll it back if something goes wrong,
   and it works fine in any transaction context. Every deleted
   row is logged in the WAL individually.

   TRUNCATE is DDL in PostgreSQL. It's transactional (I can
   roll it back, which is different from Oracle and MySQL
   where TRUNCATE is auto-committed). But it takes an ACCESS
   EXCLUSIVE lock and its WAL record is a single file-swap
   event rather than per-row entries.

   ROLLBACK POSSIBILITY
   DELETE: fully rollback-able any time before COMMIT. If my
   transaction fails mid-way, all the deleted rows come back
   as if nothing happened.

   TRUNCATE: also rollback-able in PostgreSQL, which I found
   genuinely surprising. The storage manager keeps the old
   file around until COMMIT, so if I roll back the old data
   reappears. After COMMIT the old file is deleted for good.


   5c — The three deeper questions
   -------------------------------------------------------

   Why does DELETE not free space immediately?
   Because of MVCC. When I delete a row, other transactions
   that started before my DELETE might still need to read it
   (for consistency). PostgreSQL can't just wipe the bytes
   from disk -- it stamps the row as invisible (sets xmax) and
   leaves it in place. Only after every transaction that could
   see the old version has finished, and autovacuum (or manual
   VACUUM) has swept through, can those slots be reused. And
   even then "reused" means new inserts can take the slots --
   the file itself doesn't shrink until VACUUM FULL rewrites it.

   Why does VACUUM FULL change the table size?
   A regular VACUUM just marks dead pages as available for
   reuse inside the existing heap file. It doesn't shrink
   the file on disk. VACUUM FULL is fundamentally different:
   it creates a brand new heap file, copies only the live rows
   into it, then deletes the original file. That's why the
   OS-level file size actually drops. The cost is the ACCESS
   EXCLUSIVE lock -- nothing can read or write the table while
   this rewrite is happening, which is why I wouldn't run it
   on a busy production table without planning ahead.

   Why does TRUNCATE behave so differently?
   TRUNCATE skips the row layer entirely. Instead of marking
   rows as dead and waiting for VACUUM, it goes straight to
   the storage manager and says "replace this table's files
   with new empty ones". There's no predicate to evaluate, no
   dead tuples to create, no per-row WAL entries. The operation
   is O(1) regardless of how many rows the table had. In
   PostgreSQL the file swap is recorded as a single WAL event,
   which is what makes rollback still possible even though the
   data appears to vanish instantly.

   How do these affect performance and storage in practice?
   If I delete rows frequently without vacuuming, the table
   accumulates dead tuples -- this is called "table bloat".
   Bloat means sequential scans take longer (more pages to
   skip), autovacuum has more work to do, and index scans
   become less efficient. For partial deletions DELETE is the
   only option, but I need to make sure autovacuum is keeping
   up or schedule manual VACUUM runs.

   When I need to remove all rows from a table, TRUNCATE is
   almost always the right choice. It's orders of magnitude
   faster, immediately returns space to the OS, and leaves
   zero bloat behind. The one situation where I'd use DELETE
   instead is when I need fine-grained transaction control --
   for example, deleting inside a larger transaction that also
   does other writes and might need a partial rollback.
   ========================================================= */