#!/bin/bash

DATA_DIR="/var/lib/pgsql/data"
POSTGRESQL_CONF="/var/lib/pgsql/data/postgresql.conf"
RECOVERY_CONF="/var/lib/pgsql/data/"
RECOVERY_BACKUPS="/var/lib/pgsql/backups"
RECOVERY_USER="postgres"
RECOVERY_PASS="postgres"
SERVER_TYPE=$1

SERVER_TYPE="master"

echo -e "
+-------------------------------------------------------------------+
| This script recover master or slave server                        |
| add them many slave servers.                                      |
| Copyright 2016 iSergio (s.serge.b@gmail.com).                     |
| Licensed under the Apache License, Version 2.0 (the \"License\");   |
| you may not use this file except in compliance with the License.  |
| You may obtain a copy of the License at                           |
| http://www.apache.org/licenses/LICENSE-2.0                        |
+-------------------------------------------------------------------+"

read -r -p "Begin recover master server? [y/N]" response
if ! [[ $response =~ ^([yY][eE][sS]|[yY])$ ]]; then
	exit 0;
fi

if [[ $SERVER_TYPE == 'master' ]]; then
	while read item; do
 		MASTER_HOSTS[$i]="$item"
		i=$((i+1))
	done < <(grep -E -o "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)" $RECOVERY_CONF'recovery.done')
	cd $DATA_DIR
	slave_host=$(grep -E -o "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)" $POSTGRESQL_CONF)
su postgres -c "psql -c \"SELECT pg_start_backup('Master recovery', true)\"" <<EOF
$RECOVERY_PASS
EOF
	su postgres -c 'rsync -azvh --progress '$DATA_DIR'/* '${MASTER_HOSTS[0]}':/'$DATA_DIR' --exclude postmaster.pid --exclude postgresql.conf --exclude recovery.done --exclude recovery.conf --exclude pg_hba.conf'
	# Change slave ip to master ip to send wal logs
	sed -i "s/$slave_host/${MASTER_HOSTS[0]}/g" "$POSTGRESQL_CONF"
	service postgresql reload
su postgres -c "psql -c \"SELECT pg_stop_backup()\"" <<EOF
$RECOVERY_PASS
EOF
	
	# Configure Master Cluster to work as Slave
	echo -e "standby_mode = on\nprimary_conninfo = 'host=$slave_host port=5432 user=postgres'\nrestore_command = 'cp $RECOVERY_BACKUPS/%f %p'\narchive_cleanup_command = 'pg_archivecleanup $RECOVERY_BACKUPS  %r'\ntrigger_file='/tmp/postgresql.trigger'" | su postgres -c 'ssh postgres@'${MASTER_HOSTS[0]}' "cat > '$DATA_DIR'/recovery.conf"'
	echo "hot_standby = on" | su postgres -c 'ssh postgres@'${MASTER_HOSTS[0]}' "cat >> '$POSTGRESQL_CONF'"'
	su postgres -c 'ssh -t postgres@'${MASTER_HOSTS[0]}' pg_ctl restart -D '$DATA_DIR' -s -w'
	
	rm -rf /tmp/postgresql.trigger

	# Now master is slave an slave is master
	# Do master master
	su postgres -c 'ssh postgres@'${MASTER_HOSTS[0]}' touch /tmp/postgresql.trigger'
	service postgresql stop
	# Do slave slave
	sed -i "s/${MASTER_HOSTS[0]}/$slave_host/g" "$POSTGRESQL_CONF"
	mv $RECOVERY_CONF/recovery.done $RECOVERY_CONF/recovery.conf
	
su postgres -c 'ssh '$RECOVERY_USER'@'${MASTER_HOSTS[0]}'' <<EOF
psql -c "SELECT pg_start_backup('Master recovery', true)"
$RECOVERY_PASS
EOF
	su postgres -c 'ssh postgres@'${MASTER_HOSTS[0]}' rsync -azvh --progress '$DATA_DIR'/* '$slave_host':/'$DATA_DIR' --exclude postmaster.pid --exclude postgresql.conf --exclude recovery.done --exclude recovery.conf --exclude pg_hba.conf'

su postgres -c 'ssh '$RECOVERY_USER'@'${MASTER_HOSTS[0]}'' <<EOF
psql -c "SELECT pg_stop_backup()"
$RECOVERY_PASS
EOF

	service postgresql start
	su postgres -c 'ssh postgres@'${MASTER_HOSTS[0]}' rm -rf /tmp/postgresql.trigger'
fi
