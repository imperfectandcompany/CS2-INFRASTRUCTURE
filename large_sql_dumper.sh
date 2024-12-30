#!/bin/bash
# Will show warning about mariadb instead of mysqldump, but it will still work.
mysqldump -u root -p \
  --single-transaction \
  --routines \
  --triggers \
  --events \
  #DBNAMEGOESHERE \
| pv -Wbr \
| gzip -c \
| ssh #USER@#TARGETHOST "cat > /home/dijaz/#DBNAME.sql.gz"
