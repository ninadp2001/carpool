-- CarPool database schema (PostgreSQL 16)
--
-- Plain-SQL equivalent of backend/alembic/versions/8e4ca7b8ce70_initial_schema.py,
-- plus the catalogue data from backend/app/seed.py (cars, wash plans, wash centres).
--
-- Alembic migrations remain the source of truth. Use this file to read the schema
-- or to set up a database without Python:
--
--     psql -U carpool -d carpool -f database/schema.sql
--
-- It records the migration version, so `alembic upgrade head` works afterwards.
-- User accounts are not included: passwords must be bcrypt-hashed, so create the
-- admin with `python -m app.seed` (it skips catalogue rows that already exist).
--
-- Money columns are integer paise (Rs 1 = 100 paise). Like the migration, columns
-- have no SQL defaults: the API always sets status, timestamps and flags itself.

BEGIN;

-- ------------------------------------------------------------------ users

CREATE TABLE users (
    id            SERIAL PRIMARY KEY,
    first_name    VARCHAR(60)  NOT NULL,
    last_name     VARCHAR(60)  NOT NULL,
    email         VARCHAR(255) NOT NULL,
    phone         VARCHAR(20),
    password_hash VARCHAR(255) NOT NULL,
    is_admin      BOOLEAN      NOT NULL,
    is_active     BOOLEAN      NOT NULL,
    created_at    TIMESTAMPTZ  NOT NULL
);
CREATE UNIQUE INDEX ix_users_email ON users (email);

-- ------------------------------------------------------------------ rental

CREATE TABLE cars (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(80)  NOT NULL,
    seats       INTEGER      NOT NULL,
    rate_per_km INTEGER      NOT NULL,          -- paise per km
    image       VARCHAR(255),
    is_active   BOOLEAN      NOT NULL
);

CREATE TABLE rental_bookings (
    id           SERIAL PRIMARY KEY,
    user_id      INTEGER     NOT NULL REFERENCES users (id),
    car_id       INTEGER     NOT NULL REFERENCES cars (id),
    pickup_date  DATE        NOT NULL,
    km           INTEGER     NOT NULL,
    rate_per_km  INTEGER     NOT NULL,          -- snapshot at booking time
    base_amount  INTEGER     NOT NULL,
    tax_amount   INTEGER     NOT NULL,
    total_amount INTEGER     NOT NULL,
    status       VARCHAR(20) NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL
);
CREATE INDEX ix_rental_bookings_status  ON rental_bookings (status);
CREATE INDEX ix_rental_bookings_user_id ON rental_bookings (user_id);

-- ------------------------------------------------------------------ wash

CREATE TABLE wash_plans (
    id        SERIAL PRIMARY KEY,
    name      VARCHAR(80) NOT NULL,
    price     INTEGER     NOT NULL,             -- paise, before tax
    features  JSON        NOT NULL,
    is_active BOOLEAN     NOT NULL
);

CREATE TABLE wash_centers (
    id            SERIAL PRIMARY KEY,
    name          VARCHAR(120) NOT NULL,
    area          VARCHAR(80)  NOT NULL,
    address       TEXT         NOT NULL,
    phone         VARCHAR(20),
    slot_capacity INTEGER      NOT NULL,   -- cars per time slot
    is_active     BOOLEAN      NOT NULL
);

CREATE TABLE wash_bookings (
    id           SERIAL PRIMARY KEY,
    user_id      INTEGER     NOT NULL REFERENCES users (id),
    plan_id      INTEGER     NOT NULL REFERENCES wash_plans (id),
    center_id    INTEGER     NOT NULL REFERENCES wash_centers (id),
    wash_date    DATE        NOT NULL,
    slot         TIME        NOT NULL,
    base_amount  INTEGER     NOT NULL,
    tax_amount   INTEGER     NOT NULL,
    total_amount INTEGER     NOT NULL,
    status       VARCHAR(20) NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL
);
CREATE INDEX ix_wash_bookings_status    ON wash_bookings (status);
CREATE INDEX ix_wash_bookings_user_id   ON wash_bookings (user_id);
CREATE INDEX ix_wash_bookings_wash_date ON wash_bookings (wash_date);

-- ------------------------------------------------------------------ carpool

CREATE TABLE rides (
    id              SERIAL PRIMARY KEY,
    driver_id       INTEGER      NOT NULL REFERENCES users (id),
    origin          VARCHAR(120) NOT NULL,
    destination     VARCHAR(120) NOT NULL,
    depart_at       TIMESTAMPTZ  NOT NULL,
    seats_total     INTEGER      NOT NULL,
    seats_available INTEGER      NOT NULL,
    price_per_seat  INTEGER      NOT NULL,      -- paise, before tax
    vehicle         VARCHAR(80),
    notes           TEXT,
    status          VARCHAR(20)  NOT NULL,   -- open | cancelled | completed
    created_at      TIMESTAMPTZ  NOT NULL
);
CREATE INDEX ix_rides_depart_at   ON rides (depart_at);
CREATE INDEX ix_rides_destination ON rides (destination);
CREATE INDEX ix_rides_driver_id   ON rides (driver_id);
CREATE INDEX ix_rides_origin      ON rides (origin);
CREATE INDEX ix_rides_status      ON rides (status);

CREATE TABLE ride_bookings (
    id           SERIAL PRIMARY KEY,
    ride_id      INTEGER     NOT NULL REFERENCES rides (id),
    passenger_id INTEGER     NOT NULL REFERENCES users (id),
    seats        INTEGER     NOT NULL,
    base_amount  INTEGER     NOT NULL,
    tax_amount   INTEGER     NOT NULL,
    total_amount INTEGER     NOT NULL,
    status       VARCHAR(20) NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL,
    CONSTRAINT uq_ride_passenger UNIQUE (ride_id, passenger_id)
);
CREATE INDEX ix_ride_bookings_passenger_id ON ride_bookings (passenger_id);
CREATE INDEX ix_ride_bookings_ride_id      ON ride_bookings (ride_id);
CREATE INDEX ix_ride_bookings_status       ON ride_bookings (status);

-- ------------------------------------------------------------------ payments

CREATE TABLE payments (
    id           SERIAL PRIMARY KEY,
    user_id      INTEGER     NOT NULL REFERENCES users (id),
    booking_kind VARCHAR(10) NOT NULL,          -- rental | wash | ride
    booking_id   INTEGER     NOT NULL,
    amount       INTEGER     NOT NULL,          -- paise
    currency     VARCHAR(3)  NOT NULL,
    provider     VARCHAR(20) NOT NULL,          -- razorpay | mock
    order_id     VARCHAR(64) NOT NULL,
    payment_id   VARCHAR(64),
    status       VARCHAR(10) NOT NULL,   -- created | paid | failed
    created_at   TIMESTAMPTZ NOT NULL,
    paid_at      TIMESTAMPTZ
);
CREATE UNIQUE INDEX ix_payments_order_id ON payments (order_id);
CREATE INDEX ix_payments_status  ON payments (status);
CREATE INDEX ix_payments_user_id ON payments (user_id);

-- ------------------------------------------------------------------ alembic

CREATE TABLE alembic_version (
    version_num VARCHAR(32) NOT NULL,
    CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num)
);
INSERT INTO alembic_version (version_num) VALUES ('8e4ca7b8ce70');

-- ------------------------------------------------------------------ catalogue data

INSERT INTO cars (name, seats, rate_per_km, image, is_active) VALUES
    ('Maruti WagonR',          4,  800, '/cars/wagonr.jpg', TRUE),
    ('Tata Tiago',             4,  800, '/cars/tiago.jpg', TRUE),
    ('Maruti Swift Dzire',     5, 1000, '/cars/dzire.jpg', TRUE),
    ('Hyundai Verna',          5, 1000, '/cars/verna.jpg', TRUE),
    ('Maruti Ertiga',          7, 1300, '/cars/ertiga.jpg', TRUE),
    ('Toyota Innova Crysta',   7, 1300, '/cars/innova.jpg', TRUE),
    ('Tata Winger',           13, 1800, '/cars/winger.jpg', TRUE),
    ('Force Tempo Traveller', 17, 2200, '/cars/traveller.jpg', TRUE);

INSERT INTO wash_plans (name, price, features, is_active) VALUES
    ('Basic',     55000, '["Seat wash", "Vacuum", "Exterior wash"]', TRUE),
    ('Premium',   75000, '["Seat wash", "Vacuum", "Exterior wash", "Interior wet clean", "Window wipe"]', TRUE),
    ('Complete', 105000, '["Seat wash", "Vacuum", "Exterior wash", "Interior wet clean", "Window wipe", "Disinfection", "Polish and detailing"]', TRUE);

INSERT INTO wash_centers (name, area, address, phone, slot_capacity, is_active) VALUES
    ('Splash & Dash',        'Kandivali West', '402 Blue Empress Apartments, Borsapada Road, opp. Poisar Gymkhana, Mumbai 400067', '7947411184', 2, TRUE),
    ('PaajiAuto',            'Malad West',     'Evershine Nagar, New Link Road, near Movie Time Cinema, Mumbai 400064', '7949315450', 2, TRUE),
    ('Extreme Car Care',     'Ghansoli',       'Shop 1, Vanai Niwas, Sector 2, near Ghansoli Station, Navi Mumbai 400701', '7947288767', 2, TRUE),
    ('360 Moto Care',        'Kharghar',       'Shops B-15 and A-16, Shah Arcade, Sector 6, near Global IT Park, Navi Mumbai 410210', '7947179719', 2, TRUE),
    ('Auto Launder',         'Prabhadevi',     'Plot 105B, S L Matkar Road, near Parel ST Depot, Mumbai 400025', '7947197114', 2, TRUE),
    ('Baba Auto Garage',     'Ghatkopar West', 'Patan Wada Compound, LBS Marg, opp. Brand Factory, Mumbai 400084', '7947186715', 2, TRUE),
    ('Zebro Auto Care',      'Chembur East',   'Plot 7, Laxmi Narayan Shopping Complex, Sion Trombay Road, Mumbai 400071', '7947168789', 2, TRUE),
    ('VKS Auto Shine',       'Thane West',     'Next to Tata Motors, Eastern Express Highway, Thane 400602', '8045783832', 2, TRUE),
    ('3C Crystal Clear Car', 'Mulund West',    'Zojawala Petroleum, LBS Marg, opp. Santoshi Mata Temple, Mumbai 400080', '7947371337', 2, TRUE),
    ('Star Auto Care',       'Colaba',         '4th Pasta Lane, near Colaba Market Post Office, Mumbai 400005', '9920069887', 2, TRUE);

COMMIT;
