/*
  Portfolio 5: availability group step 5 (run on sql2)
*/
USE master;
ALTER AVAILABILITY GROUP ag_lasuth JOIN WITH (CLUSTER_TYPE = NONE);
ALTER AVAILABILITY GROUP ag_lasuth GRANT CREATE ANY DATABASE;
GO
