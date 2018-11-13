-- Creates the test_app user and grants access to the public schema

CREATE USER test_app PASSWORD 'SUPERSECRETPASSWORD';
GRANT ALL ON SCHEMA public to test_app;
