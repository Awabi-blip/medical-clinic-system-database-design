CREATE VIEW view_doctor_specialization
WITH (security_invoker = true) AS
SELECT CONCAT(profiles.first_name, ' ', profiles.last_name) AS "name", doctors.education, 
doctors.specialization 
FROM doctors
JOIN profiles ON doctors.id = profiles.id;

CREATE VIEW view_doctor_schedule
WITH (security_invoker = true) AS
SELECT "day", shift_start, 
       shift_end, hourly_rate
FROM doctor_schedule;


CREATE OR REPLACE FUNCTION get_doctor_schedule(f_doctor_id UUID)
RETURNS TABLE (
    appointments_date DATE,
    appointments_time TIME,
    duration_hours DECIMAL(2,1)
)
SECURITY DEFINER
AS $$
DECLARE
    v_patient_id UUID;
BEGIN
    v_patient_id := auth.uid();

    IF NOT EXISTS (SELECT 1 FROM patients WHERE id = v_patient_id) THEN
        RAISE EXCEPTION 'Patient not found or not authorized';
    END IF; 
    
    RETURN QUERY
    SELECT 
        appointments.scheduled_at::DATE, 
        appointments.scheduled_at::TIME, 
        appointments.duration_hours
    FROM appointments
    WHERE appointments.doctor_id = f_doctor_id
      AND appointments.status = 'scheduled';
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION add_appointment(
    f_doctor_id UUID,
    f_date DATE, 
    f_time TIME, 
    f_duration_hours DECIMAL(2,1)
)
RETURNS BIGINT
SECURITY DEFINER
AS $$
DECLARE 
    v_doctor_shift_start TIME;
    v_doctor_shift_end TIME;
    v_appointment_day working_days;
    v_patient_id UUID;
    v_appointment_id BIGINT;
    v_count_unpaid_appointments SMALLINT;
    v_count_scheduled_appointments SMALLINT;
    v_scheduled_at TIMESTAMPTZ;
BEGIN
    v_patient_id := auth.uid();
    
    IF NOT EXISTS (SELECT 1 FROM patients WHERE id = v_patient_id) THEN
        RAISE EXCEPTION 'Patient not found or not authorized';
    END IF; 
    
    SELECT COUNT(1) INTO v_count_scheduled_appointments
    FROM appointments
    WHERE patient_id = v_patient_id
    AND "status" = 'scheduled';

    IF v_count_scheduled_appointments > 4 THEN
        RAISE EXCEPTION 'too many assignments already due wait it out';
    END IF;

    SELECT COUNT(1) INTO v_count_unpaid_appointments
    FROM appointments
    JOIN appointments_billing ON appointments.id = appointments_billing.appointment_id
    WHERE appointments.patient_id = v_patient_id
    AND appointments_billing.paid = FALSE;
    
    IF v_count_unpaid_appointments > 3 THEN 
        RAISE EXCEPTION 'clear your dues';
    END IF;
    
    v_appointment_day := to_char(f_date, 'FMDay')::working_days;
    
    IF v_appointment_day NOT IN (
        SELECT "day" FROM doctor_schedule 
        WHERE doctor_id = f_doctor_id
    ) THEN
        RAISE EXCEPTION 'doctor is not available on the day';
    END IF;

    SELECT shift_start, shift_end 
    INTO v_doctor_shift_start, v_doctor_shift_end
    FROM doctor_schedule
    WHERE doctor_id = f_doctor_id 
    AND "day" = v_appointment_day;

    IF f_time NOT BETWEEN v_doctor_shift_start AND v_doctor_shift_end THEN
        RAISE EXCEPTION 'doctor not available on the day at that time';
    END IF;

    IF (f_time + (f_duration_hours * INTERVAL '1 hour') > v_doctor_shift_end) THEN
        RAISE EXCEPTION 'appointment would end after doctor shift';
    END IF;
    
    v_scheduled_at := (f_date + f_time)::TIMESTAMPTZ;

    IF EXISTS (
        SELECT 1 
        FROM appointments
        WHERE doctor_id = f_doctor_id 
        AND "scheduled_at" = v_scheduled_at
        AND "status" != 'completed'
    ) THEN
        RAISE EXCEPTION 'doctor either booked from before or done with the appointment';
    END IF;
    
    IF EXISTS (
        SELECT 1
        FROM appointments
        WHERE doctor_id = f_doctor_id
        AND (v_scheduled_at, (v_scheduled_at + f_duration_hours * INTERVAL '1 hour')) 
        OVERLAPS 
        (scheduled_at, (scheduled_at + duration_hours * INTERVAL '1 hour'))
        AND "status" NOT IN ('completed', 'cancelled')
    ) THEN
        RAISE EXCEPTION 'time overlapping';
    END IF;
    
    INSERT INTO appointments 
        (doctor_id, patient_id, scheduled_at, "duration_hours")
    VALUES 
        (f_doctor_id, v_patient_id, v_scheduled_at, f_duration_hours)
    RETURNING id INTO v_appointment_id;
    
    INSERT INTO audit_logs ("action", person_id, table_name, pk)
    VALUES ('patient booked an appointment', v_patient_id, 'appointments', v_appointment_id);

    RETURN v_appointment_id;
END;
$$ LANGUAGE plpgsql;


CREATE VIEW view_all_appointments_patients
WITH (security_invoker = true) AS
    SELECT
        appointments.id AS "appointment_id",
        CONCAT(profiles.first_name, ' ', profiles.last_name) AS "doctor",
        doctors.specialization AS "specialization",
        appointments.scheduled_at::DATE AS "date",
        appointments.scheduled_at::TIME AS "time",
        appointments.duration_hours AS "duration"
    FROM appointments
    JOIN doctors ON appointments.doctor_id = doctors.id
    JOIN profiles ON doctors.id = profiles.id;


CREATE OR REPLACE FUNCTION cancel_appointment_patient(
    f_appointment_id BIGINT
)
RETURNS VOID 
SECURITY DEFINER
AS $$
DECLARE
    v_patient_id UUID;
    v_status appointment_status;
    v_scheduled_at TIMESTAMPTZ;
BEGIN
    v_patient_id := auth.uid();

    IF NOT EXISTS (SELECT 1 FROM patients WHERE id = v_patient_id) THEN
        RAISE EXCEPTION 'patient not found or not authorized';
    END IF; 
    
    SELECT "status", scheduled_at INTO v_status, v_scheduled_at
    FROM appointments 
    WHERE id = f_appointment_id AND patient_id = v_patient_id;
    
    IF NOT FOUND 
        THEN
            RAISE EXCEPTION 'appointment not found or does not exist';
    END IF;

    IF v_status != 'scheduled'
        THEN
            RAISE EXCEPTION 'appointment either on_going, completed or cancelled';
    END IF;

    IF v_scheduled_at <= now()
        THEN
            RAISE EXCEPTION 'why are you trying to cancel an appointment that is about to happen or has happened?';
    END IF;

    UPDATE appointments
    SET "status" = 'cancelled'
    WHERE id = f_appointment_id;

    INSERT INTO audit_logs ("action", person_id, table_name, pk)
    VALUES ('patient deleted an appointment', v_patient_id, 'appointments', f_appointment_id);
END;
$$ LANGUAGE plpgsql;


CREATE VIEW view_bills_patients
WITH (security_invoker = true) AS
    SELECT 
        appointments.id AS "appointment_id",
        CONCAT(profiles.first_name, ' ', profiles.last_name) AS "doctor",
        appointments.scheduled_at::DATE AS "date_held", 
        appointments.id AS "billing_id",
        appointments_billing.total_bill AS "total_bill"
    FROM appointments 
    JOIN appointments_billing ON appointments.id = appointments_billing.appointment_id
    JOIN doctors ON doctors.id = appointments.doctor_id
    JOIN profiles ON doctors.id = profiles.id
    WHERE appointments_billing.paid = FALSE;


-- use this for cash/card/aid based, not for online transactions
CREATE OR REPLACE FUNCTION pay_for_appointments_in_house(
    f_patient_id UUID,
    f_appointment_id BIGINT, 
    f_method payment_method,
    f_paid_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID 
SECURITY DEFINER
AS $$
DECLARE
    v_manager_id UUID;
    v_status appointment_status;
BEGIN
    v_manager_id := auth.uid();
    
    IF NOT EXISTS (SELECT 1 FROM management_staff WHERE id = v_manager_id) THEN
        RAISE EXCEPTION 'manager not found or not authorized';
    END IF;

    IF f_method = 'stripe' THEN
        RAISE EXCEPTION 'we cant ensure concurrency through this function';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM patients WHERE id = f_patient_id) THEN
        RAISE EXCEPTION 'patient not found or not authorized';
    END IF; 

    SELECT "status"
    INTO v_status 
    FROM appointments 
    WHERE id = f_appointment_id
    AND patient_id = f_patient_id 
    FOR UPDATE;

    IF NOT FOUND
        THEN
            RAISE EXCEPTION 'appointment not found or not patients';
    END IF;

    IF v_status != 'completed' THEN
        RAISE EXCEPTION 'appointment is not completed yet';
    END IF;

    IF EXISTS (SELECT 1 FROM appointments_billing 
        WHERE appointment_id = f_appointment_id
        AND paid = TRUE) THEN
        RAISE EXCEPTION 'no double payments';
    END IF;

    IF f_paid_at IS NULL THEN
        f_paid_at := now();
    END IF;

    UPDATE appointments_billing
    SET paid = TRUE,
        method = f_method,
        paid_at = f_paid_at
    WHERE appointment_id = f_appointment_id;

    INSERT INTO audit_logs ("action", person_id, table_name, pk)
    VALUES ('paid for appointment', f_patient_id, 'appointments_billing', f_appointment_id);
    
END;
$$ LANGUAGE plpgsql;
