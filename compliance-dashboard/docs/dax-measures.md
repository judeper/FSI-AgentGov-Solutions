# DAX Measures

Complete DAX measure definitions for the Compliance Dashboard.

> **Important — column naming for the Dataverse Power BI connector:**
> - **Choice (option set) columns** are imported as integer values (Dataverse stores `100000000+` for custom option sets unless you explicitly assign integer values when creating the option set). Comparing `[fsi_status] = 1` only works if you set the option values to `1, 2, 3, 4` when creating the choice. If you accept the Dataverse defaults, change every comparison below to the matching `100000000+` value, or join to a label/dimension table.
> - **Lookup columns** are imported as `_<schemaname>_value` (a GUID column) on the child side, **not** under the lookup's logical name. For example, the parent reference on `ControlAssessment` is `_fsi_controlmasterid_value`, not `fsi_controlmasterid`. The measures below use the `_value` form on the child side.
> - **Calculated columns** (`fsi_daysopen`, `fsi_slastatus`) are read-only when imported.

---

## Score Measures

### Overall Score

```dax
Overall Score =
VAR LatestDate = MAX(ComplianceScore[fsi_scoredate])
RETURN
    CALCULATE(
        AVERAGE(ComplianceScore[fsi_overallscore]),
        ComplianceScore[fsi_scoredate] = LatestDate
    )
```

### Overall Score Formatted

```dax
Overall Score Display =
FORMAT([Overall Score], "0.0") & "%"
```

### Pillar Scores

```dax
Pillar 1 Score =
VAR LatestDate = MAX(ComplianceScore[fsi_scoredate])
RETURN
    CALCULATE(
        AVERAGE(ComplianceScore[fsi_pillar1score]),
        ComplianceScore[fsi_scoredate] = LatestDate
    )

Pillar 2 Score =
VAR LatestDate = MAX(ComplianceScore[fsi_scoredate])
RETURN
    CALCULATE(
        AVERAGE(ComplianceScore[fsi_pillar2score]),
        ComplianceScore[fsi_scoredate] = LatestDate
    )

Pillar 3 Score =
VAR LatestDate = MAX(ComplianceScore[fsi_scoredate])
RETURN
    CALCULATE(
        AVERAGE(ComplianceScore[fsi_pillar3score]),
        ComplianceScore[fsi_scoredate] = LatestDate
    )

Pillar 4 Score =
VAR LatestDate = MAX(ComplianceScore[fsi_scoredate])
RETURN
    CALCULATE(
        AVERAGE(ComplianceScore[fsi_pillar4score]),
        ComplianceScore[fsi_scoredate] = LatestDate
    )
```

### Zone Scores

```dax
Zone 1 Score =
VAR LatestDate = MAX(ComplianceScore[fsi_scoredate])
RETURN
    CALCULATE(
        AVERAGE(ComplianceScore[fsi_zone1score]),
        ComplianceScore[fsi_scoredate] = LatestDate
    )

Zone 2 Score =
VAR LatestDate = MAX(ComplianceScore[fsi_scoredate])
RETURN
    CALCULATE(
        AVERAGE(ComplianceScore[fsi_zone2score]),
        ComplianceScore[fsi_scoredate] = LatestDate
    )

Zone 3 Score =
VAR LatestDate = MAX(ComplianceScore[fsi_scoredate])
RETURN
    CALCULATE(
        AVERAGE(ComplianceScore[fsi_zone3score]),
        ComplianceScore[fsi_scoredate] = LatestDate
    )
```

---

## Trend Measures

### Score Change (30 Day)

```dax
Score Change 30D =
VAR CurrentScore = [Overall Score]
VAR PriorScore =
    CALCULATE(
        AVERAGE(ComplianceScore[fsi_overallscore]),
        DATESINPERIOD(
            DateTable[Date],
            MAX(ComplianceScore[fsi_scoredate]) - 30,
            1,
            DAY
        )
    )
RETURN
    CurrentScore - PriorScore
```

### Score Change Direction

```dax
Score Trend Direction =
VAR Change = [Score Change 30D]
RETURN
    SWITCH(
        TRUE(),
        Change > 2, "Improving",
        Change < -2, "Declining",
        "Stable"
    )
```

### Score Trend Icon

```dax
Score Trend Icon =
VAR Change = [Score Change 30D]
RETURN
    SWITCH(
        TRUE(),
        Change > 2, "▲",
        Change < -2, "▼",
        "●"
    )
```

### Month-over-Month Change

```dax
MoM Change =
VAR CurrentMonth = EOMONTH(MAX(ComplianceScore[fsi_scoredate]), 0)
VAR PriorMonth = EOMONTH(MAX(ComplianceScore[fsi_scoredate]), -1)
VAR CurrentScore =
    CALCULATE(
        AVERAGE(ComplianceScore[fsi_overallscore]),
        MONTH(ComplianceScore[fsi_scoredate]) = MONTH(CurrentMonth),
        YEAR(ComplianceScore[fsi_scoredate]) = YEAR(CurrentMonth)
    )
VAR PriorScore =
    CALCULATE(
        AVERAGE(ComplianceScore[fsi_overallscore]),
        MONTH(ComplianceScore[fsi_scoredate]) = MONTH(PriorMonth),
        YEAR(ComplianceScore[fsi_scoredate]) = YEAR(PriorMonth)
    )
RETURN
    CurrentScore - PriorScore
```

---

## Control Status Measures

### Total Controls

```dax
Total Controls = COUNTROWS(ControlMaster)
```

### Compliant Count

```dax
Compliant Controls =
VAR LatestAssessments =
    FILTER(
        ADDCOLUMNS(
            ControlAssessment,
            "IsLatest", ControlAssessment[fsi_assessmentdate] =
                CALCULATE(MAX(ControlAssessment[fsi_assessmentdate]),
                    ALLEXCEPT(ControlAssessment, ControlAssessment[_fsi_controlmasterid_value]))
        ),
        [IsLatest] = TRUE()
    )
RETURN
COUNTROWS(FILTER(LatestAssessments, [fsi_status] = 1))
```

### Partial Count

```dax
Partial Controls =
VAR LatestAssessments =
    FILTER(
        ADDCOLUMNS(
            ControlAssessment,
            "IsLatest", ControlAssessment[fsi_assessmentdate] =
                CALCULATE(MAX(ControlAssessment[fsi_assessmentdate]),
                    ALLEXCEPT(ControlAssessment, ControlAssessment[_fsi_controlmasterid_value]))
        ),
        [IsLatest] = TRUE()
    )
RETURN
COUNTROWS(FILTER(LatestAssessments, [fsi_status] = 2))
```

### Non-Compliant Count

```dax
Non-Compliant Controls =
VAR LatestAssessments =
    FILTER(
        ADDCOLUMNS(
            ControlAssessment,
            "IsLatest", ControlAssessment[fsi_assessmentdate] =
                CALCULATE(MAX(ControlAssessment[fsi_assessmentdate]),
                    ALLEXCEPT(ControlAssessment, ControlAssessment[_fsi_controlmasterid_value]))
        ),
        [IsLatest] = TRUE()
    )
RETURN
COUNTROWS(FILTER(LatestAssessments, [fsi_status] = 3))
```

### Compliance Rate

```dax
Not Applicable Controls =
VAR LatestAssessments =
    FILTER(
        ADDCOLUMNS(
            ControlAssessment,
            "IsLatest", ControlAssessment[fsi_assessmentdate] =
                CALCULATE(MAX(ControlAssessment[fsi_assessmentdate]),
                    ALLEXCEPT(ControlAssessment, ControlAssessment[_fsi_controlmasterid_value]))
        ),
        [IsLatest] = TRUE()
    )
RETURN
COUNTROWS(FILTER(LatestAssessments, [fsi_status] = 4))

Compliance Rate =
DIVIDE(
    [Compliant Controls],
    [Total Controls] - [Not Applicable Controls],
    0
)
```

### Controls by Status (for matrix)

```dax
Control Status Count =
SWITCH(
    SELECTEDVALUE(StatusDimension[Status]),
    "Compliant", [Compliant Controls],
    "Partial", [Partial Controls],
    "Non-Compliant", [Non-Compliant Controls],
    "Not Applicable", [Not Applicable Controls],
    BLANK()
)
```

---

## Exception Measures

### Open Exceptions

```dax
Open Exceptions =
CALCULATE(
    COUNTROWS(ComplianceException),
    ComplianceException[fsi_exceptionstatus] IN {1, 2, 3}
)
```

### Critical Exceptions

```dax
Critical Exceptions =
CALCULATE(
    COUNTROWS(ComplianceException),
    ComplianceException[fsi_severity] = 1,
    ComplianceException[fsi_exceptionstatus] IN {1, 2, 3}
)
```

### SLA Breached Exceptions

```dax
SLA Breached =
CALCULATE(
    COUNTROWS(ComplianceException),
    ComplianceException[fsi_slastatus] = 3,
    ComplianceException[fsi_exceptionstatus] IN {1, 2, 3}
)
```

### SLA Compliance Rate

```dax
SLA Compliance % =
VAR OnTrack =
    CALCULATE(
        COUNTROWS(ComplianceException),
        ComplianceException[fsi_slastatus] = 1,
        ComplianceException[fsi_exceptionstatus] IN {1, 2, 3}
    )
VAR Total = [Open Exceptions]
RETURN
    DIVIDE(OnTrack, Total, 1)
```

### Average Days Open

```dax
Avg Days Open =
CALCULATE(
    AVERAGE(ComplianceException[fsi_daysopen]),
    ComplianceException[fsi_exceptionstatus] IN {1, 2, 3}
)
```

### Exceptions by Severity

```dax
Exception Severity Distribution =
SUMMARIZE(
    ComplianceException,
    ComplianceException[fsi_severity],
    "Count", COUNTROWS(ComplianceException)
)
```

---

## Evidence Measures

### Total Evidence Items

```dax
Total Evidence =
COUNTROWS(ComplianceEvidence)
```

### Evidence per Control

```dax
Avg Evidence per Control =
DIVIDE(
    [Total Evidence],
    DISTINCTCOUNT(ComplianceEvidence[_fsi_controlassessmentid_value]),
    0
)
```

### Recent Evidence (30 Days)

```dax
Recent Evidence =
CALCULATE(
    COUNTROWS(ComplianceEvidence),
    ComplianceEvidence[fsi_collecteddate] >= TODAY() - 30
)
```

---

## Conditional Formatting Measures

### Score Color

```dax
Score Color =
VAR Score = [Overall Score]
RETURN
    SWITCH(
        TRUE(),
        Score >= 90, "#28A745",  -- Green
        Score >= 70, "#FFC107",  -- Yellow
        Score >= 50, "#FD7E14",  -- Orange
        "#DC3545"               -- Red
    )
```

### Status Color

```dax
Status Color =
SWITCH(
    SELECTEDVALUE(ControlAssessment[fsi_status]),
    1, "#28A745",  -- Compliant - Green
    2, "#FFC107",  -- Partial - Yellow
    3, "#DC3545",  -- Non-Compliant - Red
    4, "#6C757D",  -- Not Applicable - Gray
    "#000000"
)
```

### SLA Status Color

```dax
SLA Color =
SWITCH(
    SELECTEDVALUE(ComplianceException[fsi_slastatus]),
    1, "#28A745",  -- On Track - Green
    2, "#FFC107",  -- At Risk - Yellow
    3, "#DC3545",  -- Breached - Red
    "#6C757D"
)
```

---

## Time Intelligence Measures

### Score Same Period Last Month

```dax
Score SPLM =
CALCULATE(
    [Overall Score],
    DATEADD(DateTable[Date], -1, MONTH)
)
```

### Score Same Period Last Quarter

```dax
Score SPLQ =
CALCULATE(
    [Overall Score],
    DATEADD(DateTable[Date], -1, QUARTER)
)
```

### Rolling 7-Day Average

```dax
Score 7D Avg =
AVERAGEX(
    DATESINPERIOD(
        DateTable[Date],
        MAX(DateTable[Date]),
        -7,
        DAY
    ),
    [Overall Score]
)
```

### Year-to-Date Average

```dax
Score YTD =
CALCULATE(
    AVERAGE(ComplianceScore[fsi_overallscore]),
    DATESYTD(DateTable[Date])
)
```

---

## Calculated Tables

### Status Dimension

```dax
StatusDimension =
DATATABLE(
    "StatusID", INTEGER,
    "Status", STRING,
    "SortOrder", INTEGER,
    {
        {1, "Compliant", 1},
        {2, "Partial", 2},
        {3, "Non-Compliant", 3},
        {4, "Not Applicable", 4}
    }
)
```

### Severity Dimension

```dax
SeverityDimension =
DATATABLE(
    "SeverityID", INTEGER,
    "Severity", STRING,
    "SLADays", INTEGER,
    {
        {1, "Critical", 7},
        {2, "High", 14},
        {3, "Medium", 30},
        {4, "Low", 90}
    }
)
```

### Pillar Dimension

```dax
PillarDimension =
DATATABLE(
    "PillarID", INTEGER,
    "PillarName", STRING,
    "ControlCount", INTEGER,
    {
        {1, "Security", 24},
        {2, "Management", 21},
        {3, "Reporting", 10},
        {4, "SharePoint", 7}
    }
)
```

---

## Usage Notes

1. **Performance**: Use measures instead of calculated columns for aggregations
2. **Filtering**: Most measures respect filter context from slicers
3. **Time Intelligence**: Requires properly configured Date table relationship
4. **Conditional Formatting**: Apply color measures in visual formatting pane

---

*Compliance Dashboard v1.0.4*
