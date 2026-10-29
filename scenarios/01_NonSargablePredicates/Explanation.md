# Scenario 01 — Non-sargable predicates

## Mistake

`YEAR(OrderDate)` and `MONTH(OrderDate)` hide the column from the optimizer. A predicate is sargable when the optimizer can turn it into a range on an index key. A function, calculation, or conversion applied to the column produces a new value per row, and that value is not the index key.

`IX_Orders_OrderDate` is already there. Adding another copy of the same index does not fix this query. The predicate has to keep `OrderDate` bare.

## Why CPU goes up

The engine reads every row it scans and evaluates `YEAR` and `MONTH` on each one. June 2024 is 12,000 orders out of 400,000 (3 percent). The scan still touches the other 97 percent, and it does extra computational work on every row.

On a parallel scan, `SET STATISTICS TIME` CPU time is the sum of worker time. It can be larger than elapsed time. That is normal. Record both numbers. Logical reads are the stable signal that the scan happened: they stay proportional to the index (or the table), not to 12,000 rows.

At this volume the CPU gap versus a seek may be modest on a fast server. The shape does not change at tens of millions of rows; the CPU cost does, because the expression runs once per scanned row and the scan gets larger. High-frequency calls multiply it again.

## What the plan should show

| Run | Operators | Warning |
| --- | --- | --- |
| Before | Index Scan or Clustered Index Scan. Residual predicate contains `YEAR` / `MONTH`. Often parallel. | None required. The wrapped column is the evidence. |
| After | Index Seek on `IX_Orders_OrderDate`, range 2024-06-01 inclusive to 2024-07-01 exclusive. A Merge Interval, Concatenation, or Nested Loops beside that seek is the normal shape for a pair of range bounds. | None on the column. A convert of the date literal is fine. |

Seek predicates and residual predicates are both visible in the operator properties. A seek with a residual predicate on `YEAR(OrderDate)` would mean the range was not actually applied. This after query should show the range as a seek predicate.

`CAST(OrderDate AS date)` is a poor teaching example of a non-sargable predicate. On current SQL Server builds the optimizer often rewrites `CAST(datetime2 AS date) = '2024-06-15'` into a dynamic range seek. `YEAR` and `MONTH` are not rewritten that way. `CONVERT(varchar(10), OrderDate, 23)` is also not sargable.

`LIKE 'C%'` on `CustomerCode` is sargable. `LEFT(CustomerCode, 1) = 'C'` is not, unless you index a computed column of `LEFT(CustomerCode, 1)`. A computed column is the right tool when the expression itself is the key you must search. It is the wrong tool for a date range you could have written directly.

## The fix

```sql
WHERE o.OrderDate >= '20240601'
  AND o.OrderDate < '20240701';
```

Half-open ranges avoid the `BETWEEN` boundary problem. `BETWEEN '2024-06-01' AND '2024-06-30'` on a `datetime2` column means `<= 2024-06-30 00:00:00`, so every order later on 30 June is lost. If the column is `datetime` (not `datetime2`) and the session language changes, separated literals such as `'2024-06-01'` can be misread. `datetime2` does not have that old `datetime` language bug; unseparated `'20240601'` is still the literal that does not depend on `DATEFORMAT`.

The string is converted once, to `datetime2`. Data type precedence converts the lower type. The column is already `datetime2`, so the column is not wrapped.

## Compare CPU time, elapsed time, and logical reads

Both scripts turn `SET STATISTICS IO` and `SET STATISTICS TIME` on. In the Messages tab, use `SQL Server Execution Times` and the logical reads for `Orders`. Ignore `parse and compile time`. Run each script twice and keep the second execution.

The before scan should show far more logical reads than the after seek. CPU time often drops too. On a fast server and this 400,000-row table the CPU gap can be small; the logical-read gap is the reliable signal. Elapsed time on `Before.sql` and `After.sql` includes SSMS drawing 12,000 rows. `benchmarks/RunBefore.sql` and `RunAfter.sql` aggregate that same query on the server. Use those when you want elapsed time without the grid. Both sides must return 12,000 rows and the same sum of `TotalAmount`.

The rewrite helps when the range is selective and `IX_Orders_OrderDate` exists. If the range is most of the table, a seek and a scan can cost about the same CPU. A second copy of the date index does not fix `YEAR(OrderDate)`.

## What this scenario does not show

* A missing index. The supporting index is created in `database/02_CreateIndexes.sql` before either script runs.
* Implicit conversion. Both queries compare the column with integers (`YEAR` / `MONTH`) or with a date literal converted once. Scenario 02 is the conversion case.
* A filter applied after a join. Scenario 05 is that case.

## Version and permissions

No SQL Server 2022-only feature. Behavior is the same at compatibility level 150 and 160. `SET STATISTICS IO` and `SET STATISTICS TIME` need only permission to run the query. The actual plan needs `SHOWPLAN` in this database, which `db_owner` has.
