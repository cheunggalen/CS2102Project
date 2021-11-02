
-- TRIGGER FUNCTION THAT CHECKS THAT APPROVES IS FOR FUTURE MEETINGS
CREATE OR REPLACE FUNCTION approve_future()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.date < CURRENT_DATE then
        RAISE NOTICE 'Approvals must be for future dates';
        Return NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$LANGUAGE plpgsql;

CREATE TRIGGER future_approve
BEFORE INSERT OR UPDATE ON Approves
FOR EACH ROW 
EXECUTE FUNCTION approve_future();


-- TRIGGER FUNCTION THAT CHECKS THAT THE MANAGER IS FROM THE SAME DEPARTMENT AS THE MEETING ROOM
CREATE OR REPLACE FUNCTION check_manager_from_same_dep_as_mr()
RETURNS TRIGGER AS $$
DECLARE
    m_department_id INTEGER; -- manager
    target_department_id INTEGER; -- session or update

BEGIN
    
    SELECT COALESCE(e.did,-1) INTO m_department_id 
    FROM Employees e, Managers m
    WHERE e.eid = m.eid AND NEW.m_eid = m.eid;

    SELECT COALESCE(mr.did, -1) INTO target_department_id
    FROM Meeting_Rooms mr
    WHERE mr.room = NEW.room AND mr.floor = NEW.floor;

    IF  m_department_id <> target_department_id THEN
        RAISE NOTICE 'The manager doesnt come from the same dep as the meeting room';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;

END;
$$LANGUAGE plpgsql;

CREATE TRIGGER approves_check
BEFORE INSERT OR UPDATE ON Approves
FOR EACH ROW 
EXECUTE FUNCTION check_manager_from_same_dep_as_mr();

--------------------------------------------------------------------------------------------------------------------

-- Checks that the Manager adding to Updates is from the same department as the meeting room that it is updating

CREATE TRIGGER updates_check
BEFORE INSERT OR UPDATE ON Updates
FOR EACH ROW 
EXECUTE FUNCTION check_manager_from_same_dep_as_mr();

--------------------------------------------------------------------------------------------------------------------


-- FUNCTION THAT CAN FIND EVERYONE THAT IS A CLOSE CONTACT
CREATE OR REPLACE FUNCTION close_contacts(IN sick_eid INT, IN sick_date DATE)
RETURNS SETOF INT AS $$

    SELECT j2.e_eid as e_eid
    FROM Sessions s, Joins j1, Joins j2
    -- get participants of meetings
    WHERE (s.room, s.floor, s.date, s.time, s.b_eid) = (j1.room, j1.floor, j1.date, j1.time, s.b_eid)
    -- get sessions that eid was in in the past 3 days
    AND j1.e_eid = sick_eid AND (j1.date = sick_date OR j1.date = sick_date - INTERVAL '1 day' OR j1.date = sick_date - INTERVAL '2 day' OR j1.date = sick_date - INTERVAL '3 day')
    -- get close contacts;
    AND (j1.room, j1.floor, j1.date, j1.time, j1.b_eid) = (j2.room, j2.floor, j2.date, j2.time, j2.b_eid)
    
$$ LANGUAGE sql ;

-- TRIGGER FUNC TO REMOVE CLOSE CONTACTS FROM 7 DAYS OF SESSIONS
CREATE OR REPLACE FUNCTION rem_close_contacts()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.temp > 37.0 THEN
        RAISE NOTICE 'Close contacts are removed from meetings for the next 7 days';
        Delete FROM Joins j USING close_contacts(NEW.eid, NEW.date) cc 
        WHERE
            j.e_eid = cc AND
            j.date = NEW.date OR j.date = NEW.date + INTERVAL '1 day'OR
            j.date = NEW.date + INTERVAL '2 day'OR j.date = NEW.date + INTERVAL '3 day'OR
            j.date = NEW.date + INTERVAL '4 day'OR j.date = NEW.date + INTERVAL '5 day'OR
            j.date = NEW.date + INTERVAL '6 day'OR j.date = NEW.date + INTERVAL '7 day';
    END IF;
RETURN new;
END;
$$LANGUAGE plpgsql;


CREATE TRIGGER close_contact_rem
BEFORE INSERT OR UPDATE ON Health_Declarations
FOR EACH ROW 
EXECUTE FUNCTION rem_close_contacts();


--------------------------------------------------------------------------------------------------------------------

 -- TRIGGER FUNC TO REMOVE SESSIONS AND APPROVES WHICH HAVE b_eid == booker_eid
CREATE OR REPLACE FUNCTION rem_sessions() -- cascades to delete approves and Joins
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.temp > 37.0 then 
        RAISE NOTICE 'This employee has a fever, all future sessions booked by them are deleted';
        DELETE FROM Sessions s
        WHERE NEW.eid = s.b_eid AND s.date >= NEW.date;
    END IF;
RETURN new;
END;
$$LANGUAGE plpgsql;


CREATE TRIGGER session_rem
BEFORE INSERT OR UPDATE ON Health_Declarations
FOR EACH ROW 
EXECUTE FUNCTION rem_sessions();










