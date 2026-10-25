/*
  Portfolio 5: availability group step 4 (run on sql1)
  CLUSTER_TYPE = NONE builds a read scale availability group that needs no
  Windows failover cluster or Pacemaker. Failover is manual, which is enough
  to demonstrate replication, synchronous commit and promotion.
*/
USE master;
IF NOT EXISTS (SELECT 1 FROM sys.availability_groups WHERE name = 'ag_lasuth')
    CREATE AVAILABILITY GROUP ag_lasuth
        WITH (CLUSTER_TYPE = NONE)
        FOR REPLICA ON
            N'sql1' WITH (ENDPOINT_URL = N'tcp://sql1:5022', AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
                          FAILOVER_MODE = MANUAL, SEEDING_MODE = AUTOMATIC,
                          SECONDARY_ROLE (ALLOW_CONNECTIONS = ALL)),
            N'sql2' WITH (ENDPOINT_URL = N'tcp://sql2:5022', AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
                          FAILOVER_MODE = MANUAL, SEEDING_MODE = AUTOMATIC,
                          SECONDARY_ROLE (ALLOW_CONNECTIONS = ALL));
ALTER AVAILABILITY GROUP ag_lasuth GRANT CREATE ANY DATABASE;
GO
