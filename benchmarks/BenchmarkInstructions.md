# Benchmark instructions

Use this when you want numbers you can compare. Use the scenario scripts when you want the plan on screen. The two runs answer different questions, and mixing them produces a false regression.

## What is being compared

`RunBefore.sql` and `RunAfter.sql` execute the same five statements as the scenario files. Each statement is aggregated on the server:

```sql
SELECT @Rows = COUNT_BIG(*), @Check = SUM(...)
FROM ( /* the scenario query */ ) AS q;
```

SSMS does not render 12,000 or 80,000 rows during the timing run, so `ASYNC_NETWORK_IO` and the results grid are not part of the elapsed time. The predicates, the function call, the `TOP (100)` / `ORDER BY`, and the early-versus-late filter are unchanged.

`@Rows` and `@Check` are printed so you can confirm the before and after answers match:

| Scenario | Rows | Check |
| --- | --- | --- |
| 01 June 2024 orders | 12,000 | Sum of `TotalAmount`. Before and after must match. |
| 02 Customer `C00010000` | 1 | CustomerId 10000. |
| 03 Top 100 shipped by amount | 100 | Sum of those 100 `TotalAmount` values. Must match. |
| 04 Lines for orders 1–20000 | 80,000 | Sum of gross amounts. Must match. |
| 05 Open orders in June 2025 | 600 | Sum of `CalculatedTotal`. Must match. |

If a checksum differs, do not record the timing. The rewrite is not equivalent on your build, and that is the bug to look at.

## Conditions

1. Run `database/00` through `database/04` once, and do not continue if verification throws. `00_CreateDatabase.sql` drops `SqlServerCpuOptimization` only as the first step of creating it again, and leaves that database in place. `RunBefore.sql` and `RunAfter.sql` use that database. They fail if it is missing. They do not connect to `master` and they do not expect the name to stay dropped.
2. Use a quiet SQL Server instance. Developer Edition is appropriate. Express Edition caps memory and CPU and will change elapsed time, especially if a sort or hash spills.
3. In SSMS, turn **Include Actual Execution Plan** off. Turn **Include Live Query Statistics** off.
4. Leave Query Store off for both runs (the setup script does this). `diagnostics/05_QueryStore.sql` turns it on and adds capture CPU. Enable it only after the template is filled, or enable it before the before run and leave it on for both.
5. Do not run `DBCC DROPCLEANBUFFERS` or `DBCC FREEPROCCACHE` on a shared instance. The scripts warm the cache themselves.
6. Run `benchmarks/RunBefore.sql` once. It drops `IX_Orders_Status_TotalAmount_OrderId` if scenario 03 created it, then warms and measures each before statement.
7. Run `benchmarks/RunAfter.sql` once. Scenario 03 creates the supporting index before its warm-up, so the measured execution is not the index build and is not the first compile.

Each scenario prints `warm-up` and then `measured`. Record only the measured `SQL Server Execution Times` block and the logical reads of the base tables (`Orders`, `OrderItems`, `Customers`). Ignore parse and compile time. Ignore worktable and `#OrderTotals` reads when you are describing the fix, but you may note them: they are part of why the before query is expensive.

## How to read the three numbers

| Metric | What it tells you |
| --- | --- |
| CPU time | Worker time for the execution. This is the CPU comparison. Parallel plans can report CPU time higher than elapsed time. |
| Elapsed time | Wall time on the server for that execution, including waits. Useful after the warm-up, when physical reads have gone to zero. |
| Logical reads | Pages touched in the buffer pool. Stable across a warm and a cold cache. A scan that "only takes 20 ms" and reads the whole index is still the wrong plan. |

Physical reads on the measured block mean the warm-up did not cache the pages. Run that script again and record the new measured block.

Scenario 02 may show a small CPU delta and a large logical-read delta. That is a successful result. The scan is the defect; one execution against 80,000 codes is cheap until the statement runs constantly.

Scenario 04 should show similar logical reads and much higher before CPU. If the two CPU numbers are close, check `sys.sql_modules.inline_type` for `dbo.fn_LineAmountWithTax`. It must be 0 (`INLINE = OFF`). `is_inlineable` may be 1. See `scenarios/04_ScalarFunctions/Explanation.md`.

Scenario 05 before prints two execution blocks (materialize, then filter). Add them. The after script prints one.

## Plans

After the template is filled, turn Include Actual Execution Plan on and run the individual `Before.sql` / `After.sql` files. Do not paste those timings next to the benchmark timings. Capture the operators listed in `diagnostics/02_ExecutionPlanInspection.sql` into the Notes column.

## Isolation

* `RunBefore.sql` always drops the scenario 03 index before measuring, so the sort is actually in the plan.
* Scenario 05 does not need that index. `RunAfter.sql` creates it for scenario 03 and leaves it in place. Scenario 05 after may seek it. The before script still processed every line either way. To time scenario 05 after with only the base indexes, run `scenarios/05_ExcessiveRowProcessing/After.sql` before `scenarios/03_UnnecessarySorting/After.sql`.
* The scalar function stays in the database. The after query simply does not call it.

## Where to write the numbers

Copy `benchmarks/ResultsTemplate.md` to `benchmarks/local-results/` (that folder is gitignored) and fill it in. Keeping a filled template out of git avoids publishing one workstation's timings as if they were a target.
