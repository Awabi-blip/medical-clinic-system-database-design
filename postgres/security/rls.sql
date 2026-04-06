ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE active_users_role ENABLE ROW LEVEL SECURITY;
ALTER TABLE management_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE emergency_patients_contact ENABLE ROW LEVEL SECURITY;
ALTER TABLE db_admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE hospital_managers ENABLE ROW LEVEL SECURITY;
ALTER TABLE item_store_room ENABLE ROW LEVEL SECURITY;


ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE doctors ENABLE ROW LEVEL SECURITY;
ALTER TABLE nurses ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacists ENABLE ROW LEVEL SECURITY;

ALTER TABLE medication_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE medication_name ENABLE ROW LEVEL SECURITY;

ALTER TABLE wards ENABLE ROW LEVEL SECURITY;
ALTER TABLE items_in_wards ENABLE ROW LEVEL SECURITY;
ALTER TABLE patients_in_wards ENABLE ROW LEVEL SECURITY;
ALTER TABLE nurses_in_wards ENABLE ROW LEVEL SECURITY;

ALTER TABLE doctor_schedule ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE prescriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointments_billing ENABLE ROW LEVEL SECURITY;


ALTER TABLE workers_salary ENABLE ROW LEVEL SECURITY;
ALTER TABLE workers_time_deductions ENABLE ROW LEVEL SECURITY;


ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

ALTER TABLE allowed_dosage_units ENABLE ROW LEVEL SECURITY;

/*"""                       ALL PROFILES
============================================================================================================================================================
============================================================================================================================================================
============================================================================================================================================================

"""*/


--new
CREATE POLICY everyone_see_allowed_dosage_units ON allowed_dosage_units
FOR SELECT TO authenticated
USING(
    EXISTS (SELECT 1 FROM profiles WHERE id = (select auth.uid()))
);

CREATE POLICY management_staff_manage_allowed_dosage_units ON 
allowed_dosage_units FOR ALL TO authenticated
USING (
    EXISTS (SELECT 1 FROM management_staff WHERE id = (select auth.uid()))
);


CREATE POLICY management_staff_manage_patients_emergency_contact
ON emergency_patients_contact FOR ALL TO authenticated 
USING (
  EXISTS (
    SELECT 1 FROM management_staff WHERE id = (select auth.uid())
    UNION 
    SELECT 1 FROM patients WHERE id = (select auth.uid())
    )
);

CREATE POLICY admins_manage_their_profile
ON db_admins FOR ALL TO authenticated
USING (id = (select auth.uid()));

CREATE POLICY admins_manage_their_profile
ON hospital_managers FOR ALL TO authenticated
USING (id = (select auth.uid()));

CREATE POLICY nurses_or_doctors_view_items ON   
item_store_room  FOR ALL TO authenticated USING (
  EXISTS (SELECT 1 FROM nurses WHERE id = (select auth.uid())
      UNION SELECT 1 FROM doctors WHERE id = (select auth.uid())
  )
);
/*"""                 ENTITIES MANAGE THEIR PROFILES
============================================================================================================================================================
============================================================================================================================================================
============================================================================================================================================================

"""*/

CREATE POLICY admins_read_session_policies
ON active_users_role FOR SELECT TO authenticated
USING(
    EXISTS (SELECT 1 FROM db_admins WHERE id = (select auth.uid()))
);

CREATE POLICY admins_manage_management_staff
ON management_staff FOR ALL TO authenticated
USING (
    EXISTS (SELECT 1 FROM db_admins WHERE id = (select auth.uid()))
);

CREATE POLICY admins_assign_roles
ON user_roles FOR ALL TO authenticated
USING (
    EXISTS (SELECT 1 FROM db_admins WHERE id = (select auth.uid()))
);


CREATE POLICY everyone_manage_their_own_profile
ON profiles FOR ALL TO authenticated 
USING ( -- used for SELECT DELETE UPDATE copied for insert if not written: with check
    id = (select auth.uid())
);

CREATE POLICY patients_manage_their_profile
ON patients FOR ALL TO authenticated
USING (id = (select auth.uid()));

CREATE POLICY doctors_manage_their_profile
ON doctors FOR ALL TO authenticated
USING (id = (select auth.uid()));

CREATE POLICY nurses_manage_their_profile
ON nurses FOR ALL TO authenticated
USING (id = (select auth.uid()));

CREATE POLICY pharmacists_manage_their_profile
ON pharmacists FOR ALL TO authenticated
USING (id = (select auth.uid()));


/*"""                       MEDICATION INVENTORY
============================================================================================================================================================
============================================================================================================================================================
============================================================================================================================================================

"""*/

CREATE POLICY pharmacist_control_medication_names
ON medication_name
FOR ALL
TO authenticated
USING (
    EXISTS ( -- used for SELECT, UPDATE. DELETE
       SELECT 1 FROM pharmacists WHERE id = (select auth.uid())
    )
);

CREATE POLICY pharmacist_control_inventory
ON medication_inventory
FOR ALL
TO authenticated
USING (
    EXISTS ( -- used for SELECT, UPDATE. DELETE
       SELECT 1 FROM pharmacists WHERE id = (select auth.uid())
    )
);

CREATE POLICY managers_view_medication_inventory 
ON medication_inventory
FOR SELECT 
USING ( -- using here only used for select
    EXISTS (
        SELECT 1 FROM management_staff WHERE id = (select auth.uid())
    )
);

CREATE POLICY managers_view_medication_names
ON medication_name
FOR SELECT 
USING ( -- using here only used for select
    EXISTS (
        SELECT 1 FROM management_staff WHERE id = (select auth.uid())
    )
);

/*"""                         WARD ITEMS
============================================================================================================================================================
============================================================================================================================================================
============================================================================================================================================================

"""*/

CREATE POLICY nurses_view_items_in_wards  ON 
items_in_wards FOR SELECT TO authenticated USING (
    EXISTS (
        SELECT 1 FROM nurses WHERE id = (select auth.uid())
    )
);

CREATE POLICY doctors_view_items_in_wards ON 
items_in_wards FOR SELECT TO authenticated USING (
    EXISTS (
        SELECT 1 FROM doctors WHERE id = (select auth.uid())
    )
);


/*"""                             AUDIT LOGS
============================================================================================================================================================
============================================================================================================================================================
============================================================================================================================================================

"""*/

CREATE POLICY management_control_audit_logs ON
audit_logs FOR ALL TO authenticated USING(
    EXISTS (
        SELECT 1 FROM management_staff WHERE id =
        (select auth.uid())
    )
);

CREATE POLICY all_insert_audit_logs ON 
audit_logs FOR INSERT TO authenticated WITH CHECK (
    EXISTS (
        SELECT 1 FROM profiles WHERE id = (select auth.uid()) -- can use auth.users too
    )
);


/*"""                             DOCTORS
============================================================================================================================================================
============================================================================================================================================================
============================================================================================================================================================

"""*/

        
/*"""                         DOCTORS AND PATIENTS
============================================================================================================================================================
============================================================================================================================================================
============================================================================================================================================================

"""*/


CREATE POLICY doctors_add_data_to_patients
ON patients 
FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM
        appointments
        WHERE appointments.patient_id = patients.id
        AND appointments.doctor_id = (select auth.uid())
        )
);

CREATE POLICY doctors_view_their_patients 
ON patients
FOR SELECT 
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM appointments WHERE appointments.doctor_id = (select auth.uid())
        AND appointments.patient_id = patients.id
    )
);

CREATE POLICY doctors_view_their_patients2
ON profiles 
FOR SELECT 
TO authenticated
USING (
    EXISTS (SELECT 1 FROM appointments WHERE appointments.doctor_id = (select auth.uid())
            AND appointments.patient_id = profiles.id
            )
);

/*"""                      DOCTORS AND APPOINTMENTS
============================================================================================================================================================
============================================================================================================================================================
============================================================================================================================================================

"""*/

CREATE POLICY doctors_view_their_appointments
ON appointments FOR SELECT TO authenticated 
USING (doctor_id = (select auth.uid()));


/*"""                       DOCTORS AND BILLINGS
============================================================================================================================================================
============================================================================================================================================================
============================================================================================================================================================

"""*/

CREATE POLICY doctors_view_their_bills 
ON appointments_billing FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM appointments WHERE
        appointments.id = appointments_billing.appointment_id AND
        appointments.doctor_id = (select auth.uid())
        )
);

/*"""                      DOCTORS AND SCHEDULING
============================================================================================================================================================
============================================================================================================================================================
============================================================================================================================================================

"""*/



CREATE POLICY doctors_view_their_schedule
ON doctor_schedule FOR SELECT TO authenticated
USING (doctor_id = (select auth.uid()));

/*"""                      DOCTORS AND PRESCRIPTIONS
============================================================================================================================================================
============================================================================================================================================================
============================================================================================================================================================

"""*/

CREATE POLICY doctors_add_prescriptions 
ON prescriptions FOR ALL TO authenticated USING (
    EXISTS (
        SELECT 1 FROM appointments 
        WHERE appointments.id = prescriptions.appointment_id
        AND appointments.doctor_id = (select auth.uid())
    )
);

/*"""                            PATIENTS
============================================================================================================================================================
============================================================================================================================================================
============================================================================================================================================================

"""*/

/*"""                       PATIENTS AND APPOINTMENTS
============================================================================================================================================================
============================================================================================================================================================
============================================================================================================================================================

"""*/

CREATE POLICY patients_view_their_appointments
ON appointments FOR SELECT TO authenticated 
USING (patient_id = (select auth.uid()));


/*"""                        PATIENTS AND BILLINGS
============================================================================================================================================================
============================================================================================================================================================
============================================================================================================================================================

"""*/

CREATE POLICY patients_view_their_bills
ON appointments_billing FOR SELECT TO authenticated 
USING (
    EXISTS (
        SELECT 1 FROM appointments WHERE 
        appointments.id = appointments_billing.appointment_id
        AND 
        appointments.patient_id = (select auth.uid())
    )
);

/*"""                        PATIENT WARDS AND NURSES 
============================================================================================================================================================
============================================================================================================================================================
============================================================================================================================================================

"""*/

CREATE POLICY patients_view_their_ward_nurses 
ON nurses FOR SELECT TO authenticated USING (
    EXISTS (
        SELECT 1 FROM 
        nurses_in_wards
        JOIN
        patients_in_wards 
        ON 
        nurses_in_wards.ward_name = patients_in_wards.ward_name
        WHERE nurses_in_wards.discharged_at IS NULL 
        AND patients_in_wards.discharged_at IS NULL 
        AND nurses_in_wards.nurse_id = nurses.id
        AND patients_in_wards.patient_id = (select auth.uid())
    )
);

CREATE POLICY patients_view_their_ward ON 
wards FOR SELECT TO authenticated USING (
    EXISTS (
        SELECT 1 FROM patients_in_wards
        WHERE wards.name = patients_in_wards.ward_name
        AND patients_in_wards.patient_id = (select auth.uid())
        AND discharged_at IS NULL
    )
);


/*"""                        PATIENT AND PRESCRIPTIONS 
============================================================================================================================================================
============================================================================================================================================================
============================================================================================================================================================

"""*/

CREATE POLICY patients_view_their_prescriptions ON 
prescriptions FOR SELECT TO authenticated USING (
    EXISTS (
        SELECT 1 FROM appointments WHERE 
        appointments.id = prescriptions.appointment_id
        AND 
        appointments.patient_id = (select auth.uid())
    )
);


/*"""                            NURSES 
============================================================================================================================================================
============================================================================================================================================================
============================================================================================================================================================

"""*/


/*"""                         Workers SALARY
============================================================================================================================================================
============================================================================================================================================================
============================================================================================================================================================

"""*/

CREATE POLICY management_staff_manage_workers_salary
ON workers_salary FOR ALL TO authenticated USING 
(
    EXISTS (SELECT 1 FROM management_staff WHERE id = (select auth.uid()))
);
    

CREATE POLICY workers_see_their_salary 
ON workers_salary FOR SELECT TO authenticated USING (
    worker_id = (select auth.uid())
);


/*"""                         Workers TIME DEDUCTION
============================================================================================================================================================
============================================================================================================================================================
============================================================================================================================================================

"""*/
CREATE POLICY management_staff_manage_workers_time_deductions
ON workers_time_deductions FOR ALL TO authenticated USING 
(
    EXISTS (SELECT 1 FROM management_staff WHERE id = (select auth.uid()))
);


CREATE POLICY workers_see_their_deductions 
ON workers_time_deductions FOR SELECT TO authenticated 
USING (
    nurse_id = (select auth.uid())
);

/*"""                        NURSES AND THEIR WARD PATIENTS
============================================================================================================================================================
============================================================================================================================================================
============================================================================================================================================================

"""*/

CREATE POLICY nurses_view_their_ward_patients 
ON patients FOR SELECT TO authenticated USING (
    EXISTS (
        SELECT 1 FROM
        patients_in_wards 
        JOIN 
        nurses_in_wards
        ON
        patients_in_wards.ward_name = nurses_in_wards.ward_name
        WHERE patients_in_wards.discharged_at IS NULL
        AND nurses_in_wards.discharged_at IS NULL 
        AND patients_in_wards.patient_id = patients.id
        AND nurses_in_wards.nurse_id = (select auth.uid())
    )
);

