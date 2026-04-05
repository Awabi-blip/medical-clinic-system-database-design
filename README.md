# Design Document
By Muhammad Awab

## Scope

The purpose of this database-heavy-backend is to provide a rigid structure for a small-to-medium clinic system, that handles:
- appointments booking and management
- inventory tracking and management
- ward appointments and management
- item ward management
- custom role allocation native to SQL

Outside the scope of this project are Enterprise Grade hospital management, such as Surgery Rooms, Tracking Surgical Data, Psychological Wards, or Integration with other Enterprise systems for accurate medicinal data.

## Functional Requirements
### Actors
The database has a few actors all defined by this ENUM type: 
```SQL 
CREATE TYPE all_roles AS ENUM ('patient', 'doctor', 'nurse', 'hospital_manager','pharmacist', 'db_admin');
```

**profiles** every role has a few key information stored, such as name, email, phone_number and gender.

**patients** can signup and login via normal supabase login, make their profile, which will be added to the patients column, a doctor can then after diagnoses or when the patient visits, add data like, "bloodtype", "neurotype", or "chronic diseases".

**patients relationships** can provide an emergency contact, and could only be from a specific set of predefined values, described by this ENUM:

```SQL
CREATE TYPE human_relationships AS ENUM ('Parent', 'Sibling', 'Relative', 'Spouse', 'Friend');
```
They can have a gender, so a parent if male represents father, and conversely a female spouse would represent a wife, and they also have a phone number.

**nurses** they can sign up only through the hospital portal for admins (to be made), can have a shift_start and a shift_end

**doctors** they can also only sign up through the hospital portal, they have a more dedicated schedule table, where their schedule can vary per day,they also need a license number, an education and a specialization field (could be general specialization too) defined by this ENUM:
```SQL
CREATE TYPE doctor_specializations AS ENUM ('Generalist', 'ENT', 'Pediatrician','Dermatologist', 'General_Physician', 'Gynecologist', 'Therapist', 'Orthopedic');
```

**db_admins** (cool people like me), they are required to have an education, an experience and a license number (usually given by the clinic itself).

**hospital_managers** they are also required to have an education, an experience and they are assigned to their respective departments.

**management_staff** this is a composition of doctors, db_admins, and hospital_staff, usually linked with management decisions, updating profiles, appointments flow and such, assigining nurses to wards, patients to wards, items to wards or overall lookup for the clinic/hop.

## Rules
Overall structural rule enforcement for functionality within the database.

### Appointments
A **patient** can book, cancel, or view their past/upcoming, and pay for their appointments.

A **doctor** can start, cancel, add data to, or view their past/upcoming appointments.
- An appointment can not be started before the scheduled time.
- An appointment must be started before any data can be added to it.
- A doctor may generate the bill for an appointment once it is done, through their manager roles

### Billings
-- Todo

### Wards and Inventory

Their are a total of 7 wards in the clinic as represented by this ENUM:
```SQL
CREATE TYPE "ward_name" AS ENUM ('tulip', 'daisy', 'jasmine', 
'lavender', 'blossom', 'rose', 'sunflower');
```
and a few items that can be placed in each ward in certain amounts namely:
```SQL
CREATE TYPE item_type AS ENUM ('ventilator', 'drip_setup', 'syringes', 'massagers', '60W_batteries', '30W_batteries', 'rose_water', 'protein_wheat_biscuits', 'vitamin_supplements');
```
There is as such no capacity that can be assigned within each ward, but all these items have an amount, and are connected through a transaction such that the data inside the database is consistent.
The ward can be assigned items, if the items available are less than what the ward requires, but it is an emergency, then all those items that are available are assigned to the ward.
Note: a manager role is usually required for items to wards assignement.


### Nurse Deductions

### Items Assignment

### Patients Assignment



## Relationships and Entities
###  Entities

The core entities in the database are patients, doctors, nurses, items, pharmacists, wards, inventory and how each of these relate to each other

There is a base table profiles, which has the core information such as 

```SQL
first_name TEXT,
last_name TEXT,
gender gender ENUM(Male, Female),
date_of_birth DATE,
phone_number TEXT
```
- Reason for using ENUM for gender was to enforce 2 genders, and TEXT for phone number because of hyphens and different formats and country codes and leading 0s as INT types remove leading 0s.

Every other role in the database inherits from this table via Foreign Keys, and has a one to one relationship with each user entity (doctors, patients, nurses, db_admins, hopsital_managers)
that is that one profile can only be related to one doctor or one patient or one nurse and so on.

A single authenticated user can hold multiple roles each represented by separate tables i.e a doctor can use his doctor account to make a patient profile, without needing a new login, but 2 accounts from the same base account.

Some rules regarding multiple roles are enforced at the administration and database level via triggers, that is that a doctor can't be a nurse or a pharmacist all at once. Yes if that doctor retires as a doctor, he can strip away his doctor role and then work as a nurse, that is managed via the user_roles table which looks plainly like this:

```SQL
    "id" UUID,
    "role" all_roles, (refer to ENUM above)
    PRIMARY KEY ("id", "role")
```

The trigger **check_doctor_no_extra_roles** enforces that if someone already has a nurse role or a pharmacist role, they can't have the doctor role, and vice versa too

The reason for using a composite primary key here, was because one id can have more than one role, but there can not be duplicates of one id having multiple of the same role (not an issue for visuals but data redundancy invalidates 1NF constraints).


The patients table
```SQL
    "allergies" TEXT[] DEFAULT NULL,
    "bloodtype" bloodtype DEFAULT NULL,
    "neurotype" neurotype[] DEFAULT '{Typical}',
    "chronic_diseases" TEXT[] DEFAULT NULL,
```
The reason for denormalization is because I intended for this data to be read and write only, as in there is no querying by the chornic diseases or neurotype types and it is mostly for doctor's knowledge about the current patient they are currently treating or have an appointment with.

The bloodtype ENUM goes like this:
```SQL
CREATE TYPE bloodtype AS ENUM ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-');
```

The neurotype ENUM goes like this:
```SQL
CREATE TYPE neurotype AS ENUM ('Typical', 'ASD', 'ADHD', 'OCD', 'BPD', 'Dyslexia',
'Dyspraxia', 'Dyscalculia', 'Dysgraphia');
```

Note: I am not from the medical field and I did not know that BPD is not a neurotype but rather a personality disorder, but I kept it in the ENUM because the removal process is way too hectic.

**Pharmacists and Nurses**
```SQL
"shift_start" TIME(0) NOT NULL CHECK (EXTRACT(SECOND FROM "shift_start") = 0),
"shift_end" TIME(0) NOT NULL CHECK (EXTRACT(SECOND FROM "shift_end") = 0),
```
in addition pharmacists have a CHAR(8) license number.

Time(0) ensures no microseconds are added and the seconds that a shift must start at is set to 0 to avoid weird shift starts or ends.

**Wards**
```SQL
"name" ward_name,
"beds_total" INT NOT NULL,
"beds_available" INT NOT NULL CHECK ("beds_total" >= 0 AND "beds_available" <= "beds_total"),
```
The ward_name ENUM goes like this:

```SQL
CREATE TYPE "ward_name" AS ENUM ('tulip', 'daisy' 'jasmine','lavender', 'blossom', 'rose', 'sunflower');
```

The check constraint enforces that there can't be anomalous values where total_beds go under 0 or that a case arises where beds available are greater than beds total.

The flower names for wards is because of a personal liking and choice.

This is lookup table that and the values stored in it are also based on personal intuition:
![alt text](image.png)

**Items** (table name -> item_store_room)
```SQL
"item_type" item_type,
"amount_total" INT NOT NULL,
"amount_available" INT NOT NULL CHECK("amount_available" <= "amount_total"),
"return_status" BOOLEAN NOT NULL, --to check weather an item can be returned in the first place
```
The item_type ENUM goes like this:
```SQL
CREATE TYPE item_type AS ENUM ('ventilator', 'drip_setup','syringes', 'massagers', '60W_batteries', '30W_batteries', 'rose_water','protein_wheat_biscuits', 'vitamin_supplements');
```
This is also a lookup table and values stored in it are:
![alt text](image-1.png)

**return_status** set to true means that upon borrowing these items can be returned and the **amount_total** stays the same, when the item is assigned to a ward.

In case of **return_status** being false the **amount_total** is also decreased when the item is assigned to a ward.

**Medication Inventory**
```SQL
"dosage_strength" DECIMAL(6,2),
"dosage_form" dosage_form NOT NULL,
"dosage_units" dosage_units NOT NULL,
"price_per_unit" DECIMAL(10,2) NOT NULL,
PRIMARY KEY ("medication_id", "dosage_strength","dosage_form", "dosage_units"),
```

The dosage_form ENUM goes like this:
```SQL
CREATE TYPE dosage_form AS ENUM ('tablets', 'capsule', 'syrup', 'inhaler', 'ointment', 'injection', 'eye_drops');
```

The dosage_units ENUM goes like this:

```SQL
CREATE TYPE dosage_units AS ENUM ('mg', 'mg/ml', 'mg/5ml', 'IU/ml', '%', 'mg/g', 'mcg' );
```
The reason for quadruple primary key is because one medicine, i.e Ibuprofen with its unique ID from medication_names table (more on this in the relationships) in the FK column let's assume 37, 37 can then have, 300, tablets, mg, 1, and also can have 400, tablets, mg, 1 and can also have, 300, syrup, mg/ml and 1 so if only those 4 itmes can ever be unique, as under the same name a medicine can have different strengths in different forms and different units too. A tablet can have mg or mcg while having same strength number i.e 300.

### ERD
![alt text](../ERD.png)
- Generated by pgAdmin4

#### Patients and Doctors
```
patients are related to doctor via the appointments table.

The relationship between them is Many to Many.
```

The appointment table holds the status about the appointments, when it is scheduled and who is it scheduled between.

One doctor can have many appointments with different patients (but not many with the same that are scheduled (enforced by an Unique Index)) and one patient can have many appointments, with many doctors that are scheduled.

The appointments table has key information that the doctor can add, the diagnoses or any notes.

---
#### Appointments and Billings
```
appointments and bills are related via the appointments_billing table, that calculates the bill based on the time and doctor's hourly charge on that day via the bill_appointments function.

The relationship between them is One to One.
```
---

#### Appointments and Prescriptions

```
apointments and prescriptions are related via the prescriptions table, where each appointment's described prescriptions are logged by the doctor.

The relationship between them is One to Many (one appointment session can have many many prescriptions.)
```
---
#### Doctor and Schedules

```
doctors and daily_schedule are related via the  doctor_schedule table

The relationship between them is One to Many (usually upto 7 because one doctor can have upto 7 schedules).
```

doctor_schedule table holds a daily shift_start to shift_end data, and their hourly rate per day. Overnight shifts are disallowed because of scope management (they were extremely hard to implement with days and stuff without proper dating system which is fine for a clinic

---
#### Patients and Wards

```
patients and wards are related via the patients_in_wards table 

The relationship between them Many to Many but one patient in one ward at one time period.
```
One patient can only be in ward ward at one continous period in time, (enforced by a unique index) but they can have a history of overall being in alot of wards and one ward can have more than one patient at a time.

---
#### Nurses, assignements, salaries.
---
```
nurses and assignments are related via the nurses_in_wards where each nurse can be assigned to no more than 3 wards and each ward shall be unique

The relationship between them is Many to Many (upto 3 at a time.) as one nurse can be in many wards and wards can have multiple nurses.
```

```
nurses and salaries are related via the nurses_salary
table 

The relationship between them is One to Many (as one nurse can have many time deductions) (each salary maps to one nurse only)
```

```
nurses and cutoffs are related via nurses and nurse_time_deductions.

The relationship between them is One to Many (as one nurse can have many time deductions) (each salary deduction maps to one nurse only)
```
---
#### Items and Wards

```
items and wards are related via the items_in_wards table.

it is a many to many relationship as one item can be in many wards and many wards can have that item at the same time (tho not more than the quantity allows)
```
---
#### Medication and Inventory

```
The medication names are stored in medication_name table
which are then related to inventory by the medication_inventory table

It is a one to many relationship, as one medication can have multiple inventory records, i.e with different forms or potencies, but each of those records only point to one medication.
```

# Security Rules
## Row Level Security (RLS) — Design & Policy Guide

---

## Overview

This section defines the **Row Level Security (RLS)** policies used in the clinic database system.

The goal of RLS in this project is simple:

* enforce strict data isolation
* ensure role-based access control at the database level
* prevent unauthorized reads/writes even if the API layer is compromised
* keep logic close to the data, not scattered in application code

All policies are written assuming **Supabase Auth (`auth.uid()`)** as the identity provider.

---

## Core Philosophy

This system follows a few strong principles:

### 1. Ownership First

Every user can fully manage their own data:

* profiles
* role-specific tables (patients, doctors, nurses, etc.)

---

### 2. Role-Based Authority

Access beyond personal data is granted strictly through roles:

| Role               | Power                               |
| ------------------ | ----------------------------------- |
| `db_admin`         | full system control                 |
| `management_staff` | operational control                 |
| `doctor`           | patient + appointment scoped access |
| `nurse`            | ward-scoped visibility              |
| `pharmacist`       | medication control                  |
| `patient`          | self + related data only            |

---

### 3. Relationship-Based Access

Instead of broad permissions, access is granted via relationships:

* doctors → only their patients (via appointments)
* patients → only their wards, prescriptions, bills
* nurses → only patients in their assigned wards

---

### 4. Deny by Default

If no policy allows access → access is denied.

No exceptions. No silent fallbacks.

---

## Policy Structure

Policies are grouped logically by domain:

---

## Profiles & Identity

### Self Management

Users can fully control their own profile and role-specific records:

* `profiles`
* `patients`
* `doctors`
* `nurses`
* `pharmacists`

Enforced via:

```sql
id = auth.uid()
```

---

## Admin Controls

Admins (`db_admins`) have elevated privileges:

* manage `user_roles`
* manage `management_staff`
* view session roles (`active_users_role`)
* manage their own admin profile

This makes them the root authority inside the system.

---

## Management Staff

Management staff act as operational controll (which include db_admins, and doctors and hospital managers, so I wanted to give a collective access to all of them):

* manage:
  * `allowed_dosage_units`
  * `emergency_patients_contact`
  * `audit_logs`
* view:

  * medication inventory
  * medication names

They bridge the gap between admins and medical staff.

---

## Pharmacists

Pharmacists have exclusive write control over:

* `medication_name`
* `medication_inventory`

They can:

* insert
* update
* delete
* view

Managers only get read access, not control.

---

## Doctors

Doctors operate strictly within appointment boundaries.

### They can:

#### Patients

* view patients they have appointments with
* update patient medical data only if an appointment exists

#### Appointments

* view their own appointments

#### Billing

* view billing tied to their appointments

#### Prescriptions

* create/update prescriptions linked to their appointments

#### Schedule

* view their own schedule

---

## Patients

Patients are heavily restricted to self-scope + derived relationships.

### They can:

#### Appointments

* view their own appointments

#### Billing

* view their own bills

#### Prescriptions

* view prescriptions from their appointments

#### Wards

* view:

  * their current ward
  * nurses assigned to that ward

---

## Nurses

Nurses operate within ward assignments.

### They can:

* view:

  * patients in their wards
  * items assigned to wards
* view:

  * their salary
  * time deductions

---

## Wards & Inventory

### Items

* nurses & doctors can view available items (`item_store_room`)
* nurses can view ward-level item distribution

### Assignment Logic

All access is controlled via:

* `items_in_wards`
* `patients_in_wards`
* `nurses_in_wards`

---

## Audit Logs

Two-layer control:

| Action       | Who                    |
| ------------ | ---------------------- |
| Insert logs  | Any authenticated user |
| Full control | Management staff       |

This ensures:

* system activity is always recorded
* but only trusted roles can modify logs

---

## Dosage Units

* readable by all authenticated users
* modifiable only by management staff

---

## Security Patterns Used

### EXISTS Based Authorization

Most policies use:

```sql
EXISTS (SELECT 1 FROM <table> WHERE id = auth.uid())
```

* Fast
* Clean
* Index-friendly

---

### Relationship Enforcement

Access is granted via joins like:

* `appointments`
* `patients_in_wards`
* `nurses_in_wards`

This ensures:

* no global visibility leaks
* strict contextual access

---

### UNION in Policies

Used where multiple roles share authority, (to support the index) e.g.:

* patient + management staff for emergency contacts

---

## Important Notes

* RLS assumes `auth.uid()` is always trusted
* No policy = no access
* Insert operations rely on implicit `WITH CHECK` unless specified
* Complex joins have indexing for performance.

---

(Formatting and Writing from ChatGPT 5.4 Mini Thinking on RLS document section).


Most Queries have indexes, the functions and views will be explained in `ForFrontendEngineers.md` file.

---

# IMPORTANT 
## Limitations:
- Doctors cannot have overnight shifts (to prevent overlapping errors).

- No implementation of parition on any tables, if a table exceeds more than 10 million rows and has alot of reads per second, it might struggle.

---
