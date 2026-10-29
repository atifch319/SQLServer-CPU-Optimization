# Scenario 03 — Unnecessary sorting

## Mistake

The statement asks for the 100 shipped orders with the highest `TotalAmount`, tie-broken by `OrderId`. That order is a real requirement. The CPU cost is not "someone typed `ORDER BY`." The cost is that no index supplies those rows in that order, so a Sort operator has to manufacture it from hundreds of thousands of rows.

`Before.sql` drops `IX_Orders_Status_TotalAmount_OrderId` so the script still shows the sort after you have run `After.sql`.

## Why CPU goes up

There are 320,000 shipped orders. `TOP (100)` does not mean "touch 100 rows" unless an index already leads with `Status` and then `TotalAmount`, `OrderId`.

Without that index the optimizer typically:

1. Finds the shipped rows (scan plus residual predicate, or a scan of a non-covering structure).
2. Runs a **Top N Sort**: a Sort operator whose properties show `TopN = 100`.

A Top N Sort keeps a small heap of 100 winners, so it is cheaper than sorting all 320,000 rows into a fully ordered stream. It still **reads all 320,000 candidates** and does comparison work for each of them. CPU and the memory grant follow the input size. If the grant is short, the sort spills to tempdb (a warning on the Sort operator). A spill adds IO and usually more CPU. You do not need a spill to conclude the sort is the problem; the operator on a 320,000-row input is enough.

`IX_Orders_OrderDate` does not answer `ORDER BY TotalAmount`. An index removes a sort only when its key order matches the `ORDER BY` after the equality predicates.

## What the plan should show

| Run | Operators |
| --- | --- |
| Before | Scan (clustered or `IX_Orders_OrderDate`) and a Sort. The Sort properties include the Top N. Actual rows into the sort are far above 100. |
| After | Seek or ordered scan of `IX_Orders_Status_TotalAmount_OrderId` for `Status = 'Shipped'`. No Sort. Actual rows out of the seek are 100. |

On the after plan, open the seek and confirm **Ordered = True** (the tooltip or properties). An unordered seek plus a later Sort means the index was used for filtering only, and this scenario is not fixed yet.

## The index

```sql
CREATE NONCLUSTERED INDEX IX_Orders_Status_TotalAmount_OrderId
    ON dbo.Orders (Status, TotalAmount DESC, OrderId DESC)
    INCLUDE (OrderNumber, OrderDate);
```

Key order:

1. `Status` first, because the predicate is `Status = 'Shipped'` (equality).
2. `TotalAmount DESC`, `OrderId DESC` next, because they are the `ORDER BY`.

Putting `TotalAmount` first would not serve `WHERE Status = 'Shipped' ORDER BY TotalAmount`. The equality column has to lead.

`DESC` mirrors the query. An all-`ASC` key on `(Status, TotalAmount, OrderId)` is often just as good: the storage engine can scan that range backward, and backward scans still avoid an explicit Sort when **every** sort column reverses together. Mixed directions (`TotalAmount DESC, OrderId ASC`) are the case that needs the key direction written explicitly, because one backward scan cannot reverse only one column.

`OrderId` is already the clustered key sitting in every nonclustered leaf. It is still declared in the key here because the `ORDER BY` uses it. `INCLUDE` is for columns that are selected but not used for seek or order: `OrderNumber`, `OrderDate`.

## Compare CPU time, elapsed time, and logical reads

Record `SQL Server Execution Times` for the `SELECT`, not for `CREATE INDEX` in `After.sql`. The build is a separate batch and is not the query. Run the `SELECT` a second time after the build so the measured execution is not the first compile.

CPU time should drop because the Top N Sort no longer touches 320,000 shipped rows. Logical reads should drop from a scan of the shipped set to about 100 index rows. Elapsed time on the scenario scripts includes returning 100 rows, which is cheap next to the sort; still prefer `benchmarks/RunBefore.sql` and `RunAfter.sql` when you want the server-only number. Both sides must return the same 100 orders. The benchmark prints the sum of `TotalAmount` so you can check.

The index does not help a different `ORDER BY`. It also costs extra CPU on every insert and update of `Status`, `TotalAmount`, or `OrderId`. A sort of a few hundred rows is rarely worth that write cost. If the caller does not need this order, delete the `ORDER BY` instead of adding an index.

## When the sort is the wrong argument

* If the consumer does not need a deterministic order, delete the `ORDER BY`. That is a different fix and it changes the contract. This scenario keeps the contract and removes the operator.
* `ORDER BY` inside a derived table or view does not guarantee order and is often discarded unless `TOP`, `OFFSET`, or an outer `ORDER BY` needs it. Adding `ORDER BY` to a view is not how you pre-sort rows for callers.
* A Sort of a few hundred rows is rarely the CPU problem worth an index. The input cardinality is the decision. Here the input is 320,000 rows for a 100-row answer.

## Version and permissions

`CREATE INDEX` needs `ALTER` on `dbo.Orders` (`db_owner`). The index is offline (no `ONLINE = ON`) so the script also runs on editions that cannot build online. Building it takes a schema-stability lock for the duration of the build. On this table that is a short operation; do not run `After.sql` against a production copy without a maintenance window.

No compatibility-level feature is required. SQL Server 2022's intelligent query processing does not invent a sorted index that does not exist.
