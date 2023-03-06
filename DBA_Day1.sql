    DECLARE @Hostname                  varchar(50)          = (SELECT convert(varchar(50),@@SERVERNAME))

       DECLARE @VersionInfo        varchar(max)  = (SELECT convert(varchar(max),@@version))

       DECLARE @EditionInfo        varchar(50)          = (SELECT convert(varchar(50),SERVERPROPERTY('edition')))

       DECLARE @IsClustered        varchar(50)          = (SELECT CASE SERVERPROPERTY ('IsClustered') WHEN 1 THEN 'Clustered Instance' WHEN 0 THEN 'Non Clustered instance' ELSE 'null' END)

       DECLARE       @IsSingleUserMode    varchar(50)          = (SELECT CASE SERVERPROPERTY ('IsSingleUser') WHEN 1 THEN 'Single user' WHEN 0 THEN 'Multi user' ELSE 'null' END)

 

       SELECT 'ServerInfo' AS Info

       SELECT @Hostname AS HostName,@VersionInfo AS VersionInfo,@EditionInfo AS Edition,@IsClustered AS IsCluster,@IsSingleUserMode AS IsNode

 

       SELECT 'DiskSpace' AS DiskInfo

       SELECT DISTINCT Vol.logical_volume_name AS LogicalName

              ,      Vol.volume_mount_point AS Drive

              ,       CONVERT(INT,Vol.available_bytes/1024/1024/1024) AS FreeSpace

              ,   CONVERT(INT,Vol.total_bytes/1024/1024/1024) AS TotalSpace

              ,   CONVERT(INT,Vol.total_bytes/1024/1024/1024) - CONVERT(INT,Vol.available_bytes/1024/1024/1024) AS OccupiedSpace

       FROM sys.master_files MF

       CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.FILE_ID) Vol

 

       SELECT 'DB Info' AS DBInfo

       select  DB.database_id

              ,      DB.name

              ,      DB.create_date

              ,      SP.name

              ,      DB.user_access_desc

              ,      DB.state_desc

              ,      DB.compatibility_level

              ,      recovery_model_desc

              ,      Sum((MF.size*8)/1024) as DBSizeInMB

       FROM sys.databases DB

       JOIN sys.server_principals SP on DB.owner_sid= SP.sid

       JOIN sys.master_files MF on DB.database_id=MF.database_id

       WHERE DB.database_id >      5

       GROUP by DB.name

              ,      DB.create_date

              ,      SP.name

              ,      DB.user_access_desc

              ,      DB.compatibility_level

              ,      DB.state_desc

              ,      DB.recovery_model_desc

              ,      DB.database_id

 

       IF OBJECT_ID('tempdb..#tempback') IS NOT NULL

              DROP TABLE #tempback

 

       CREATE TABLE #tempback

              (             DBName varchar(200)

                      ,      BackupType varchar(50)

                      ,      BackupStartDate datetime

                      ,      BackupFinishDate datetime

                      ,      UserName varchar(200)

                      ,      BackupSizeMB numeric(10,2)

                      ,      BackupUser varchar(250)

              )

             

       ;WITH backup_information AS

       (

              SELECT database_name

                      ,      backup_type = CASE

                                                          type

                                                          WHEN 'D' THEN 'Full backup'

                                                          WHEN 'I' THEN 'Differential backup'

                                                          WHEN 'L' then 'Log backup'

                                                          ELSE 'Other or copy only backup'

                                                  END

                      ,      backup_start_date

                      ,   backup_finish_date

                      ,      user_name 

                      ,      server_name

                      ,   compressed_backup_size

                      ,   rownum =  row_number() OVER (PARTITION BY database_name, type ORDER BY backup_finish_date DESC

          )

              FROM msdb.dbo.backupset

       )

       INSERT INTO #tempback

       SELECT database_name

              ,   backup_type

              ,   backup_start_date

              ,   backup_finish_date

              ,   server_name

              ,   Convert(varchar,convert(numeric(10,2),compressed_backup_size/ 1024/1024))

              ,   user_name

       FROM backup_information

       WHERE rownum = 1

       ORDER by database_name;

 

       SELECT *

       FROM #tempback AS T

 

       IF OBJECT_ID('tempdb..#tempjob') IS NOT NULL

              DROP TABLE #tempjob

 

       CREATE TABLE #tempjob

              (             Servername varchar(100)

                      ,      categoryname varchar(100)

                      ,      JobName varchar(500)

                      ,      ownerID varchar(250)

                      ,      Enabled varchar(5)

                      ,      NextRunDate datetime

                      ,      LastRunDate datetime

                      ,      status varchar(50)

              )

 

       INSERT INTO #tempjob

           (

                             Servername

                      ,      categoryname

                      ,   JobName

                      ,      ownerID

                      ,   Enabled

                      ,   NextRunDate

                      ,   LastRunDate

                      ,   status

              )

       SELECT CONVERT (varchar, SERVERPROPERTY('Servername')) AS ServerName

              ,      categories.NAME AS CategoryName

              ,      sqljobs.name

              ,      SUSER_SNAME(sqljobs.owner_sid) AS OwnerID

              ,      CASE sqljobs.enabled WHEN 1 THEN 'Yes' ELSE 'No'END AS Enabled

              ,      CASE job_schedule.next_run_date

                             WHEN 0 THEN CONVERT(DATETIME, '1900/1/1')

                             ELSE CONVERT(DATETIME, CONVERT(CHAR(8), job_schedule.next_run_date, 112) + ' ' + STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(8), job_schedule.next_run_time), 6), 5, 0, ':'), 3, 0, ':'))

                      END NextScheduledRunDate

              ,      lastrunjobhistory.LastRunDate

              ,       ISNULL(lastrunjobhistory.run_status_desc,'Unknown') AS run_status_desc

       FROM msdb.dbo.sysjobs AS sqljobs

       LEFT JOIN msdb.dbo.sysjobschedules AS job_schedule     ON sqljobs.job_id = job_schedule.job_id

       LEFT JOIN msdb.dbo.sysschedules AS schedule             ON job_schedule.schedule_id = schedule.schedule_id

       INNER JOIN msdb.dbo.syscategories categories    ON sqljobs.category_id = categories.category_id

       LEFT OUTER JOIN (

                                           SELECT Jobhistory.job_id

                                           FROM msdb.dbo.sysjobhistory AS Jobhistory

                                           WHERE Jobhistory.step_id = 0

                                           GROUP BY Jobhistory.job_id

                                    ) AS jobhistory      ON jobhistory.job_id = sqljobs.job_id  -- to get the average duration

       LEFT OUTER JOIN

                                    (

                                           SELECT sysjobhist.job_id

                                                  ,      CASE sysjobhist.run_date

                                                                 WHEN 0      THEN CONVERT(DATETIME, '1900/1/1')

                                                                 ELSE CONVERT(DATETIME, CONVERT(CHAR(8), sysjobhist.run_date, 112) + ' ' + STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(8), sysjobhist.run_time), 6), 5, 0, ':'), 3, 0, ':'))

                                                          END AS LastRunDate

                                                  ,       sysjobhist.run_status

                                                  ,      CASE sysjobhist.run_status

                                                                 WHEN 0      THEN 'Failed'

                                                                 WHEN 1      THEN 'Succeeded'

                                                                 WHEN 2      THEN 'Retry'

                                                                 WHEN 3      THEN 'Canceled'

                                                                 WHEN 4      THEN 'In Progress'

                                                                 ELSE 'Unknown'

                                                          END AS run_status_desc

                                                  ,       sysjobhist.retries_attempted

                                                   ,       sysjobhist.step_id

                                                  ,       sysjobhist.step_name

                                                  ,       sysjobhist.run_duration AS RunTimeInSeconds

                                                  ,       sysjobhist.message

                                                  ,      ROW_NUMBER() OVER (PARTITION BY sysjobhist.job_id ORDER BY

                                                                                              CASE sysjobhist.run_date

                                                                                                     WHEN 0

                                    THEN CONVERT(DATETIME, '1900/1/1')

              ELSE CONVERT(DATETIME, CONVERT(CHAR(8), sysjobhist.run_date, 112) + ' ' + STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(8), sysjobhist.run_time), 6), 5, 0, ':'), 3, 0, ':'))

    END DESC

              ) AS RowOrder

       FROM msdb.dbo.sysjobhistory AS sysjobhist

WHERE sysjobhist.step_id = 0  --to get just the job outcome and not all steps

)AS lastrunjobhistory

    ON lastrunjobhistory.job_id = sqljobs.job_id  -- to get the last run details

    AND

    lastrunjobhistory.RowOrder=1

 

       SELECT 'JOBs' Jobs

 

       SELECT *

       FROM #tempjob AS T

       ORDER BY T.Enabled DESC