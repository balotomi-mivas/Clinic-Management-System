/*
  LASUTH Clinic Management System
  File: 00_create_database.sql
  
*/
DROP DATABASE IF EXISTS lasuth;
CREATE DATABASE lasuth;

ALTER DATABASE lasuth SET search_path TO clinic, public;
