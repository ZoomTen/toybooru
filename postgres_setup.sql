-- pg_hba.conf set method to md5

Create Role toybooru With CreateDB Password 'toybooru';
Create Database toybooru_main Owner toybooru;
Create Database toybooru_session Owner toybooru;
