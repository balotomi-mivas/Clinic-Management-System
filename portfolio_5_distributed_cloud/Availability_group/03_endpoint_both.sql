/*
  Portfolio 5: availability group step 3 (run on sql1 AND sql2)
*/
USE master;
IF NOT EXISTS (SELECT 1 FROM sys.database_mirroring_endpoints WHERE name = 'hadr_endpoint')
    CREATE ENDPOINT hadr_endpoint
        STATE = STARTED
        AS TCP (LISTENER_PORT = 5022)
        FOR DATABASE_MIRRORING (ROLE = ALL, AUTHENTICATION = CERTIFICATE ag_lasuth_cert,
                                ENCRYPTION = REQUIRED ALGORITHM AES);
ALTER EVENT SESSION AlwaysOn_health ON SERVER WITH (STARTUP_STATE = ON);
SELECT @@SERVERNAME AS replica, name, state_desc, role_desc FROM sys.database_mirroring_endpoints;
GO
