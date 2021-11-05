DROP TRIGGER IF EXISTS booker_joins ON Sessions;
DROP TRIGGER IF EXISTS temp_check_join ON Joins;
DROP TRIGGER IF EXISTS date_time_check_join ON Joins;
DROP TRIGGER IF EXISTS cap_check ON Joins;
DROP TRIGGER IF EXISTS temp_check_book ON Sessions;
DROP TRIGGER IF EXISTS date_time_check_book ON Sessions;
DROP TRIGGER IF EXISTS meeting_cancelled ON Joins;
DROP TRIGGER IF EXISTS approved_check_join ON Joins;
DROP TRIGGER IF EXISTS resignation_check ON Joins;
DROP TRIGGER IF EXISTS approved_check_book ON Sessions;
DROP TRIGGER IF EXISTS session_participation_check ON Sessions;
DROP FUNCTION IF EXISTS contact_trace(IN sick_eid INT, IN sick_date DATE);
DROP TRIGGER IF EXISTS contact_check ON Sessions;

--The employee booking the room immediately joins the booked meeting
CREATE OR REPLACE FUNCTION automatically_join()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO Joins (time, date, room, floor, b_eid, e_eid) VALUES (NEW.time, NEW.date, NEW.room, NEW.floor, NEW.b_eid, NEW.b_eid);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER join_automatically
AFTER INSERT OR UPDATE ON Sessions
FOR EACH ROW EXECUTE FUNCTION automatically_join();

--If an employee is having a fever, they cannot join a booked meeting (check the most recent temperature)
CREATE OR REPLACE FUNCTION check_temp_join()
RETURNS TRIGGER AS $$
DECLARE
    t FLOAT;
BEGIN
    SELECT temp INTO t
    FROM Health_Declarations hd
    WHERE hd.eid = NEW.e_eid;

    IF t > 37.5 THEN
        RAISE NOTICE 'Not allowed to join session as employee has fever';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER temp_check_join
BEFORE INSERT OR UPDATE ON Joins
FOR EACH ROW EXECUTE FUNCTION check_temp_join();

--An employee can only join future meetings
CREATE OR REPLACE FUNCTION check_date_time_join()
RETURNS TRIGGER AS $$
DECLARE
    date_current DATE;
BEGIN
    SELECT CURRENT_DATE INTO date_current;

    IF NEW.date < date_current THEN
        RAISE NOTICE 'Session is already over';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER date_time_check_join
BEFORE INSERT OR UPDATE ON Joins
FOR EACH ROW EXECUTE FUNCTION check_date_time_join();

--An employee can only join meetings if the number of people in the meeting is less than the most recent updated capacity
CREATE OR REPLACE FUNCTION check_cap()
RETURNS TRIGGER AS $$
DECLARE
    cap INTEGER;
    current INTEGER;
BEGIN
    SELECT u.new_cap INTO cap
    FROM Updates u
    WHERE u.room = NEW.room
    AND u.floor = NEW.floor
    AND u.date <= NEW.date;

    SELECT COUNT(*) INTO current
    FROM Joins j
    WHERE j.time = NEW.time
    AND j.date = NEW.date
    AND j.room = NEW.room
    AND j.floor = NEW.floor
    AND j.b_eid = NEW.b_eid;

    IF current >= cap THEN
        RAISE NOTICE 'Unable to join as session is full';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER cap_check
BEFORE INSERT OR UPDATE ON Joins
FOR EACH ROW EXECUTE FUNCTION check_cap();

--If an employee is having a fever, they cannot book a room (we check your most recent temperature)
CREATE OR REPLACE FUNCTION check_temp_book()
RETURNS TRIGGER AS $$
DECLARE
    tem FLOAT;
BEGIN
    SELECT temp INTO tem
    FROM Health_Declarations hd
    WHERE hd.eid = NEW.b_eid;

    IF tem > 37.5 THEN
        RAISE NOTICE 'Not allowed to book as booker has fever';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER temp_check_book
BEFORE INSERT OR UPDATE ON Sessions
FOR EACH ROW EXECUTE FUNCTION check_temp_book();

--A booking can only be made for future meetings
CREATE OR REPLACE FUNCTION check_date_time_book()
RETURNS TRIGGER AS $$
DECLARE
    date_current DATE;
BEGIN
    SELECT CURRENT_DATE INTO date_current;

    IF NEW.date < date_current THEN
        RAISE NOTICE 'Cannot book in the past';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER date_time_check_book
BEFORE INSERT OR UPDATE ON Sessions
FOR EACH ROW EXECUTE FUNCTION check_date_time_book();

--When the booker is removed from a meeting, the meeting is cancelled
CREATE OR REPLACE FUNCTION cancel_meeting()
RETURNS TRIGGER AS $$
DECLARE
    is_booker INTEGER;
BEGIN
    SELECT COUNT (*) INTO is_booker 
    FROM Bookers b
    WHERE b.eid = OLD.e_eid;

    IF is_booker > 0 THEN
        RAISE NOTICE 'A booker has been removed, the session booked by him will be cancelled';
        DELETE FROM Joins j
        WHERE j.time = OLD.time
        AND j.date = OLD.date
        AND j.room = OLD.room
        AND j.floor = OLD.floor
        AND j.b_eid = OLD.e_eid;

        DELETE FROM Sessions s
        WHERE s.time = OLD.time
        AND s.date = OLD.date
        AND s.room = OLD.room
        AND s.floor = OLD.floor
        AND s.b_eid = OLD.e_eid;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER meeting_cancelled
AFTER DELETE ON Joins
FOR EACH ROW EXECUTE FUNCTION cancel_meeting();

--No employees can join or leave from an already approved session
CREATE OR REPLACE FUNCTION check_approved_join()
RETURNS TRIGGER AS $$
DECLARE
    join_approved INTEGER;
BEGIN
    SELECT COUNT(*) INTO join_approved
    FROM Approves a
    WHERE a.time = NEW.time
    AND a.date = NEW.date
    AND a.room = NEW.room
    AND a.floor = NEW.floor
    AND a.b_eid = NEW.b_eid;

    IF join_approved > 0 THEN
        RAISE NOTICE 'Cannot join or leave approved session';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER approved_check_join
BEFORE INSERT OR UPDATE OR DELETE ON Joins
FOR EACH ROW EXECUTE FUNCTION check_approved_join();

--An employee who has resigned cannot join any sessions
CREATE OR REPLACE FUNCTION check_resignation()
RETURNS TRIGGER AS $$
DECLARE
    resign_date DATE;
BEGIN
    SELECT e.resigned_date INTO resign_date
    FROM Employees e
    WHERE e.eid = NEW.e_eid;

    IF resign_date IS NULL OR resign_date > NEW.date THEN
        RETURN NEW;
    ELSE
        RAISE NOTICE 'Not allowed to join session as employee has already resigned';
        RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER resignation_check
BEFORE INSERT OR UPDATE ON Joins
FOR EACH ROW EXECUTE FUNCTION check_resignation();

--A session can only be booked if there isn't already an approved session of the same time, date, room, and floor
CREATE OR REPLACE FUNCTION check_approved_book()
RETURNS TRIGGER AS $$
DECLARE
    same_approved INTEGER;
BEGIN
    SELECT COUNT(*) INTO same_approved
    FROM Approves a
    WHERE a.time = NEW.time
    AND a.date = NEW.date
    AND a.room = NEW.room
    AND a.floor = NEW.floor;

    IF same_approved > 0 THEN
        RAISE NOTICE 'There is already an approved session of the same time, date, room, and floor';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER approved_check_book
BEFORE INSERT OR UPDATE ON Sessions
FOR EACH ROW EXECUTE FUNCTION check_approved_book();

--Each session must exist at least once in Join
CREATE OR REPLACE FUNCTION check_session_participation()
RETURNS TRIGGER AS $$
DECLARE
    corresponding_joins INTEGER;
BEGIN
    SELECT COUNT(*) INTO corresponding_joins
    FROM Joins j
    WHERE j.time = NEW.time
    AND j.date = NEW.date
    AND j.room = NEW.room
    AND j.floor = NEW.floor
    AND j.b_eid = NEW.b_eid;

    IF corresponding_joins > 0 THEN
        RAISE NOTICE 'There are still employees involved in this session, please clear them first';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER session_participation_check
BEFORE UPDATE OR DELETE ON Sessions
FOR EACH ROW EXECUTE FUNCTION check_session_participation();

--checks if an employee has been in contact with a sick employee in the past 7 days
CREATE OR REPLACE FUNCTION sick_contacts(IN checked_eid INT, IN checked_date DATE)
RETURNS TABLE(sick_contact_id INT) AS $$
    SELECT j2.e_eid AS sick_contact_id
    FROM Joins j1, (SELECT j.time, j.date, j.room, j.floor, j.b_eid, j.e_eid, h.temp
        FROM (Joins j JOIN Health_Declarations h ON (j.e_eid = h.eid AND j.date = h.date))) j2
    WHERE j1.e_eid = checked_eid --find all sessions joined by checked employee
    AND (j1.date = checked_date --find all sessions joined by checked employee in the past 7 days
        OR j1.date = checked_date - INTERVAL '1 day' 
        OR j1.date = checked_date - INTERVAL '2 day' 
        OR j1.date = checked_date - INTERVAL '3 day'
        OR j1.date = checked_date - INTERVAL '4 day'
        OR j1.date = checked_date - INTERVAL '5 day'
        OR j1.date = checked_date - INTERVAL '6 day'
        OR j1.date = checked_date - INTERVAL '7 day')
    AND j2.time = j1.time --find all other employees who joined the same sessions as the checked employee
    AND j2.date = j1.date
    AND j2.room = j1.room
    AND j2.floor = j1.floor
    AND j2.b_eid = j1.b_eid
    AND j2.temp > 37.5; --find all sick employees who joined the same sessions as the checked employee
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION check_contact()
RETURNS TRIGGER AS $$
DECLARE
    num_of_sick_contacts INTEGER;
BEGIN
    SELECT COUNT (*) INTO num_of_sick_contacts
    FROM sick_contacts(NEW.e_eid, NEW.date);

    IF num_of_sick_contacts > 0 THEN
        RAISE NOTICE 'Not allowed to join session as employee has been in contact with a sick personel in the past 7 days';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER contact_check
BEFORE INSERT OR UPDATE ON Joins
FOR EACH ROW EXECUTE FUNCTION check_contact();
