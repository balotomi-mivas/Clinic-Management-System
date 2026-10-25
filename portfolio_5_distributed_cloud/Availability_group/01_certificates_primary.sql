/*
  LASUTH Clinic Management System
  Portfolio 5: Always On availability group, step 1 (run on sql1)
  The containers are not in a Windows domain, so the replicas authenticate
  their endpoints with a shared certificate instead of Kerberos.
  $(CERT_PASSWORD) is supplied by run_portfolio_5.ps1 through sqlcmd -v.
*/
USE master;
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$(CERT_PASSWORD)';
IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'ag_lasuth_cert')
BEGIN
    CREATE CERTIFICATE ag_lasuth_cert WITH SUBJECT = 'LASUTH availability group endpoint';
    BACKUP CERTIFICATE ag_lasuth_cert
        TO FILE = '/shared/ag_lasuth_cert.cer'
        WITH PRIVATE KEY (FILE = '/shared/ag_lasuth_cert.pvk', ENCRYPTION BY PASSWORD = '$(CERT_PASSWORD)');
END;
GO
