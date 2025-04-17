SELECT
   empID AS empId
   ,SiteId AS siteId
   ,EmailWork AS emailW
   ,NameLast AS ln
   ,NameFirst AS fn
   ,BargUnitId AS bargId
   ,EmailHome AS emailH
   ,HomePhoneMobile AS mobile
   ,EmploymentTypeCode AS empType
   ,EmploymentStatusCode AS empStatus
   ,JobCategoryId
   ,JobCategoryDescr
   ,JobClassId
   ,JobClassDescr AS jobDesc
   ,PersonTypeId AS persId
   ,DateTimeEdited AS dts
  FROM vwHREmploymentList
  WHERE
    -- Regular employee accounts
    ( EmailWork LIKE '%@chico%'
    AND EmploymentStatusCode NOT IN ('R','T','D','X')
    AND SiteId IN ( 010,020,030,050,060,070,080,090,111,110,120,130,160,180,190,200,210,230,240,250,260,270,280,640,740 )
    AND JobCategoryId NOT IN ('BUILDING','DRIVER','INSTRUCT','NUTRI')
    -- AND PersonTypeId IN (1,2,4)
    -- AND BargUnitId IN ('CUTA','CUMA','CSEA','CHRT')
    AND BargUnitId NOT IN ('REST')
    AND EmploymentStatusCode IN ('A','I','L','W')
    AND DateTimeEdited > DATEADD(day,-5,getdate())
    )
    -- Student worker accounts
    OR (
      PersonTypeId = 6
      AND DateTimeEdited > DATEADD(day,-5,getdate())
      AND EmploymentStatusCode IN ('A')
      )
  ORDER BY JobCategoryId;

--   select distinct JobCategoryId from vwHREmploymentList order by JobCategoryId;