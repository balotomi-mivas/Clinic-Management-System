/*
  LASUTH Clinic Management System
  File: 00_create_database.sql
  Run once as a superuser before 01_schema.sql.
*/
DROP DATABASE IF EXISTS lasuth;
CREATE DATABASE lasuth;
/* Lagos is UTC+1 with no daylight saving; every timestamp displays in local time. */
ALTER DATABASE lasuth SET timezone TO 'Africa/Lagos';
ALTER DATABASE lasuth SET search_path TO clinic, public;
