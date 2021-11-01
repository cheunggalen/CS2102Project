DROP TABLE IF EXISTS Employees, Contacts, Juniors, Seniors, Bookers, Managers, Sessions, 
Departments, Meeting_Rooms, Updates, Approves, Joins, Health_Declarations, Check_Fever CASCADE;

CREATE TABLE Departments (
    did INTEGER PRIMARY KEY,
    dname TEXT
);

CREATE TABLE Employees (
    eid INTEGER PRIMARY KEY,
    ename TEXT,
    email TEXT UNIQUE,
    resigned_date DATE,
    did INTEGER NOT NULL,
    contact INTEGER,
    home_contact INTEGER,
    office_contact INTEGER,
    FOREIGN KEY (did) REFERENCES Departments(did) ON UPDATE CASCADE
    -- ON DELETE NO ACTION since departments with employees cannot be deleted
);

CREATE TABLE Juniors (
    eid INTEGER PRIMARY KEY,
    FOREIGN KEY (eid) REFERENCES Employees(eid) ON UPDATE CASCADE
);

CREATE TABLE Bookers (
    eid INTEGER PRIMARY KEY,
    FOREIGN KEY (eid) REFERENCES Employees(eid) ON UPDATE CASCADE
);

CREATE TABLE Seniors (
    eid INTEGER PRIMARY KEY,
    FOREIGN KEY (eid) REFERENCES Employees(eid) ON UPDATE CASCADE,
    FOREIGN KEY (eid) REFERENCES Bookers(eid) 
);

CREATE TABLE Managers (
    eid INTEGER PRIMARY KEY,
    FOREIGN KEY (eid) REFERENCES Employees(eid) ON UPDATE CASCADE,
    FOREIGN KEY (eid) REFERENCES Bookers(eid) 
);

CREATE TABLE Meeting_Rooms (
    room    INTEGER,
    floor   INTEGER,
    rname   TEXT,
    did     INTEGER NOT NULL,
    PRIMARY KEY (room, floor),
    FOREIGN KEY (did) REFERENCES Departments (did) ON UPDATE CASCADE
    -- ON DELETE NO ACTION since departments with meeting rooms cannot be deleted
);

CREATE TABLE Updates(
    date    DATE,
    new_cap INTEGER,
    room    INTEGER,
    floor   INTEGER,
    PRIMARY KEY(date, room, floor),
    FOREIGN KEY (room, floor) REFERENCES Meeting_rooms (room, floor) 
    ON DELETE CASCADE -- ON UPDATES NO ACTION
);

CREATE TABLE Sessions (
    time    INTEGER,
    date    DATE,
    room    INTEGER,
    floor   INTEGER,
    eid     INTEGER NOT NULL,
    PRIMARY KEY (time, date, room, floor),
    FOREIGN KEY (room, floor) REFERENCES Meeting_Rooms (room, floor)
    ON DELETE CASCADE, -- ON UPDATES NO ACTION
    FOREIGN KEY (eid) REFERENCES Bookers (eid)
    ON UPDATE CASCADE,
    CHECK (time >= 0 AND time < 2400)
);

CREATE TABLE Approves (
    time    INTEGER,
    date    DATE,
    room    INTEGER,
    floor   INTEGER,
    eid     INTEGER,
    PRIMARY KEY (time, date, room, floor),
    FOREIGN KEY (time, date, room, floor) REFERENCES Sessions (time, date, room, floor) 
    ON DELETE CASCADE,
    FOREIGN KEY (eid) REFERENCES Managers (eid)
    ON UPDATE CASCADE,
    CHECK (time >= 0 AND time < 2400)
);

CREATE TABLE Joins (
    time    INTEGER,
    date    DATE,
    room    INTEGER,
    floor   INTEGER,
    eid     INTEGER,
    PRIMARY KEY (time, date, room, floor, eid),
    FOREIGN KEY (time, date, room, floor) REFERENCES Sessions(time, date, room, floor)
    ON DELETE CASCADE,
    FOREIGN KEY (eid) REFERENCES Employees (eid)
    ON UPDATE CASCADE,
    CHECK (time >= 0 AND time < 2400)
);

-- this table is to ensure 3NF normalization
CREATE TABLE Check_Fever (
    temp FLOAT PRIMARY KEY,
    fever INTEGER DEFAULT 0, -- 1 is fever
    CHECK (temp > 34 and temp < 43)
);

CREATE TABLE Health_Declarations (
    date    DATE,
    temp    FLOAT,
    eid     INTEGER,
    PRIMARY KEY (date, eid),
    FOREIGN KEY (eid) REFERENCES Employees(eid) ON UPDATE CASCADE,
    FOREIGN KEY (temp) REFERENCES check_fever(temp),
    CHECK (temp > 34 and temp < 43)
);





CREATE OR REPLACE FUNCTION check_approves()
RETURNS TRIGGER AS $$
DECLARE
    m_department_id INTEGER; -- manager
    s_department_id INTEGER; -- session

BEGIN
    
    select COALESCE(e.did,-1) into m_department_id 
    from Employees e, Managers m
    where e.eid = m.eid AND NEW.eid = m.eid;

    select COALESCE(mr.did, -1) into s_department_id
    from Meeting_Rooms mr
    where mr.room = NEW.room AND mr.floor = NEW.floor;

    if m_department_id < 0 OR s_department_id < 0 or m_department_id <> s_department_id then
        RAISE NOTICE "The manager doesn't come from the same dep as the meeting room";
        return NULL;
    else
        return NEW;
    end if;

END;
$$LANGUAGE plpgsql;

CREATE TRIGGER approves_check
BEFORE INSERT OR UPDATE ON Approves
FOR EACH ROW 
EXECUTE FUNCTION check_approves();


