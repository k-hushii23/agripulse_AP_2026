-- 1. COMMODITIES TABLE
-- Stores crop names, varieties, grades and units.

CREATE TABLE IF NOT EXISTS commodities (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    variety VARCHAR(255),
    grade VARCHAR(100),
    unit VARCHAR(50),

    CONSTRAINT unique_commodity
    UNIQUE NULLS NOT DISTINCT (name, variety, grade)
);


-- 2. MARKETS TABLE
-- Stores agricultural market information.

CREATE TABLE IF NOT EXISTS markets (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    district VARCHAR(255),
    state VARCHAR(255),

    CONSTRAINT unique_market
    UNIQUE NULLS NOT DISTINCT (name, district, state)
);


-- 3. SPOT PRICES TABLE
-- Stores daily mandi prices from Agmarknet.

CREATE TABLE IF NOT EXISTS spot_prices (
    id SERIAL PRIMARY KEY,

    commodity_id INTEGER NOT NULL,
    market_id INTEGER NOT NULL,

    price_date DATE NOT NULL,

    min_price NUMERIC(12, 2),
    max_price NUMERIC(12, 2),
    modal_price NUMERIC(12, 2),

    arrival_qty NUMERIC(12, 2),

    CONSTRAINT fk_spot_commodity
        FOREIGN KEY (commodity_id)
        REFERENCES commodities(id),

    CONSTRAINT fk_spot_market
        FOREIGN KEY (market_id)
        REFERENCES markets(id),

    CONSTRAINT unique_spot_price
        UNIQUE (commodity_id, market_id, price_date)
);


-- 4. FUTURES PRICES TABLE
-- Stores NCDEX futures market data.

CREATE TABLE IF NOT EXISTS futures_prices (
    id SERIAL PRIMARY KEY,

    commodity_id INTEGER NOT NULL,

    contract_month DATE,
    expiry_date DATE,
    price_date DATE NOT NULL,

    settlement_price NUMERIC(12, 2),

    CONSTRAINT fk_futures_commodity
        FOREIGN KEY (commodity_id)
        REFERENCES commodities(id),

    CONSTRAINT unique_futures_price
        UNIQUE NULLS NOT DISTINCT (commodity_id, contract_month, price_date)
);
-- 5. ALERTS TABLE
-- Stores user-defined price-threshold notifications (PRD Section 10).


CREATE TABLE IF NOT EXISTS alerts (
    id SERIAL PRIMARY KEY,
    commodity_id INTEGER NOT NULL REFERENCES commodities(id) ON DELETE CASCADE,
    market_id INTEGER NOT NULL REFERENCES markets(id) ON DELETE CASCADE,
    target_price NUMERIC(12, 2) NOT NULL,
    unit VARCHAR(50) DEFAULT 'Quintal',
    direction VARCHAR(10) NOT NULL CHECK (direction IN ('above', 'below')),
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);