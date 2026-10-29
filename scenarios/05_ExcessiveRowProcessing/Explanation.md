# Scenario 05 — Excessive row processing

## Mistake

The question is: what is the merchandise total of each **open order placed in June 2025**?

That is 600 orders and 2,400 line items.

`Before.sql` computes the total of **every** order (400,000 orders, 1,600,000 lines), writes them to `#OrderTotals`, and only then keeps June 2025 open orders. The discarded work is about 99.85 percent of the input.

## Why CPU goes up

CPU here is join, aggregate, and tempdb write cost, not a property of `SUM` itself.

* The join reads the covering index `IX_OrderItems_OrderId` or the clustered index for every order. A merge join is a normal choice here because both sides can be ordered by `OrderId`. A hash join is also normal.
* The aggregate builds 400,000 groups. That is a stream aggregate or a hash aggregate over the full line-item set, with a memory grant sized for that input. The plan can be parallel. CPU time can then exceed elapsed time. Record both.
* `SELECT INTO` writes 400,000 rows to tempdb. Those writes show up as logical reads and log activity on `tempdb`, and they are included in the statement's CPU and elapsed time.
* The second statement is cheap. Add its CPU to the first statement's CPU if you want the full before number. The first statement is the problem.

A short memory grant spills the hash aggregate to tempdb. The spill warning is extra evidence. The full scan is already enough.

## Why this pattern, and not an outer `WHERE`

This does **not** demonstrate the bug reliably:

```sql
SELECT *
FROM (
    SELECT ... SUM(...) ...
    FROM dbo.Orders AS o
    INNER JOIN dbo.OrderItems AS oi ON oi.OrderId = o.OrderId
    GROUP BY ...
) AS x
WHERE x.Status = 'Open'
  AND x.OrderDate >= '20250601'
  AND x.OrderDate < '20250701';
```

For a simple derived table, the optimizer pushes `Status` and `OrderDate` below the aggregate when the grouping columns include them. The "outer filter" never executes as written. Chasing it with hints hides the lesson.

Materializing into a temporary table is an optimization fence. People do it so they can inspect the intermediate set, reuse it, or "make the plan simpler." It also forces the engine to finish the expensive statement before it is allowed to see the filter. That is the reproducible mistake.

A multi-statement table-valued function around the unfiltered join is the same fence, with a worse cardinality estimate (often a guess). It is not scripted separately.

## The fix

Filter `dbo.Orders` in the same statement that joins and aggregates. Predicates on `Orders` columns that are also grouping columns can be applied before the line items are aggregated. The optimizer then seeks `IX_Orders_OrderDate` for June 2025 (12,000 orders) and applies `Status = 'Open'` as a residual predicate (600 orders), or seeks a `Status` index if scenario 03's index happens to exist. Either plan touches on the order of 2,400 lines, not 1,600,000.

`IX_Orders_Status_TotalAmount_OrderId` is not part of this fix. `RunBefore.sql` drops it so the before measurement is not helped by it. `RunAfter.sql` may have created it for scenario 03 before scenario 05 runs. That can change which order index is seeked. It cannot make the before pattern cheap, and the after pattern is cheap without it. When you compare scenario 05 in isolation, run `After.sql` without treating the scenario 03 index as a prerequisite.

Compare logical reads on `OrderItems`, then CPU time, then elapsed time. On the before script, add the `SELECT INTO` execution to the small filter that follows it. The after script is one execution. CPU time on the before aggregate can exceed elapsed time when the plan is parallel; record both, and do not treat "CPU higher than elapsed" as a regression by itself.

Logical reads on `OrderItems` should drop from the full line-item index to about 2,400 lines. The scenario scripts return 600 rows, so the grid is not the before cost; the aggregate is. The benchmark scripts still keep that aggregate on the server and print a checksum. Both sides must return 600 rows and the same sum.

Filtering early does not help if the caller actually needs every order's total. The temp table is then the product, and the CPU is the necessary cost of that product. An outer `WHERE` without the temp table often does not show this bug, because the optimizer pushes the predicate down.

`CalculatedTotal` uses the same `decimal(19, 4)` cast in both scripts. It is the pre-tax merchandise total and matches `Orders.TotalAmount` for these rows (verified for the whole table by `04_VerifyData.sql`). Scenario 04's tax function is intentionally not used here.

## Related shapes that also process rows you do not need

These are not the measured query, and they have the same bill:

* `SELECT *` when the covering index could have answered a short column list, followed by key lookups per row.
* A predicate on a joined table written so late, or so wrapped, that it runs after the join has multiplied rows.
* A cursor or `WHILE` loop that loads one order at a time. That is row-by-row processing on top of excessive rows. The set-based form above is the replacement; a cursor would only make the before number larger.

## Version and permissions

Predicate pushdown and temp-table materialization behave this way on SQL Server 2019 and SQL Server 2022. Compatibility level 160 does not push a predicate into a statement that already finished. No extra permission beyond `db_owner` is required. The script creates a temporary table in tempdb, which any user who can run a query can do.
