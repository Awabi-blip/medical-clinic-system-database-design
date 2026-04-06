CREATE VIEW view_all_appointments_doctors AS
WITH (security_invoker = true) AS
    SELECT
        patients.id AS "patient_id",
        CONCAT(profiles.first_name, ' ', profiles.last_name) AS "patient",
        profiles.gender AS "gender",
        patients.allergies AS "allergies",
        patients.bloodtype AS "bloodtype",
        patients.neurotype AS "neurotype",
        patients.chronic_diseases AS "chronic_diseases",
        appointments.id AS "appointment_id",
        appointments.scheduled_at::DATE AS "date",
        appointments.scheduled_at::TIME AS "time"
    FROM
        appointments
    JOIN
        patients 
    ON 
        appointments.patient_id = patients.id
    JOIN
        profiles
    ON patients.id = profiles.id;

CREATE OR REPLACE FUNCTION cancel_appointment_doctor (
    f_appointment_id BIGINT
) RETURNS VOID 
SECURITY DEFINER
AS $$
DECLARE
    v_doctor_id UUID;
BEGIN

    v_doctor_id := auth.uid();

    IF NOT EXISTS (SELECT 1 FROM doctors WHERE id = v_doctor_id) THEN
        RAISE EXCEPTION 'doctor not found or not authorized';
    END IF; 

    IF NOT EXISTS (SELECT 1 FROM appointments WHERE id = f_appointment_id 
                   AND doctor_id = v_doctor_id
                   AND ("status" = 'scheduled' OR "status" = 'on_going')) THEN
        RAISE EXCEPTION 'appointment not found';
    END IF;        

    UPDATE appointments
    SET "status" = 'cancelled'
    WHERE id = f_appointment_id;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION start_appointment(
    f_appointment_id BIGINT
) RETURNS VOID
SECURITY DEFINER
AS $$
DECLARE 
v_doctor_id UUID;
v_scheduled_at TIMESTAMPTZ;
v_status appointment_status;
BEGIN
    v_doctor_id := auth.uid();

    IF NOT EXISTS (SELECT 1 FROM doctors WHERE id = v_doctor_id) THEN
        RAISE EXCEPTION 'doctor not found or not authorized';
    END IF; 
    
    SELECT "status", scheduled_at INTO v_status, v_scheduled_at
    FROM appointments 
    WHERE id = f_appointment_id AND doctor_id = v_doctor_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'appointment is not yours or does not exist';
    END IF; 
    
    IF v_scheduled_at > now()
    THEN
      RAISE EXCEPTION 'you are before time doctor';
    END IF;
    
    IF v_status != 'scheduled'
        THEN 
            RAISE EXCEPTION 'appointment cancelled or completed or on_going';
    END IF;

    UPDATE appointments
    SET  "status" = 'on_going'
    WHERE id = f_appointment_id;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION add_data_to_appointment(
    f_appointment_id BIGINT,
    f_note TEXT, 
    f_diagnoses TEXT
)
RETURNS VOID 
SECURITY DEFINER
AS $$   
DECLARE
    v_doctor_id UUID;
BEGIN
   
    v_doctor_id := auth.uid();
    
    IF NOT EXISTS (SELECT 1 FROM doctors WHERE id = v_doctor_id) THEN
        RAISE EXCEPTION 'doctor not found or not authorized';
    END IF; 
    
    IF NOT EXISTS (
    SELECT 1
    FROM appointments 
    WHERE id = f_appointment_id AND doctor_id = v_doctor_id
    AND (status = 'on_going' OR  status = 'completed'))
        THEN
            RAISE EXCEPTION 'appointment not found, not yours, or has not been started';
    END IF;

    UPDATE appointments
    SET note  = f_note,  diagnoses = f_diagnoses
    WHERE id = f_appointment_id;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION add_prescriptions (
    f_appointment_id BIGINT,
    prescription_data jsonb
)
RETURNS VOID 
SECURITY DEFINER
AS $$
DECLARE 
v_doctor_id UUID;
BEGIN

    v_doctor_id := auth.uid();

    IF NOT EXISTS (SELECT 1 FROM doctors 
        WHERE id = v_doctor_id) THEN
            RAISE EXCEPTION 'invalid doctor';
    END IF;

    IF NOT EXISTS (
    SELECT 1
    FROM appointments 
    WHERE id = f_appointment_id AND doctor_id = v_doctor_id
    AND (status = 'on_going' OR  status = 'completed'))
        THEN
            RAISE EXCEPTION 'appointment not found, not yours, or has not been started';
    END IF;

    INSERT INTO 
        prescriptions(appointment_id, medication, 
        potency, frequency, "start_date", duration_days)
    SELECT
         f_appointment_id, x.medication, x.potency, x.frequency, 
         x.start_date, x.duration_days
    FROM 
        jsonb_to_recordset(prescription_data)
    AS  
        x(medication TEXT, potency TEXT, frequency TEXT, 
        "start_date" DATE, duration_days INT);

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION bill_appointment(
    f_appointment_id BIGINT, f_optional_custom_time_value DECIMAL(2,1) DEFAULT NULL
)
RETURNS VOID 
SECURITY DEFINER
AS $$
DECLARE
    v_doctor_id UUID;
    v_total_bill DECIMAL(8,4);
    v_appointment_duration DECIMAL(2,1);
    v_hourly_rate DECIMAL(6,2);
    v_auth_id UUID;
    v_appointment_day working_days;
    v_status appointment_status;
BEGIN

    v_auth_id := auth.uid();

    IF NOT EXISTS  (
        SELECT 1 FROM management_staff WHERE id = v_auth_id)
    THEN 
        RAISE EXCEPTION 'manager not found';
    END IF;

    SELECT doctor_id, "day", status INTO v_doctor_id, v_appointment_day, v_status
    FROM appointments WHERE id = f_appointment_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'doctor % not found', v_doctor_id;
    END IF;

    IF v_status != 'on_going'
        THEN
            RAISE EXCEPTION 'doctor the appointment has not even been started!';
    END IF;
    
    UPDATE appointments SET "status" = 'completed'
    WHERE id = f_appointment_id;

    IF f_optional_custom_time_value IS NOT NULL THEN
        v_appointment_duration := f_optional_custom_time_value;
    
    ELSE v_appointment_duration := (SELECT duration_hours FROM appointments
                                WHERE id = f_appointment_id);
    END IF;
    
    SELECT hourly_rate INTO v_hourly_rate
    FROM doctor_schedule WHERE doctor_id = v_doctor_id
    AND "day" = v_appointment_day;
    
    v_total_bill := v_hourly_rate * v_appointment_duration * 0.90;

    INSERT INTO appointments_billing
    (appointment_id, total_bill, paid)
    VALUES
    (f_appointment_id, v_total_bill, FALSE);

END;
$$ LANGUAGE plpgsql;
