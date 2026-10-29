# Scenario 04 — Scalar functions

## Mistake

`dbo.fn_LineAmountWithTax` is a scalar UDF. `Before.sql` calls it once per line for orders 1 through 20,000 (80,000 calls). The `OrderId` predicate is sargable and covered by `IX_OrderItems_OrderId`, so this scenario is not an indexing problem. Logical reads should stay in the same range before and after. CPU and elapsed time should not.

## Why CPU goes up

A scalar UDF that is **not inlined** runs as a separate routine call per row:

* The plan stays serial. On the `QueryPlan` element, `NonParallelPlanReason` is set. A SQL Server 2019 plan for this function reported `CouldNotGenerateValidParallelPlan`. Other builds report `TSQLUserDefinedFunctionsNotParallelizable`. Treat either value, together with the function name in the plan, as the signature. Do not fail the demo because the string differs.
* Each call has its own execution context. That overhead dominates the few arithmetic operations inside the function.
* `sys.dm_exec_function_stats` (needs `VIEW SERVER STATE`) shows `execution_count` in the tens of thousands for one query, and worker time charged to the function.

Both scripts seek `IX_OrderItems_OrderId` for the same 80,000 lines. Compare logical reads on `OrderItems` (they should stay in the same range), then CPU time, then elapsed time. A large CPU gap with similar logical reads is the result this scenario is built to show. Parallelism is not required for that gap at this row count. A larger `OrderId` range can let the expression go parallel; the UDF plan should stay serial.

`Before.sql` and `After.sql` send 80,000 rows to the grid, so their elapsed time includes SSMS. The parity query at the bottom of `After.sql` calls the UDF on purpose and is not a timing run. `benchmarks/RunBefore.sql` and `RunAfter.sql` sum the gross amount on the server. The two sums must match. One SQL Server 2019 Developer Edition run of this seed showed a large CPU gap and a serial expression plan. That ratio is one observation, not a target for other hardware.

## Inlining, and why this function does not get it

SQL Server 2019 introduced scalar UDF inlining at compatibility level 150. SQL Server 2022 keeps it. A simple arithmetic function written with `DECLARE` and `RETURN` is often inlined until the call disappears from the plan. If that happens, `Before.sql` and `After.sql` converge and the demo teaches the wrong lesson.

`01_CreateTables.sql` creates the function `WITH INLINE = OFF`. That is the supported way to keep one function out of the inliner without changing the database.

| Column | Value in this database | Meaning |
| --- | --- | --- |
| `sys.sql_modules.inline_type` | 0 | `INLINE = OFF`. This is the check. `04_VerifyData.sql` and `Before.sql` both require it. |
| `sys.sql_modules.is_inlineable` | often 1 | The body meets the inlining rules. It does **not** mean this call will be inlined. |

`EXECUTE AS OWNER` also blocks inlining, and it is the wrong tool for this demo. Impersonation performs a security-context switch per row (`PREEMPTIVE_OS_AUTHORIZATIONOPS`). That cost hides the call overhead the scenario is about. Do not add it to make the number more dramatic.

Inlining is also skipped when any of these are true, even without `INLINE = OFF`:

* Compatibility level is below 150.
* The database scoped configuration `TSQL_SCALAR_UDF_INLINING` is `OFF`.
* The function is CLR, encrypted, uses `EXECUTE AS` other than `CALLER`, references table variables or table-valued parameters, or calls intrinsics that are non-deterministic or have side effects (`GETDATE`, `NEWID`, and others).
* The call site is in a place inlining does not support (for example some `ORDER BY` and `GROUP BY` patterns).

Those exclusions are why "SQL Server 2019 fixed scalar UDFs" is not a strategy.

### Experiment, not the fix

You can recreate the function **without** `INLINE = OFF` and run `Before.sql` again. At compatibility level 150 or 160 the body may inline and the CPU gap may collapse. `Before.sql` will throw until `inline_type` is 0 again, which is what you want: the script refuses a comparison that no longer measures a scalar call. Put `WITH INLINE = OFF` back when you are done.

Dropping the option is not the production fix. The next exclusion, or a scoped configuration change, brings the calls back. An expression or an inline TVF does not depend on the inliner.

Do not turn `TSQL_SCALAR_UDF_INLINING` off at the database to make this demo "more obvious." That changes every other query in the database.

## The fix

`After.sql` writes the same math in the query:

```sql
CAST(c.Net + CAST(ROUND(c.Net * 0.0800, 2) AS decimal(19, 4)) AS decimal(19, 4))
```

with `c.Net` defined once as `CAST(Quantity * UnitPrice AS decimal(19, 4))`.

The function does **not** compute `ROUND(net * 1.08, 2)`. It rounds 8 percent of the net to the cent, then adds that tax to the original net. Those are different values on some amounts. The parity query at the bottom of `After.sql` must report `MismatchedRows = 0`. That query calls the UDF, so it is slow on purpose and is not a benchmark.

`CROSS APPLY` here is a naming device. The plan should show a Compute Scalar (and, when the cost is high enough, parallelism). It should not show a user-defined function operator.

### When the expression has to be reused

`dbo.InlineLineAmountWithTax` in `After.sql` is an **inline** table-valued function: a single `RETURN SELECT`, no `BEGIN`. `CROSS APPLY dbo.InlineLineAmountWithTax(...)` is expanded into the caller. That is the reuse mechanism that stays set-based.

A multi-statement table-valued function (`BEGIN`, `INSERT` into a `@table`, `RETURN`) is a different CPU and cardinality problem. It is not used here. It also is not fixed by the scalar inliner.

## What the plan should show

| Run | Parallelism | Function |
| --- | --- | --- |
| Before | Serial. `NonParallelPlanReason` is populated. Index Seek on `IX_OrderItems_OrderId`. | Reference to `fn_LineAmountWithTax`. |
| After | Serial at 80,000 lines is normal, because the expression is cheap. A wider range may go parallel if cost threshold and `MAXDOP` allow it. | No UDF. Compute Scalar for the arithmetic. Same seek. |

Compare before CPU with after CPU, and before elapsed with after elapsed. If the after plan does go parallel, CPU time is summed across threads and may exceed elapsed time. Do not force `MAXDOP 1` on the after query to "make it fair" unless you are deliberately isolating call overhead from parallelism. The real fix is allowed to use more than one core.

The literal `20000` keeps the estimate honest. Replacing it with a local variable is a cardinality lesson (scenario-adjacent, not this one) and can make both sides scan all 1,600,000 lines.

## Version and permissions

| Item | Requirement |
| --- | --- |
| `is_inlineable` and `inline_type` | SQL Server 2019 or later |
| Scalar UDF inlining feature | Compatibility level 150 or higher, and the function must qualify |
| This function's forced call | `WITH INLINE = OFF` (`inline_type = 0`), valid on 2019 and 2022 |
| `sys.dm_exec_function_stats` | `VIEW SERVER STATE` or, on SQL Server 2022+, `VIEW SERVER PERFORMANCE STATE` |
