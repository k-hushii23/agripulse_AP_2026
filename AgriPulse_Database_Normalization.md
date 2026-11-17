# Database Normalization — AgriPulse

This document traces the normalization of the **AgriPulse** database from a conceptual flat
agricultural price register through to Boyce–Codd Normal Form (BCNF). The database design
described here is based on the actual SQL definition in `database/schema_prices.sql` in the
supplied AgriPulse project ZIP. The data-cleaning and backend observations are based on the
project files included in that ZIP.

AgriPulse is a farmer-focused agricultural commodity intelligence and price outlook platform.
Its database separates commodity information, market information, spot-price observations,
futures-price observations, and price alerts.

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [System Requirements and Entities](#2-system-requirements-and-entities)
3. [Unnormalized Form (UNF)](#3-unnormalized-form-unf)
4. [First Normal Form (1NF)](#4-first-normal-form-1nf)
5. [Second Normal Form (2NF)](#5-second-normal-form-2nf)
6. [Third Normal Form (3NF)](#6-third-normal-form-3nf)
7. [Boyce–Codd Normal Form (BCNF)](#7-boycecodd-normal-form-bcnf)
8. [Deliberate Denormalization](#8-deliberate-denormalization)
9. [Database Constraints and Integrity Rules](#9-database-constraints-and-integrity-rules)
10. [Design Issues and Honest Notes](#10-design-issues-and-honest-notes)
11. [Conclusion](#11-conclusion)

---

## 1. Introduction

AgriPulse is a farmer-focused agricultural commodity intelligence and price outlook platform.
It is designed to help users examine agricultural commodity prices across markets, compare
reported mandi prices, view futures-market information, and create price-threshold alerts.

The project uses **PostgreSQL** for its relational database and a **Node.js / Express** backend.
The SQL schema defines five tables: `commodities`, `markets`, `spot_prices`, `futures_prices`,
and `alerts`.

The project also contains data-processing jobs that extract Delhi-centric NCR mandi records
from a raw dataset, standardize text and district names, convert dates, validate price values,
and remove duplicate records before saving a normalized JSON dataset.

The goal of database normalization is to reduce unnecessary data duplication and prevent
insertion, update, and deletion anomalies while preserving all information required by the
application. This document explains the database design through UNF, 1NF, 2NF, 3NF, and BCNF.

**Source scope:** Table definitions, data types, keys, foreign keys, defaults, and SQL constraints
below are taken from `database/schema_prices.sql`. Data-processing behavior is taken from the
backend jobs in the ZIP. No additional tables or constraints have been invented.

---

## 2. System Requirements and Entities

The following are the core entities defined in the supplied SQL schema.

| Entity | Purpose |
|---|---|
| **Commodity** | Stores an agricultural commodity, including its name, variety, grade, and unit. |
| **Market** | Stores an agricultural market or mandi, including its name, district, and state. |
| **SpotPrice** | Stores a dated spot-price observation for a commodity at a particular market. |
| **FuturesPrice** | Stores a dated futures-price observation for a commodity and contract month. |
| **Alert** | Stores a user-defined price threshold for a commodity and market, including its direction and status. |

**Database technology and application context:**

| Item | Details |
|---|---|
| Database | PostgreSQL |
| Schema definition | `database/schema_prices.sql` |
| Backend | Node.js and Express |
| Spot-price data source referenced by the project | Agmarknet / data.gov.in |
| Futures-price source referenced by the project | NCDEX |
| Geographic extraction in the data pipeline | Delhi-centric NCR |
| NCR districts explicitly listed by the extraction job | Delhi, Faridabad, Gurugram, Ghaziabad |

**Tables and columns defined in the SQL schema:**

| Table | Columns |
|---|---|
| `commodities` | `id`, `name`, `variety`, `grade`, `unit` |
| `markets` | `id`, `name`, `district`, `state` |
| `spot_prices` | `id`, `commodity_id`, `market_id`, `price_date`, `min_price`, `max_price`, `modal_price`, `arrival_qty` |
| `futures_prices` | `id`, `commodity_id`, `contract_month`, `expiry_date`, `price_date`, `settlement_price` |
| `alerts` | `id`, `commodity_id`, `market_id`, `target_price`, `unit`, `direction`, `status`, `created_at` |

**Important SQL characteristics:**

- Every table has a `SERIAL` primary-key column named `id`.
- `spot_prices` references both `commodities` and `markets`.
- `futures_prices` references `commodities`.
- `alerts` references both `commodities` and `markets`.
- The schema uses composite UNIQUE constraints to prevent duplicate commodity, market, spot-price,
  and futures-price combinations.
- `alerts.direction` is restricted to `above` or `below` through a SQL `CHECK` constraint.

There are no PostgreSQL enum types in the supplied schema.

---

## 3. Unnormalized Form (UNF): The Flat Register

Before normalization, imagine that all agricultural price and alert information was stored in
one flat register. A row would combine commodity details, market details, spot-price details,
futures-price details, and alert details.

A conceptual flat row could contain the following attributes:

| commodity_name | variety | grade | unit | market_name | district | state | spot_price_date | min_price | max_price | modal_price | arrival_qty | contract_month | expiry_date | futures_price_date | settlement_price | alert_target_price | alert_direction | alert_status |
|---|---|---|---|---|---|---|---|---:|---:|---:|---:|---|---|---|---:|---:|---|---|
| Tomato | Tomato | FAQ | Quintal | Sohna APMC | Gurugram | Haryana | 2026-11-12 | 2000 | 2500 | 2200 | — | 2026-12-01 | 2026-12-20 | 2026-11-12 | — | 2400 | above | active |

**Illustrative example:** The row above demonstrates the shape of a possible flat register. It is
not represented as an actual combined row from the database. The SQL schema stores spot prices,
futures prices, and alerts in separate relations, and the sample source files do not establish
that all these values belong to one record.

**Problems in this flat form:**

- Commodity details (`commodity_name`, `variety`, `grade`, `unit`) would be repeated for every
  price observation and alert referring to that commodity.
- Market details (`market_name`, `district`, `state`) would be repeated for every spot-price and
  alert record referring to the same market.
- Updating a market name or district could require changes in many rows.
- A commodity could not be conveniently recorded independently of a price observation if all
  information had to be entered in one combined register.
- A market with no current price observation could be difficult to represent in the flat register.
- Spot prices and futures prices have different identifying attributes and are different kinds
  of market information. Combining them would create unrelated nullable columns.
- Alert information is a user-defined threshold, not a price observation. Repeating alert
  information alongside price records could cause duplication and update anomalies.
- Deleting the last price record for a commodity or market could accidentally remove the only
  copy of its descriptive information.

These are the insertion, update, and deletion anomalies that normalization is intended to avoid.

---

## 4. First Normal Form (1NF)

**Rule:** Every cell must contain exactly one atomic value; there must be no repeating groups or
multi-valued attributes in a single cell.

**Changes made:**

1. Commodity details are stored in the `commodities` table, one commodity record per row.
2. Market details are stored in the `markets` table, one market record per row.
3. Each daily spot-price observation is stored as a separate row in `spot_prices`.
4. Each futures-price observation is stored as a separate row in `futures_prices`.
5. Each price alert is stored as a separate row in `alerts`.
6. Each field in the SQL schema is a single scalar column, such as `VARCHAR`, `DATE`, `NUMERIC`,
   `INTEGER`, or `TIMESTAMP WITH TIME ZONE`.

**Resulting relations (1NF):**

```text
commodities(
    id, name, variety, grade, unit
)

markets(
    id, name, district, state
)

spot_prices(
    id, commodity_id, market_id, price_date,
    min_price, max_price, modal_price, arrival_qty
)

futures_prices(
    id, commodity_id, contract_month, expiry_date,
    price_date, settlement_price
)

alerts(
    id, commodity_id, market_id, target_price,
    unit, direction, status, created_at
)
```

All five relations use atomic scalar columns. Some descriptive fields are nullable in the SQL
schema, including `variety`, `grade`, `unit`, `district`, `state`, `contract_month`, and
`expiry_date`. A nullable scalar field is still atomic; nullability alone does not violate 1NF.

The data-cleaning job `normalizeNCR.js` also standardizes incoming JSON values before producing
`normalized_mandi.json`. It trims text, collapses repeated whitespace, standardizes selected
district aliases, converts arrival dates to `YYYY-MM-DD`, validates numeric price fields, and
removes duplicate records. This is data-value cleaning; the relational 1NF structure is defined
by the SQL tables above.

---

## 5. Second Normal Form (2NF)

**Rule:** A relation must be in 1NF, and every non-key attribute must depend on the whole
candidate key. There must be no partial dependency on only part of a composite candidate key.

Each table in the supplied schema has a single-column surrogate primary key (`id`). Therefore,
there can be no partial dependency on a proper subset of the declared primary key: a
single-column key has no smaller non-empty subset.

The schema also defines the following composite UNIQUE constraints, which provide additional
candidate-key combinations when considered under the declared uniqueness semantics:

| Table | Composite UNIQUE constraint |
|---|---|
| `commodities` | `(name, variety, grade)` using `UNIQUE NULLS NOT DISTINCT` |
| `markets` | `(name, district, state)` using `UNIQUE NULLS NOT DISTINCT` |
| `spot_prices` | `(commodity_id, market_id, price_date)` |
| `futures_prices` | `(commodity_id, contract_month, price_date)` using `UNIQUE NULLS NOT DISTINCT` |

The intended identifying combination for a spot-price record is the commodity, market, and
price date together. The intended identifying combination for a futures-price record is the
commodity, contract month, and price date together.

The supplied project does not specify further business dependencies such as
`commodity_name → unit` or `market_name → district`. Therefore, this document does not assume
those dependencies.

> **Note:** With respect to the declared single-column primary keys, all five tables satisfy
> the 2NF requirement because partial dependencies cannot occur. A formal proof against every
> possible natural key would require a complete set of business functional dependencies beyond
> what is explicitly stated in the project files.

---

## 6. Third Normal Form (3NF)

**Rule:** A relation must be in 2NF, and no non-key attribute should depend transitively on a
candidate key through another non-key attribute.

### 6.1 Transitive Dependencies in the Conceptual Flat Register

In the conceptual flat register, commodity and market descriptions would be stored repeatedly
alongside price and alert facts. The intended relationships can be represented as follows:

| Functional Dependency | Type | Problem in the flat register |
|---|---|---|
| `commodity_id → name, variety, grade, unit` | Commodity-level | Commodity details would repeat for each observation. |
| `market_id → name, district, state` | Market-level | Market details would repeat for each spot-price or alert row. |
| `spot_price_id → commodity_id, market_id, price_date, min_price, max_price, modal_price, arrival_qty` | Spot observation | Spot-price facts belong to an individual observation. |
| `futures_price_id → commodity_id, contract_month, expiry_date, price_date, settlement_price` | Futures observation | Futures facts belong to an individual contract/date observation. |
| `alert_id → commodity_id, market_id, target_price, unit, direction, status, created_at` | Alert-level | Alert facts belong to an individual alert. |

These dependencies describe the intended entity separation represented by the SQL schema. They
do not assert additional dependencies that are absent from the schema.

### 6.2 Decomposition into 3NF Tables

The flat register is decomposed into five relations. Each relation stores facts belonging to one
entity or event type, and relationships between those facts are represented by foreign keys.

#### `commodities`

```sql
commodities (
    id      SERIAL PRIMARY KEY,
    name    VARCHAR(255) NOT NULL,
    variety VARCHAR(255),
    grade   VARCHAR(100),
    unit    VARCHAR(50),
    UNIQUE NULLS NOT DISTINCT (name, variety, grade)
)
```

Functional dependency:

```text
id → name, variety, grade, unit
(name, variety, grade) → commodity row
```

The composite uniqueness rule prevents duplicate commodity definitions for the same name,
variety, and grade, including rows where nullable components are null because the schema uses
`NULLS NOT DISTINCT`.

#### `markets`

```sql
markets (
    id       SERIAL PRIMARY KEY,
    name     VARCHAR(255) NOT NULL,
    district VARCHAR(255),
    state    VARCHAR(255),
    UNIQUE NULLS NOT DISTINCT (name, district, state)
)
```

Functional dependency:

```text
id → name, district, state
(name, district, state) → market row
```

Market details are stored once and referenced by `market_id` from the relevant transactional
tables.

#### `spot_prices`

```sql
spot_prices (
    id          SERIAL PRIMARY KEY,
    commodity_id INTEGER NOT NULL REFERENCES commodities(id),
    market_id    INTEGER NOT NULL REFERENCES markets(id),
    price_date   DATE NOT NULL,
    min_price    NUMERIC(12, 2),
    max_price    NUMERIC(12, 2),
    modal_price  NUMERIC(12, 2),
    arrival_qty  NUMERIC(12, 2),
    UNIQUE (commodity_id, market_id, price_date)
)
```

Functional dependency:

```text
id → commodity_id, market_id, price_date,
     min_price, max_price, modal_price, arrival_qty

(commodity_id, market_id, price_date) → spot-price row
```

Each row records a spot-price observation for one commodity at one market on one date. Commodity
and market descriptions are not copied into this table; their IDs reference the parent tables.

#### `futures_prices`

```sql
futures_prices (
    id               SERIAL PRIMARY KEY,
    commodity_id     INTEGER NOT NULL REFERENCES commodities(id),
    contract_month   DATE,
    expiry_date      DATE,
    price_date       DATE NOT NULL,
    settlement_price NUMERIC(12, 2),
    UNIQUE NULLS NOT DISTINCT (commodity_id, contract_month, price_date)
)
```

Functional dependency:

```text
id → commodity_id, contract_month, expiry_date,
     price_date, settlement_price

(commodity_id, contract_month, price_date) → futures-price row
```

Each row records a futures-price observation for a commodity and contract/date combination.
The commodity details are obtained through `commodity_id`.

#### `alerts`

```sql
alerts (
    id           SERIAL PRIMARY KEY,
    commodity_id INTEGER NOT NULL REFERENCES commodities(id) ON DELETE CASCADE,
    market_id    INTEGER NOT NULL REFERENCES markets(id) ON DELETE CASCADE,
    target_price NUMERIC(12, 2) NOT NULL,
    unit         VARCHAR(50) DEFAULT 'Quintal',
    direction    VARCHAR(10) NOT NULL CHECK (direction IN ('above', 'below')),
    status       VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at   TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
)
```

Functional dependency:

```text
id → commodity_id, market_id, target_price,
     unit, direction, status, created_at
```

Each alert is stored independently and references the commodity and market to which it applies.

### 6.3 Result of 3NF Decomposition

After decomposition:

- Commodity descriptions are stored in `commodities`.
- Market descriptions are stored in `markets`.
- Spot-price observations are stored in `spot_prices`.
- Futures-price observations are stored in `futures_prices`.
- Alert definitions are stored in `alerts`.
- Foreign keys connect price and alert records to their parent commodity and market records.

This removes the need to repeat complete commodity and market descriptions in every price or alert
record. It also allows commodity and market records to exist independently of individual price
observations.

---

## 7. Boyce–Codd Normal Form (BCNF)

**Rule:** For every non-trivial functional dependency `X → Y`, the determinant `X` must be a
superkey of the relation.

BCNF is stricter than 3NF. The analysis below uses the primary keys and UNIQUE constraints
explicitly declared in `database/schema_prices.sql`. It does not assume undocumented business
dependencies.

| Table | Primary Key | Additional declared unique key | BCNF assessment |
|---|---|---|---|
| `commodities` | `id` | `(name, variety, grade)` | ✔ Declared determinants identify a row. |
| `markets` | `id` | `(name, district, state)` | ✔ Declared determinants identify a row. |
| `spot_prices` | `id` | `(commodity_id, market_id, price_date)` | ✔ Declared determinants identify a row. |
| `futures_prices` | `id` | `(commodity_id, contract_month, price_date)` | ✔ Declared determinants identify a row. |
| `alerts` | `id` | None declared | ✔ `id` is the declared determinant. |

### 7.1 Why `commodities` Has a Composite Candidate Key

The `commodities` table has a surrogate primary key, `id`, and a composite uniqueness rule on
`(name, variety, grade)`. The schema uses `UNIQUE NULLS NOT DISTINCT`, so combinations containing
null values are treated as duplicates for uniqueness enforcement.

The declared determinants are therefore `id` and the complete composite combination
`(name, variety, grade)`. Both identify a commodity row under the schema's declared constraints.

### 7.2 Why `markets` Has a Composite Candidate Key

The `markets` table has a primary key `id` and a composite uniqueness rule on
`(name, district, state)`, also using `NULLS NOT DISTINCT`.

The complete combination identifies a market row. The schema does not declare that the market
name alone uniquely identifies a market, so no such dependency is assumed here.

### 7.3 Why `spot_prices` Has a Composite Candidate Key

The `spot_prices` table has a primary key `id` and a composite UNIQUE constraint on
`(commodity_id, market_id, price_date)`.

This means the same commodity cannot have more than one spot-price row for the same market and
date under this constraint. The complete combination identifies the observation.

### 7.4 Why `futures_prices` Has a Composite Candidate Key

The `futures_prices` table has a primary key `id` and a composite uniqueness rule on
`(commodity_id, contract_month, price_date)`, using `NULLS NOT DISTINCT`.

The complete combination identifies a futures-price row under the schema's uniqueness rule.
The schema does not define a separate futures-contract master table.

### 7.5 Why `alerts` Uses Its Surrogate Key

The `alerts` table declares `id` as its primary key and does not declare another UNIQUE
constraint. Therefore, the only candidate key evidenced by the SQL schema is `id`.

**BCNF conclusion:** Based on the declared primary keys and unique constraints, each table's
documented non-trivial determinants are keys. No non-key determinant violating BCNF is specified
in the supplied SQL schema. This conclusion is limited to the functional dependencies established
by the schema; additional business rules could require further analysis.

---

## 8. Deliberate Denormalization

The SQL schema contains one field that may be viewed as overlapping with information stored in
another relation:

| Column | Table | Related information | Observation |
|---|---|---|---|
| `unit` | `alerts` | `commodities.unit` | The alert stores its own unit even though it also references a commodity. This may be useful to preserve the unit associated with the alert, but the project files do not explicitly document whether it is intended as a snapshot or whether it must always match the commodity's current unit. |

The `alerts.unit` field has a default value of `'Quintal'`. The schema does not define a trigger
or constraint that automatically copies `commodities.unit` into `alerts.unit`, nor does it enforce
that both values remain equal.

For that reason, this is recorded as a possible duplicated attribute rather than asserting a
documented denormalization strategy.

The other tables primarily use foreign keys to reference commodity and market information instead
of copying their descriptive fields into price observations.

---

## 9. Database Constraints and Integrity Rules

This section distinguishes constraints enforced by the SQL schema from validations implemented
in the visible backend code.

### 9.1 Database-Level Constraints (actual SQL schema)

| Rule | Mechanism | Table / Column |
|---|---|---|
| Every commodity has an ID | `SERIAL PRIMARY KEY` | `commodities.id` |
| Commodity name is required | `NOT NULL` | `commodities.name` |
| A commodity combination is unique, treating nulls as equal | `UNIQUE NULLS NOT DISTINCT` | `commodities(name, variety, grade)` |
| Every market has an ID | `SERIAL PRIMARY KEY` | `markets.id` |
| Market name is required | `NOT NULL` | `markets.name` |
| A market combination is unique, treating nulls as equal | `UNIQUE NULLS NOT DISTINCT` | `markets(name, district, state)` |
| Every spot-price row has an ID | `SERIAL PRIMARY KEY` | `spot_prices.id` |
| Spot price must reference an existing commodity | Foreign key | `spot_prices.commodity_id` |
| Spot price must reference an existing market | Foreign key | `spot_prices.market_id` |
| Spot-price date is required | `NOT NULL` | `spot_prices.price_date` |
| One spot-price row per commodity, market, and date | Composite `UNIQUE` | `spot_prices(commodity_id, market_id, price_date)` |
| Every futures-price row has an ID | `SERIAL PRIMARY KEY` | `futures_prices.id` |
| Futures price must reference an existing commodity | Foreign key | `futures_prices.commodity_id` |
| Futures-price date is required | `NOT NULL` | `futures_prices.price_date` |
| Futures-price combination is unique, treating null contract months as equal | `UNIQUE NULLS NOT DISTINCT` | `futures_prices(commodity_id, contract_month, price_date)` |
| Every alert has an ID | `SERIAL PRIMARY KEY` | `alerts.id` |
| Alert must reference an existing commodity | Foreign key with `ON DELETE CASCADE` | `alerts.commodity_id` |
| Alert must reference an existing market | Foreign key with `ON DELETE CASCADE` | `alerts.market_id` |
| Alert target price is required | `NOT NULL` | `alerts.target_price` |
| Alert direction is required | `NOT NULL` | `alerts.direction` |
| Alert direction must be `above` or `below` | `CHECK (direction IN ('above', 'below'))` | `alerts.direction` |
| Default alert unit is `Quintal` | `DEFAULT 'Quintal'` | `alerts.unit` |
| Default alert status is `active` | `DEFAULT 'active'` | `alerts.status` |
| Alert creation time defaults to current timestamp | `DEFAULT CURRENT_TIMESTAMP` | `alerts.created_at` |

**Referential behavior:** The `alerts` foreign keys explicitly specify `ON DELETE CASCADE`.
The foreign keys in `spot_prices` and `futures_prices` do not specify an `ON DELETE` action in
the supplied SQL. PostgreSQL's default restrictive behavior therefore applies to referenced
commodity and market rows while dependent price records exist.

### 9.2 Application-Level Validations and Data-Cleaning Rules

The project also contains rules in JavaScript. These are not all database constraints.

| Rule | Where evidenced | Implementation detail |
|---|---|---|
| NCR extraction is limited to selected districts | `backend/jobs/extractNCR.js` | Filters for Delhi, Faridabad, Gurugram, and Ghaziabad; maps the Gurgaon alias to Gurugram. |
| Text values are trimmed and repeated whitespace is collapsed | `backend/jobs/normalizeNCR.js` | `normalizeText()` |
| Selected district aliases are standardized | `backend/jobs/normalizeNCR.js` | Gurgaon and Gurugram are standardized to Gurugram; Delhi and Faridabad are standardized. |
| Arrival date must be present and use a three-part slash-separated format | `backend/jobs/normalizeNCR.js` | `normalizeDate()` |
| Arrival date must be a valid calendar date | `backend/jobs/normalizeNCR.js` | Checks the UTC year, month, and day after parsing. |
| Price values must be present, numeric, and non-negative | `backend/jobs/normalizeNCR.js` | `normalizePrice()` |
| Minimum price must not exceed maximum price | `backend/jobs/normalizeNCR.js` | Rejects `min_price > max_price`. |
| Modal price must be within the minimum and maximum prices | `backend/jobs/normalizeNCR.js` | Rejects modal price outside the range. |
| State, district, market, and commodity are required in normalized records | `backend/jobs/normalizeNCR.js` | Required-field check after normalization. |
| Duplicate normalized source records are removed | `backend/jobs/normalizeNCR.js` | Builds a key from state, district, market, commodity, variety, grade, and arrival date. |
| Alert target price must be positive | `backend/controllers/alertController.js` | `createAlert` checks the numeric target and rejects values less than or equal to zero. |
| Alert direction must be `above` or `below` | `backend/controllers/alertController.js` | `createAlert` validates the direction before creating the in-memory alert. |
| Commodity and market must exist before creating an alert | `backend/controllers/alertController.js` | Looks up the IDs in the imported mock-data collections. |

**Implementation limitation:** The visible `alertController.js` uses `../data/mockData` for alert
creation, listing, and deletion. The supplied ZIP does not include that referenced
`backend/data/mockData` file. The catalog controller does query PostgreSQL through the database
pool, while the visible intelligence and alert controllers import mock data. Therefore, the
JavaScript validations above should not be described as database-enforced rules.

---

## 10. Design Issues and Honest Notes

The following observations are based on the supplied SQL and backend files. They are design
trade-offs or areas that could be strengthened; they are not claims that the application already
implements additional safeguards.

### 10.1 `alerts.unit` Can Overlap with `commodities.unit`

```sql
CREATE TABLE alerts (
    ...
    commodity_id INTEGER NOT NULL REFERENCES commodities(id) ON DELETE CASCADE,
    ...
    unit VARCHAR(50) DEFAULT 'Quintal',
    ...
);
```

The alert references a commodity, and the commodity table already contains a `unit` field.
Keeping `unit` in `alerts` may be useful if the unit is intended to be captured at alert-creation
time. However, the supplied schema does not document that snapshot behavior and does not enforce
equality between the two values. If the commodity's unit changes, an existing alert could retain
a different unit.

### 10.2 No Price-Range CHECK Constraints in the SQL Schema

The SQL schema stores `min_price`, `max_price`, and `modal_price` in `spot_prices`, but it does
not define database CHECK constraints requiring:

```sql
min_price <= max_price
min_price <= modal_price
modal_price <= max_price
```

The data-normalization job checks these relationships before writing its normalized JSON output.
Those checks are not equivalent to database constraints: a direct SQL insert could bypass the
JavaScript job.

**Recommendation:** Consider adding SQL CHECK constraints if these relationships must be enforced
for every database write.

### 10.3 Non-Negative Price and Quantity Constraints Are Not Declared in SQL

The numeric fields include spot minimum, maximum, and modal prices, arrival quantity, futures
settlement price, and alert target price. The supplied schema does not declare CHECK constraints
to require all of these values to be non-negative.

The JSON normalization job rejects negative spot-price values, and the alert controller checks
for a positive target price in its in-memory workflow. These checks do not establish equivalent
database-wide constraints.

**Recommendation:** Add suitable CHECK constraints if non-negative values are required for all
direct database writes. The exact rule for zero should be decided by the project requirements.

### 10.4 Futures Contract Information Is Stored in the Observation Table

```sql
CREATE TABLE futures_prices (
    ...
    commodity_id INTEGER NOT NULL REFERENCES commodities(id),
    contract_month DATE,
    expiry_date DATE,
    price_date DATE NOT NULL,
    settlement_price NUMERIC(12, 2),
    ...
);
```

The table stores contract month and expiry date alongside each dated settlement-price observation.
The supplied schema does not define a separate contract master table. If the same contract is
recorded across multiple price dates, its expiry date may be repeated across those rows.

A separate futures-contract relation could be considered if contract-level attributes become
more extensive or need independent management. The current schema does not establish that such
a decomposition is required.

### 10.5 Nullable Contract Month and Expiry Date

`contract_month` and `expiry_date` are nullable in the SQL schema. The futures uniqueness rule uses
`UNIQUE NULLS NOT DISTINCT` on `(commodity_id, contract_month, price_date)`, which means null
contract months are treated as equal for the purpose of this uniqueness constraint.

The project files do not explain when a futures record may legitimately omit its contract month or
expiry date. If these fields are mandatory for every futures observation, the schema could be
tightened with `NOT NULL` after confirming the business rule.

### 10.6 Alert Status Is Free Text

```sql
status VARCHAR(20) NOT NULL DEFAULT 'active'
```

The schema gives `status` a default value of `active`, but it does not restrict the possible
values with an enum, CHECK constraint, or reference table. Other strings could therefore be
stored through direct database writes.

**Recommendation:** If the application has a fixed set of alert states, define and enforce the
allowed values using a CHECK constraint or a dedicated status type/table.

### 10.7 No Unique Constraint for Alerts

The `alerts` table has a primary key on `id`, but no additional uniqueness rule. As written, the
database can store multiple alerts with the same commodity, market, target price, and direction.

This may be intentional because a user could create multiple alerts for the same threshold.
The schema does not include a user identifier, so it also does not define user ownership or
uniqueness per user.

### 10.8 Backend and Database Integration Is Not Uniform in the Supplied Files

The catalog controller (`catalogController.js`) imports the PostgreSQL pool and runs SQL queries
against `commodities`, `markets`, and `spot_prices`. The visible alert and intelligence controllers
import collections from `backend/data/mockData`.

The referenced `backend/data/mockData` file is not present in the supplied ZIP. Consequently,
the visible source does not demonstrate that all alert and intelligence operations are currently
reading from or writing to the PostgreSQL tables.

This distinction matters when documenting integrity: a validation performed on an in-memory
mock object is not a PostgreSQL constraint.

### 10.9 Data Normalization Pipeline and Database Normalization Are Different

The project includes `extractNCR.js` and `normalizeNCR.js`. These scripts perform data preparation:
regional filtering, text cleanup, district alias standardization, date parsing, numeric validation,
range checks, and duplicate removal.

These operations improve source-data consistency, but they are different from relational database
normalization (1NF, 2NF, 3NF, and BCNF). The relational normalization is achieved through the
separate SQL tables and their keys and relationships.

---

## 11. Conclusion

The AgriPulse SQL schema separates commodity, market, spot-price, futures-price, and alert
information into five relational tables. This design avoids placing all agricultural information
in one large register and uses primary keys, foreign keys, and unique constraints to identify
records and maintain relationships.

The normalization path can be summarized as follows:

| Step | Key action |
|---|---|
| **UNF → 1NF** | Replaced the conceptual flat register with separate atomic relations for commodities, markets, spot prices, futures prices, and alerts. |
| **1NF → 2NF** | Confirmed that each table uses a single-column surrogate primary key, so partial dependency on a proper subset of the primary key cannot occur. |
| **2NF → 3NF** | Separated commodity and market descriptions from price observations and alerts, connecting related records through foreign keys. |
| **3NF → BCNF** | Checked the determinants established by the declared primary keys and UNIQUE constraints; each declared determinant identifies a row. |

The five tables are:

1. `commodities`
2. `markets`
3. `spot_prices`
4. `futures_prices`
5. `alerts`

The SQL schema enforces referential integrity for the declared foreign keys, composite uniqueness
for commodity, market, spot-price, and futures-price records, and a restricted set of values for
`alerts.direction`.

The project also includes a data-cleaning pipeline that standardizes NCR source records before
they are saved as normalized JSON. These data-cleaning steps complement, but do not replace,
relational database normalization.

**Recommendations for future hardening:**

- Add database CHECK constraints for valid spot-price ranges (`min_price`, `modal_price`, and
  `max_price`) if those rules must apply to every SQL write.
- Consider non-negative CHECK constraints for prices and arrival quantity.
- Decide whether `alerts.unit` is a historical snapshot or should always match `commodities.unit`.
- Restrict `alerts.status` to a documented set of valid values if it is not intended to be free text.
- Clarify whether `contract_month` and `expiry_date` must be mandatory for futures-price records.
- Consider a separate futures-contract table if contract-level attributes grow or need independent
  management.
- Ensure the backend uses the PostgreSQL database consistently where persistent database behavior
  is intended, rather than relying on mock-data collections.
