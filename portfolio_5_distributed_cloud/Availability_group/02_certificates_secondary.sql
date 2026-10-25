/*
  Portfolio 5: availability group step 2 (run on sql2): import the same certificate
*/
USE master;
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$(CERT_PASSWORD)';
IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'ag_lasuth_cert')
    CREATE CERTIFICATE ag_lasuth_cert
        FROM FILE = '/shared/ag_lasuth_cert.cer'
        WITH PRIVATE KEY (FILE = '/shared/ag_lasuth_cert.pvk', DECRYPTION BY PASSWORD = '$(CERT_PASSWORD)');
GO
