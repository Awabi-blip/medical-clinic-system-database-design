CREATE TYPE gender AS ENUM ('Male', 'Female');
CREATE TYPE neurotype AS ENUM ('Typical', 'ASD', 'ADHD', 'OCD', 'BPD', 'Dyslexia',
'Dyspraxia', 'Dyscalculia', 'Dysgraphia');
CREATE TYPE bloodtype AS ENUM ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-');
CREATE TYPE all_roles AS ENUM ('patient', 'doctor', 'nurse', 'hospital_manager', 'pharmacist', 'db_admin');

CREATE TABLE IF NOT EXISTS "profiles"(
    "id" UUID,
    "first_name" TEXT NOT NULL,
    "last_name" TEXT NOT NULL,
    "gender" gender NOT NULL,
    "date_of_birth" DATE NOT NULL,
    "phone_number" TEXT NOT NULL UNIQUE,
    PRIMARY KEY ("id"),
    FOREIGN KEY ("id") REFERENCES auth.users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "user_roles"(
    "id" UUID,
    "role" all_roles,
    PRIMARY KEY ("id", "role"),
    FOREIGN KEY ("id") REFERENCES "profiles"("id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "active_users_role"(
    "user_id" UUID,
    "role" all_roles NOT NULL,
    "expiry_time" TIMESTAMP NOT NULL,
    "session_id" UUID DEFAULT NULL,
    PRIMARY KEY ("user_id"), -- not composite primary key because that allows more than(one user must only have one role at active_time)
    FOREIGN KEY ("user_id", "role") REFERENCES user_roles("id", "role")
);

CREATE TYPE staff_role AS ENUM ('hospital_manager', 'doctor', 'db_admin');

CREATE TABLE IF NOT EXISTS "management_staff" (
    "id" UUID,
    "role" staff_role,
    PRIMARY KEY ("id", "role"),  -- composite PK prevents duplicate roles
    FOREIGN KEY ("id") REFERENCES profiles(id) ON DELETE CASCADE
);

CREATE TYPE worker_role AS ENUM ('nurses', 'pharmacists');

CREATE TABLE IF NOT EXISTS "worker_staff"(
    "id" UUID,
    "role" worker_role,
    "shift_start" TIME(0) NOT NULL CHECK (EXTRACT(SECOND FROM "shift_start") = 0),
    "shift_end" TIME(0) NOT NULL CHECK (EXTRACT(SECOND FROM "shift_end") = 0),
    CHECK ("shift_start" < "shift_end"),
    "joined_at" DATE NOT NULL DEFAULT NOW(),
    PRIMARY KEY ("id", "role"),
    FOREIGN KEY ("id") REFERENCES profiles(id) ON DELETE CASCADE
);
    
CREATE TABLE IF NOT EXISTS "db_admins"(
    "id" UUID,
    "education" TEXT NOT NULL,
    "experience" TEXT NOT NULL,
    "license_number" CHAR(8) NOT NULL,
    PRIMARY KEY ("id"),
    FOREIGN KEY ("id") REFERENCES profiles(id)
);

CREATE TABLE IF NOT EXISTS "hospital_managers"(
    "id" UUID,
    "education" TEXT NOT NULL,
    "experience" TEXT NOT NULL,
    "license_number" CHAR(8) NOT NULL,
    "department" TEXT NOT NULL,
    PRIMARY KEY("id"),
    FOREIGN KEY ("id") REFERENCES profiles(id)
);

CREATE TABLE IF NOT EXISTS "patients" (
    "id" UUID,
    "allergies" TEXT[] DEFAULT NULL,
    "bloodtype" bloodtype DEFAULT NULL,
    "neurotype" neurotype[] DEFAULT '{Typical}',
    "chronic_diseases" TEXT[] DEFAULT NULL,
    "last_visited" DATE NOT NULL default now(),
    "bio" TEXT,
    PRIMARY KEY ("id"),
    FOREIGN KEY ("id") REFERENCES auth.users(id) ON DELETE CASCADE
);

CREATE TYPE human_relationships AS ENUM ('Parent', 'Sibling', 'Relative', 'Spouse', 'Friend');

CREATE TABLE IF NOT EXISTS "emergency_patients_contact" (
    "id" SERIAL,
    "patient_id" UUID NOT NULL,
    "relation" human_relationships NOT NULL,
    "relation_gender" gender,
    "phone_number" TEXT NOT NULL, -- not unique becuase more than one patient can have the same emergency contact, imagine 2 children of the same parent
    PRIMARY KEY ("id"),
    FOREIGN KEY ("patient_id") REFERENCES "patients"("id")
);

CREATE TABLE IF NOT EXISTS "nurses" (
    "id" UUID,
    "bio" TEXT,
    "license_number" CHAR(9),
    PRIMARY KEY ("id"),
    FOREIGN KEY ("id") REFERENCES profiles(id) ON DELETE CASCADE
);

CREATE TYPE doctor_specializations AS ENUM ('Generalist', 'ENT', 'Pediatrician', 'Dermatologist',
'General_Physician', 'Gynecologist', 'Therapist', 'Orthopedic');

CREATE TABLE IF NOT EXISTS "doctors" (
    "id" UUID,
    "specialization" doctor_specializations NOT NULL,
    "education" TEXT NOT NULL,
    "license_number" CHAR(7) NOT NULL,
    PRIMARY KEY ("id"),
    FOREIGN KEY ("id") REFERENCES profiles(id) ON DELETE CASCADE
);

CREATE TYPE working_days AS ENUM ('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
 'Saturday', 'Sunday');

CREATE TABLE IF NOT EXISTS "doctor_schedule" (
    "id" BIGSERIAL,
    "day" working_days NOT NULL,
    "doctor_id" UUID NOT NULL,   
    "shift_start" TIME(0) NOT NULL CHECK (EXTRACT(SECOND FROM "shift_start") = 0),
    "shift_end" TIME(0) NOT NULL CHECK (EXTRACT(SECOND FROM "shift_end") = 0),
    "hourly_rate" DECIMAL(6,2) NOT NULL CHECK ("hourly_rate" >= 0 AND "hourly_rate" < 2000.00),
    PRIMARY KEY ("id"),
    FOREIGN KEY ("doctor_id") REFERENCES "doctors"("id") ON DELETE CASCADE
);

CREATE TYPE appointment_status AS ENUM ('scheduled', 'completed', 'cancelled', 'on_going');

CREATE OR REPLACE FUNCTION find_day_for_appointments(
    "ts" TIMESTAMPTZ
) RETURNS working_days AS $$
DECLARE
    v_extracted_day INT;
BEGIN
    v_extracted_day := EXTRACT(ISODOW FROM ("ts" AT TIME ZONE 'UTC'));
        CASE v_extracted_day
            WHEN 1 THEN RETURN 'Monday'::working_days;
            WHEN 2 THEN RETURN 'Tuesday'::working_days;
            WHEN 3 THEN RETURN 'Wednesday'::working_days;
            WHEN 4 THEN RETURN 'Thursday'::working_days;
            WHEN 5 THEN RETURN 'Friday'::working_days;
            WHEN 6 THEN RETURN 'Saturday'::working_days;
            WHEN 7 THEN RETURN 'Sunday'::working_days;
            ELSE RAISE EXCEPTION 'Invalid date';
        END CASE;
    END;
$$ LANGUAGE plpgsql IMMUTABLE;
    
CREATE TABLE IF NOT EXISTS "appointments" (
    "id" BIGSERIAL,
    "patient_id" UUID NOT NULL,
    "doctor_id" UUID NOT NULL,
    "note" TEXT DEFAULT 'pending',
    "diagnosis" TEXT DEFAULT 'pending',
    "status" appointment_status NOT NULL DEFAULT 'scheduled',
    "scheduled_at" TIMESTAMPTZ NOT NULL CHECK (EXTRACT(SECOND FROM "scheduled_at") = 0),
    "day" working_days GENERATED ALWAYS AS (
        find_day_for_appointments("scheduled_at")
    ) STORED,   
    "duration_hours" DECIMAL(2,1) NOT NULL DEFAULT 0.5 CHECK( duration_hours IN (0.5, 1, 1.5, 2)),
    PRIMARY KEY ("id"),
    FOREIGN KEY ("patient_id") REFERENCES "patients"("id"),
    FOREIGN KEY ("doctor_id") REFERENCES "doctors"("id")
);

CREATE TABLE IF NOT EXISTS "prescriptions" (
    "id" BIGSERIAL,
    "appointment_id" BIGINT NOT NULL,
    "medication" TEXT NOT NULL,
    "potency" TEXT NOT NULL, -- i.e 500mg or any other unit
    "frequency" TEXT NOT NULL, -- 2 times a day etc
    "start_date" DATE NOT NULL DEFAULT CURRENT_DATE,
    "duration_days" INT NOT NULL, -- to get end date of a prescription, use start_date + days
    PRIMARY KEY ("id"),
    FOREIGN KEY ("appointment_id") REFERENCES "appointments"("id") ON DELETE CASCADE
);

CREATE TYPE payment_method AS ENUM ('stripe', 'cash', 'apple_pay', 'google_pay', 'aid');

CREATE TABLE IF NOT EXISTS "appointments_billing" (
    "appointment_id" BIGINT NOT NULL,
    "total_bill" DECIMAL(8,4) NOT NULL,
    "paid" BOOLEAN NOT NULL, 
    "paid_at" TIMESTAMP DEFAULT NULL,
    "method" payment_method NOT NULL,
    PRIMARY KEY ("appointment_id"),
    FOREIGN KEY ("appointment_id") REFERENCES "appointments"("id") ON DELETE CASCADE
);

CREATE TYPE "ward_name" AS ENUM ('tulip', 'daisy', 'jasmine', 
'lavender', 'blossom', 'rose', 'sunflower');

CREATE TABLE IF NOT EXISTS "wards" (
    "name" ward_name,
    "beds_total" INT NOT NULL,
    "beds_available" INT NOT NULL CHECK ("beds_total" >= 0 AND "beds_available" <= "beds_total"),
    "use_case" TEXT NOT NULL,
    "description" TEXT DEFAULT 'temporary patient stay',
    PRIMARY KEY ("name") 
);

CREATE TABLE IF NOT EXISTS "patients_in_wards"(
    "id" SERIAL,
    "patient_id" UUID NOT NULL,
    "ward_name" ward_name NOT NULL,
    "added_under_emergency" BOOLEAN NOT NULL DEFAULT FALSE,
    "assigned_at" TIMESTAMP NOT NULL DEFAULT now(),
    "discharged_at" TIMESTAMP DEFAULT NULL CHECK (discharged_at > assigned_at),
    PRIMARY KEY ("id"),
    FOREIGN KEY ("patient_id") REFERENCES "patients"("id") ON DELETE CASCADE,
    FOREIGN KEY ("ward_name") REFERENCES "wards"("name") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "nurses_in_wards" (
    "id" SERIAL,
    "nurse_id" UUID NOT NULL,
    "ward_name" ward_name NOT NULL,
    "assigned_at" TIMESTAMP NOT NULL DEFAULT now(),
    "discharged_at" TIMESTAMP DEFAULT NULL CHECK (discharged_at > assigned_at),
    PRIMARY KEY ("id"),
    FOREIGN KEY ("nurse_id") REFERENCES "nurses"("id") ON DELETE CASCADE,
    FOREIGN KEY ("ward_name") REFERENCES "wards"("name") ON DELETE CASCADE
);

CREATE TYPE item_type AS ENUM ('ventilator', 'drip_setup', 'syringes', 'massagers', 
'60W_batteries', '30W_batteries', 'rose_water', 'protein_wheat_biscuits', 'vitamin_supplements');

CREATE TABLE IF NOT EXISTS "item_store_room"(
    "item_type" item_type,
    "amount_total" INT NOT NULL,
    "amount_available" INT NOT NULL CHECK ("amount_available" <= "amount_total"),
    "return_status" BOOLEAN NOT NULL, --to check weather an item can be returned in the first place
    PRIMARY KEY ("item_type")
);

CREATE TABLE IF NOT EXISTS "items_in_wards"(
    "id" SERIAL,
    "item_type" item_type NOT NULL,
    "ward_name" ward_name NOT NULL,
    "amount_used" INT NOT NULL,
    "assigned_by" UUID NOT NULL,
    "assigner_role" staff_role NOT NULL,
    PRIMARY KEY ("id"),
    FOREIGN KEY ("item_type") REFERENCES "item_store_room"("item_type") ON DELETE CASCADE,
    FOREIGN KEY ("ward_name") REFERENCES "wards"("name") ON DELETE CASCADE,
    FOREIGN KEY ("assigned_by", "assigner_role") REFERENCES management_staff(
    "id", "role") ON DELETE CASCADE
);

CREATE TYPE dosage_form AS ENUM ('tablets', 'capsule', 'syrup', 'inhaler', 'ointment', 'injection', 'eye_drops');

CREATE TYPE dosage_units AS ENUM ('mg', 'mg/ml', 'mg/5ml', 'IU/ml', '%', 'mg/g', 'mcg' );

CREATE TABLE "pharmacists"(
    "id" UUID,
    "license_number" CHAR(8), --if 6 digit add a 00 padding.
    PRIMARY KEY ("id"),
    FOREIGN KEY ("id") REFERENCES profiles("id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "workers_time_deductions" (
    "id" SERIAL,
    "worker_id" UUID NOT NULL,
    "worker_role" worker_role,
    "date_of_absence" DATE NOT NULL,
    "hours_deducted" DECIMAL(2,1) NOT NULL,
    "reason" TEXT NOT NULL, -- e.g., "Sick leave", "Late arrival", "Unapproved absence"
    "logged_by" UUID NOT NULL,
    "logger_role" staff_role NOT NULL,
    PRIMARY KEY("id"),
    FOREIGN KEY("worker_id", "worker_role") REFERENCES worker_staff("id", "role") ON DELETE CASCADE,
    FOREIGN KEY("logged_by", "logger_role") REFERENCES "management_staff"("id","role")
);

CREATE TABLE IF NOT EXISTS "workers_salary" (
  "id" SERIAL,
  "worker_id" UUID NOT NULL,
  "worker_role" worker_role,
  "month" INT DEFAULT EXTRACT(MONTH FROM CURRENT_DATE) CHECK ("month" BETWEEN 1 AND 12),
  "year" INT DEFAULT EXTRACT(YEAR FROM CURRENT_DATE) CHECK("year" > 2015), -- maybe if the hospital was built in 2015
  -- check via trigger that there are no salaries in the past or future
  "salary" DECIMAL(12,4),
  PRIMARY KEY ("id"),
  FOREIGN KEY ("worker_id", "worker_role") REFERENCES worker_staff("id","role") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "allowed_dosage_units"(
    "dosage_form" dosage_form NOT NULL,
    "dosage_units" dosage_units NOT NULL,
    PRIMARY KEY ("dosage_form", "dosage_units")
);

CREATE TABLE IF NOT EXISTS "medication_name"(
    "id" SERIAL,
    "name" TEXT NOT NULL UNIQUE,
    PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "medication_inventory"(
    "medication_id" INT, 
    "dosage_strength" DECIMAL(6,2),
    "dosage_form" dosage_form NOT NULL,
    "dosage_units" dosage_units NOT NULL,
    "price_per_unit" DECIMAL(10,2) NOT NULL,
    PRIMARY KEY ("medication_id", "dosage_strength", "dosage_form", "dosage_units"),
    FOREIGN KEY ("medication_id") REFERENCES "medication_name"("id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "audit_logs"(
    "id" SERIAL,
    "action" TEXT NOT NULL,
    "happened_at" TIMESTAMP(0) DEFAULT now() NOT NULL,
    "person_id" UUID NOT NULL,
    "table_name" TEXT NOT NULL,
    "pk" TEXT NOT NULL,
    PRIMARY KEY ("id"),
    FOREIGN KEY ("person_id") REFERENCES profiles(id) ON DELETE CASCADE
);
