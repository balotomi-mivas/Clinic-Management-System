/*
  Portfolio 5: availability group step 6 (run on sql1)
  The database needs FULL recovery and a full backup before it can join.
  Automatic seeding then streams it to sql2 over the endpoint.
*/
USE master;
ALTER DATABASE LASUTH SET RECOVERY FULL;
BACKUP DATABASE LASUTH TO DISK = '/var/opt/mssql/data/LASUTH_seed.bak' WITH INIT, COMPRESSION;
IF NOT EXISTS (SELECT 1 FROM sys.availability_databases_cluster WHERE database_name = 'LASUTH')
    ALTER AVAILABILITY GROUP ag_lasuth ADD DATABASE LASUTH;
GO
