CREATE OR REPLACE FUNCTION insert_items_in_wards (
f_item_type item_type, f_ward_name ward_name, f_amount_needed INT,
f_compensation BOOLEAN)
RETURNS VOID 
SECURITY DEFINER
AS $$ 
DECLARE
    v_return_status BOOLEAN;
    v_item_amount_available INT;
    v_manager_id UUID;
    v_manager_role staff_role;
BEGIN

    v_manager_id = auth.uid();
    v_manager_role := (auth.jwt() ->> 'role_assigned')::staff_role;


    IF NOT EXISTS (
        SELECT 1 FROM management_staff WHERE id = v_manager_id
    ) THEN 
        RAISE EXCEPTION 'manager not found or authorized';
    END IF;


    SELECT amount_available, return_status  
    INTO v_item_amount_available, v_return_status
    FROM item_store_room
    WHERE item_type = f_item_type 
    FOR UPDATE;

    IF v_item_amount_available = 0
        THEN
            RAISE EXCEPTION 'item is literally at 0';
    END IF;

    IF f_amount_needed > v_item_amount_available THEN
        IF f_compensation = FALSE THEN
            RAISE EXCEPTION 'less items available than needed';
        END IF;

        RAISE NOTICE 'compensation activated, sending as many items as available.';
            
        INSERT INTO items_in_wards (item_type, ward_name, amount_used, assigned_by, assigner_role)
        VALUES (f_item_type, f_ward_name, v_item_amount_available, v_manager_id, v_manager_role);

        IF v_return_status = TRUE THEN
            UPDATE item_store_room
            SET 
            amount_available = amount_available - v_item_amount_available
            WHERE item_type = f_item_type;
        ELSE 
            UPDATE item_store_room
            SET amount_available = amount_available - v_item_amount_available,
                amount_total = amount_total - v_item_amount_available
            WHERE item_type = f_item_type;
        
        END IF;
    
    ELSE
        INSERT INTO items_in_wards (item_type, ward_name, amount_used, assigned_by, assigner_role)
        VALUES (f_item_type, f_ward_name, f_amount_needed, v_manager_id, v_manager_role);

        IF v_return_status = TRUE THEN
            UPDATE item_store_room
            SET amount_available = amount_available - f_amount_needed
            WHERE item_type = f_item_type;
        ELSE 
            UPDATE item_store_room
            SET amount_available = amount_available - f_amount_needed,
                amount_total = amount_total - f_amount_needed
            WHERE item_type = f_item_type;
        END IF;
    END IF;

END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION return_items_to_store(
    f_item_type item_type, f_amount_returned INT, f_ward_name ward_name)
RETURNS VOID AS $$
SECURITY DEFINER
DECLARE
    v_return_status BOOLEAN;
    v_manager_id UUID;
    v_amount_used INT;
BEGIN 

    IF f_amount_returned <= 0 
       THEN RAISE EXCEPTION 'cannot return negative items';
    END IF;

    v_manager_id = auth.uid();
    
    IF NOT EXISTS (SELECT 1 FROM management_staff WHERE id = v_manager_id) 
    THEN
        RAISE EXCEPTION 'manager not found or not authorized';
    END IF; 

    SELECT return_status
    INTO v_return_status
    FROM item_store_room
    WHERE item_type = f_item_type;

    IF v_return_status = FALSE THEN
        RAISE EXCEPTION 'do not return sensitive items back';
    END IF;

    SELECT amount_used
    INTO v_amount_used
        FROM items_in_wards
        WHERE ward_name = f_ward_name
        AND item_type = f_item_type
    FOR UPDATE;

    IF f_amount_returned > v_amount_used
        THEN RAISE EXCEPTION 'do not return more than you took';
    END IF;

    UPDATE item_store_room
    SET amount_available = amount_available + f_amount_returned
    WHERE item_type = f_item_type;

    UPDATE items_in_wards 
    SET amount_used = amount_used - f_amount_returned
    WHERE item_type = f_item_type
       AND ward_name = f_ward_name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION destroy_broken_asset(
    f_item_type item_type, f_amount_broken INT
)
RETURNS VOID AS $$
SECURITY DEFINER
DECLARE
v_manager_id UUID;
v_log_id INT;
BEGIN

    v_manager_id = auth.uid();
    
    IF NOT EXISTS (SELECT 1 FROM management_staff WHERE id = v_manager_id) THEN
        RAISE EXCEPTION 'manager not found or not authorized';
    END IF; 

    UPDATE item_store_room 
    SET amount_total = amount_total - f_amount_broken
    WHERE item_type = f_item_type;


    INSERT INTO "audit_logs" ("action", "happened_at", 
    "person_id", "table_name", "pk")
    VALUES (
        format('item destroyed -> %s, amount -> %s check item_store_room', f_item_type, f_amount_broken),
        now(),
        v_manager_id, 'items_in_wards', f_item_type::TEXT
    );


END;
$$ LANGUAGE plpgsql;
