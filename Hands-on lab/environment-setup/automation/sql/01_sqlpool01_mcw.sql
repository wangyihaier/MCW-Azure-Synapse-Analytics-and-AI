if not exists(select * from sys.database_principals where name = 'asa.sql.workload01')
begin
    create user [asa.sql.workload01] from login [asa.sql.workload01]
end

if not exists(select * from sys.database_principals where name = 'asa.sql.workload02')
begin
    create user [asa.sql.workload02] from login [asa.sql.workload02]
end

if not exists(select * from sys.database_principals where name = 'ceo')
begin
    create user [CEO] without login;
end

execute sp_addrolemember 'db_datareader', 'asa.sql.workload01' 
execute sp_addrolemember 'db_datareader', 'asa.sql.workload02' 
execute sp_addrolemember 'db_datareader', 'CEO' 

if not exists(select * from sys.database_principals where name = 'DataAnalystMiami')
begin
    create user [DataAnalystMiami] without login;
end

if not exists(select * from sys.database_principals where name = 'DataAnalystSanDiego')
begin
    create user [DataAnalystSanDiego] without login;
end
go

if not exists(select * from sys.schemas where name='wwi_mcw')
begin
    EXEC('create schema [wwi_mcw] authorization [dbo]');
END
go
create master key;
go
create table [wwi_mcw].[Product]
(
    ProductId SMALLINT NOT NULL,
    Seasonality TINYINT NOT NULL,
    Price DECIMAL(6,2),
    Profit DECIMAL(6,2)
)
WITH
(
    DISTRIBUTION = REPLICATE
);
go