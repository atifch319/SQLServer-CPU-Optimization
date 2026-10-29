# Scenario 02 — Implicit conversions

## Mistake

`CustomerCode` is `varchar(16)`. The predicate supplies `nvarchar`. SQL Server has to compare one type. It converts the lower-precedence operand.

Relevant order, highest first:

`datetime2` > `datetime` > `decimal` > `bigint` > `int` > `nvarchar` > `varchar`

`nvarchar` is higher than `varchar`, so the **column** is converted:

```text
CONVERT_IMPLICIT(nvarchar(16), CustomerCode, 0) = @CustomerCode
```

An index on `CustomerCode` cannot satisfy a predicate on `CONVERT(nvarchar, CustomerCode)`. The seek becomes a scan of all 80,000 customers to return one row. Every scanned value is converted. That is the CPU cost. Logical reads of the whole unique index are the IO cost.

One execution against 80,000 rows is often only a few milliseconds of CPU. The plan is still wrong. The same statement issued hundreds of times a second, or against a multi-million-row code column, is a steady CPU consumer. Judge this scenario by the operator and the logical reads first, then by CPU time.

## Why the other direction usually survives

If the column is `nvarchar` and the parameter is `varchar`, precedence converts the **parameter**. A single conversion of the parameter still allows a seek. The dangerous direction is "column type is lower precedence than the value."

The same rule is why `WHERE OrderId = '12345'` is usually fine: `bigint` outranks `varchar`, the literal is converted once, and the seek remains. `WHERE OrderNumber = N'ORD00000001'` is the dangerous form, because `OrderNumber` is `varchar`.

A `varchar(16)` column compared with a `varchar(50)` parameter is a different and much milder case. The parameter is generally converted to the column type and the seek remains. Do not confuse length mismatch with the `nvarchar`/`varchar` mismatch.

A collation conflict between both sides can also wrap the column and block a seek. This database uses the instance collation on every string column, so collation is not the cause here.

## What the plan should show

In the actual or estimated plan, open the scan and the warning:

* **Type conversion in expression** may affect cardinality and seek choice.
* `CONVERT_IMPLICIT` on `CustomerCode`, not on the variable.
* Physical operation: Index Scan. After the fix: Index Seek on `UQ_Customers_CustomerCode`.

`diagnostics/02_ExecutionPlanInspection.sql` searches the plan cache for `Convert[@Implicit="1"]`.

`OPTION (RECOMPILE)` embeds the variable's value and can improve the estimate. It does not change the type. The scan stays. An index hint cannot seek an expression either.

## The fix

Pick one side and make every caller match it.

| Situation | Change |
| --- | --- |
| You control the SQL and the column is intentionally non-Unicode | Declare the parameter as `varchar(16)`, or pass `SqlDbType.VarChar` with an explicit size from .NET. |
| Every client sends .NET strings and will keep sending `nvarchar` | Store the column as `nvarchar`. A one-sided code change in a single stored procedure will be undone by the next ad hoc query. |

`After.sql` uses the first fix and leaves the table as `varchar`, so `Before.sql` still demonstrates the scan.

From ADO.NET the matching parameter is:

```csharp
command.Parameters.Add("@CustomerCode", SqlDbType.VarChar, 16).Value = "C00010000";
```

`AddWithValue` infers `nvarchar` from a .NET `string`. That is enough to recreate `Before.sql` from an application that otherwise looks correct.

## Compare CPU time, elapsed time, and logical reads

Use Messages, not the one-row grid. Record `SQL Server Execution Times` and logical reads for `Customers`. Ignore compile time.

Logical reads should fall from a walk of `UQ_Customers_CustomerCode` to a handful of pages (the seek). CPU time for one execution is often only a few milliseconds either way. A small CPU delta with a large logical-read delta is a successful result, not a failed one. Elapsed time here is too small, and too easily mixed with compile time, to be the decision. The benchmark scripts run the same predicate without painting a grid; with one row the grid was never the cost.

This fix does not help if the column is already `nvarchar` and only the parameter is `varchar`: that conversion is on the parameter and the seek can remain. It also does not help if you only add `OPTION (RECOMPILE)` and leave the parameter as `nvarchar`.

## What a single logical read proves

After the fix, logical reads on `Customers` should be a handful (the seek depth of `UQ_Customers_CustomerCode`), not a walk of the leaf level. If the after plan seeks and the before plan scans, the demonstration worked even when the CPU milliseconds look small.

## Version and permissions

Implicit conversion follows data type precedence on every supported version. Query Store and compatibility level do not turn a converted column back into a seek. Seeing the plan warning in SSMS requires `SHOWPLAN`.
