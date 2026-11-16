# AgriPulse Data Normalization

## 1. Overview

This script normalizes and validates the Delhi-centric NCR mandi dataset extracted from the `data.gov.in` source.

It reads the cleaned NCR dataset, standardizes text fields, district names, arrival dates, and prices, validates each record, removes duplicate records, and writes the final normalized dataset to a JSON file.

The script also generates a console report containing record counts, district-wise distribution, the available date range, and a sample normalized record.

## 2. Input and Output Files

### Input

```text
database/clean/ncr_mandi.json
```

The input file is expected to contain a JSON object with a `records` array.

### Output

```text
database/clean/normalized_mandi.json
```

The output file contains the normalized records and metadata about the normalization process.

Both paths are resolved relative to the directory in which the script is located.

## 3. Data Reading and Input Validation

The script reads the input JSON file using the Node.js `fs` module and parses it into a JavaScript object.

It then extracts the `records` property.

The script checks whether `records` is an array. If the property is missing or is not an array, processing stops with the following error:

```text
Invalid NCR dataset: records array not found
```

This prevents the normalization process from running on an incorrectly structured input file.

## 4. Text Field Normalization

A reusable text-normalization function is applied to textual fields.

The function performs the following operations:

1. Converts the value into a string.
2. Removes whitespace from the beginning and end.
3. Replaces multiple consecutive whitespace characters with a single space.
4. Converts empty strings into `null`.
5. Preserves `null` and `undefined` values as `null`.

This helps standardize values that may contain inconsistent spacing or empty fields.

The function is used for fields such as state, market, commodity, variety, and grade.

## 5. District Name Standardization

District names are standardized to avoid treating different spellings of the same district as separate locations.

The following aliases are handled:

| Input district name | Standardized district name |
|---|---|
| gurgaon | Gurugram |
| gurugram | Gurugram |
| delhi | Delhi |
| faridabad | Faridabad |
| ghaziabad | Ghaziabad |

The input is first passed through text normalization. The alias comparison is then performed in lowercase.

If a district does not match any alias, its normalized original value is retained.

This makes district-level grouping and analysis more consistent.

## 6. Arrival Date Normalization

The source arrival date is expected in the following format:

```text
DD/MM/YYYY
```

The script converts it into the ISO date format:

```text
YYYY-MM-DD
```

For example:

```text
13/11/2026
```

becomes:

```text
2026-11-13
```

The conversion process:

1. Checks that the arrival date is present.
2. Splits the date into day, month, and year.
3. Constructs a UTC date using those values.
4. Checks that the resulting calendar date matches the original day, month, and year.
5. Returns the date in ISO format.

The calendar validation prevents invalid dates, such as an impossible day or month, from being accepted.

Missing dates, incorrectly formatted dates, and invalid calendar dates cause an error.

## 7. Price Field Normalization

The script normalizes three price fields:

- `min_price`
- `max_price`
- `modal_price`

The normalization process:

1. Checks that the value is not `null`, `undefined`, or an empty string.
2. Converts the value into a string.
3. Removes comma separators.
4. Converts the cleaned value into a number.
5. Checks that the result is a finite number and is not negative.

For example, a price represented as:

```text
"2,500"
```

is converted into:

```text
2500
```

Missing, negative, or non-numeric prices are rejected.

## 8. Record Transformation and Validation

Every input record is transformed into a standardized record containing the following fields:

| Field | Description |
|---|---|
| `state` | State in which the mandi is located |
| `district` | Standardized district name |
| `market` | Mandi or market name |
| `commodity` | Agricultural commodity name |
| `variety` | Commodity variety |
| `grade` | Commodity grade |
| `arrival_date` | Arrival date in ISO format |
| `min_price` | Minimum recorded price |
| `max_price` | Maximum recorded price |
| `modal_price` | Modal or most commonly reported price |

### Required Field Validation

The following fields are mandatory:

- `state`
- `district`
- `market`
- `commodity`

If any of these fields is missing or empty after normalization, the record causes an error.

The `variety` and `grade` fields are allowed to remain `null`.

### Price Range Validation

The script checks two important conditions.

**Minimum price must not exceed maximum price:**

```text
min_price <= max_price
```

**Modal price must fall within the minimum and maximum price range:**

```text
min_price <= modal_price <= max_price
```

If either condition is violated, the script throws an error identifying the affected market.

These checks help prevent inconsistent price records from entering the normalized dataset.

## 9. Duplicate Record Removal

After normalization and validation, duplicate records are removed.

The script creates a unique key using the following fields:

- State
- District
- Market
- Commodity
- Variety
- Grade
- Arrival date

The values are joined into a single string and converted to lowercase.

A JavaScript `Set` is used to keep track of previously encountered keys.

The process works as follows:

1. Generate a unique key for each normalized record.
2. Check whether the key already exists in the `Set`.
3. If it exists, classify the record as a duplicate and skip it.
4. Otherwise, add the key to the `Set` and retain the record.
5. Increment the duplicate counter whenever a duplicate is skipped.

The first occurrence of a record is retained.

The duplicate count is stored in the final output metadata.

**Note:** The duplicate key does not include the price fields. Therefore, records with the same location, commodity, variety, grade, and arrival date are considered duplicates even if their prices differ. The first occurrence is retained.

## 10. Output Directory Creation

Before saving the normalized dataset, the script creates the output directory if it does not already exist.

This is done recursively so that missing parent directories can also be created.

It prevents the file-writing operation from failing merely because the destination directory is absent.

## 11. Normalized Dataset Structure

The final output is a JSON object containing metadata and the normalized records.

Its structure is:

```json
{
    "source": "data.gov.in",
    "region": "Delhi-centric NCR",
    "normalization_date": "ISO timestamp",
    "original_records": 0,
    "normalized_records": 0,
    "duplicates_removed": 0,
    "records": [
        {
            "state": "Example State",
            "district": "Example District",
            "market": "Example Market",
            "commodity": "Example Commodity",
            "variety": null,
            "grade": null,
            "arrival_date": "2026-11-13",
            "min_price": 1000,
            "max_price": 1200,
            "modal_price": 1100
        }
    ]
}
```

The values shown above are illustrative placeholders, not actual dataset results.

### Metadata Description

| Metadata field | Description |
|---|---|
| `source` | Original data source |
| `region` | Geographic scope of the dataset |
| `normalization_date` | Timestamp when the normalized dataset was generated |
| `original_records` | Number of records read from the input file |
| `normalized_records` | Number of unique records retained after normalization |
| `duplicates_removed` | Number of duplicate records skipped |
| `records` | Array containing the normalized records |

The normalized dataset is saved as formatted JSON using four-space indentation.

## 12. District-wise Record Breakdown

After duplicate removal, the script calculates the number of records available for each district.

It creates a district-count object in which:

- Each district name is used as a key.
- The corresponding value represents the number of normalized records belonging to that district.

This breakdown is printed in the terminal using a table.

It helps inspect the geographic distribution of the available mandi data.

## 13. Final Console Report

At the end of execution, the script prints a report titled:

```text
AGRIPULSE DATA NORMALIZATION
```

The report contains:

| Report item | Description |
|---|---|
| Original records | Total records read from the input dataset |
| Normalized records | Unique records retained after processing |
| Duplicates removed | Number of duplicate records skipped |
| District breakdown | Number of records available per district |
| Earliest date | Earliest arrival date in the normalized dataset |
| Latest date | Latest arrival date in the normalized dataset |
| Sample normalized record | First record in the normalized dataset |
| Saved to | Location of the generated JSON file |

The report ends with:

```text
NORMALIZATION COMPLETE
```

## 14. Overall Processing Pipeline

The complete normalization workflow follows this sequence:

1. Define the input and output file paths.
2. Read and parse the extracted NCR JSON dataset.
3. Verify that the records array exists.
4. Normalize textual fields.
5. Standardize district names.
6. Convert arrival dates into ISO format.
7. Convert price fields into valid numeric values.
8. Transform and validate every record.
9. Remove duplicate records.
10. Create the output directory if necessary.
11. Save the normalized dataset as JSON.
12. Calculate district-wise record counts.
13. Print the final normalization report.

## 15. Role in the AgriPulse Project

This normalization stage prepares the extracted mandi dataset for the next stages of the AgriPulse data pipeline.

It standardizes the structure and values of the source records so that they can be processed consistently by downstream ingestion and database operations.

The normalized dataset provides:

- Consistent district and market names.
- Standardized arrival dates.
- Numeric minimum, maximum, and modal prices.
- Validation of required fields and price ranges.
- Removal of duplicate records according to the defined uniqueness key.
- Metadata describing the normalization process.

The generated `normalized_mandi.json` file can then be used as the input for the subsequent database ingestion stage.
