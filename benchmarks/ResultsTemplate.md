# Benchmark results

Copy this file to `benchmarks/local-results/` before filling it in. Numbers from one workstation are not a pass/fail target.

| | |
| --- | --- |
| Date | |
| SQL Server version (`SELECT @@VERSION`) | |
| Edition | |
| Compatibility level | |
| Max server memory (MB) | |
| `cost threshold for parallelism` | |
| `max degree of parallelism` | |
| Actual execution plan while timing | Off |
| Query Store while timing | Off |

Record the **measured** execution, not the warm-up and not parse/compile time. CPU and elapsed are milliseconds from `SET STATISTICS TIME`. Logical reads are from `SET STATISTICS IO` for the table named in the scenario notes (`Orders`, `Customers`, or `OrderItems`).

| Scenario | Side | Rows | Checksum | CPU ms | Elapsed ms | Logical reads | Plan notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 01 Non-sargable predicates | Before | 12000 | | | | | Scan, `YEAR` / `MONTH` residual |
| 01 Non-sargable predicates | After | 12000 | | | | | Seek on `IX_Orders_OrderDate` |
| 02 Implicit conversions | Before | 1 | | | | | `CONVERT_IMPLICIT` on `CustomerCode`, scan |
| 02 Implicit conversions | After | 1 | | | | | Seek on `UQ_Customers_CustomerCode` |
| 03 Unnecessary sorting | Before | 100 | | | | | Sort / Top N Sort, input ≫ 100 |
| 03 Unnecessary sorting | After | 100 | | | | | Ordered seek, no Sort |
| 04 Scalar functions | Before | 80000 | | | | | Serial, `fn_LineAmountWithTax` |
| 04 Scalar functions | After | 80000 | | | | | No UDF; note if the plan is parallel |
| 05 Excessive row processing | Before | 600 | | | | | Add both statements. Reads should cover all line items. |
| 05 Excessive row processing | After | 600 | | | | | Reads should cover about 2,400 lines |

Checksums for a scenario must match on the before and after rows. Logical reads for scenario 05 before are the `OrderItems` reads on the statement that writes `#OrderTotals`.

## Notes

* Physical reads on the measured run:
* Spills (sort or hash warnings):
* Scenario 04 `inline_type` (must be 0) and `is_inlineable`:
* Anything else that moved (other workload, autogrowth, a different plan):
