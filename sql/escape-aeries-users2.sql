SELECT
   empID AS id
   ,EmailWork AS emailW
   ,NameLast AS ln
   ,NameFirst AS fn
   ,BargUnitId AS bargId
   ,EmailHome AS emailH
   ,HomeAddrCity AS city
   ,HomeAddrStateCode AS state
   ,HomeAddrStreet AS addr
   ,HomeAddrZip AS zip
   ,HomePhone AS phone
   ,HomePhoneMobile AS cell
   ,EmploymentTypeCode AS empType
   ,EmploymentStatusCode AS empStatus
   ,JobClassDescr AS jobDesc
   ,PersonTypeId AS persType
   ,DateTimeEdited AS dts
  FROM vwHREmploymentList
  WHERE
   EmailWork LIKE '%@chico%'
   AND EmploymentStatusCode NOT IN ('R','T')
   -- PersonTypeId IN (1,2,4)
   -- AND
   -- AND BargUnitId IN ('CUTA','CUMA','CSEA','CHRT')
   -- AND EmploymentStatusCode IN ('A','I','L','W')
   -- AND DateTimeEdited > DATEADD(day,-60,getdate())
  ORDER BY empID DESC;