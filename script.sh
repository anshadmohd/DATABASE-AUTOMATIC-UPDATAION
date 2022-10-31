
#!/bin/bash

# set up some variables

NOW_DATE=$(date '+%Y-%m-%d-%H-%M')
RESTORE_FROM_INSTANCE_ID=database-1
TARGET_INSTANCE_ID=temp
TARGET_INSTANCE_CLASS=db.t3.micro
VPC_ID=default-vpc-1311111111111
NEW_MASTER_PASS=*****
SECURITY_GROUP_ID=sg-0iq0d3e0ie

# do the stuff

echo "+------------------------------------------------------------------------------------+"
echo "| RDS Snapshot and Restore to Temp Instance                                          |"
echo "+------------------------------------------------------------------------------------+"
echo ""

echo "Creating manual snapshot of ${RESTORE_FROM_INSTANCE_ID}"
SNAPSHOT_ID=$( aws rds create-db-snapshot --db-snapshot-identifier $RESTORE_FROM_INSTANCE_ID-temp-$NOW_DATE --db-instance-identifier $RESTORE_FROM_INSTANCE_ID --query 'DBSnapshot.[DBSnapshotIdentifier]' --output text )
aws rds wait db-snapshot-completed --db-snapshot-identifier $SNAPSHOT_ID
echo "Finished creating new snapshot ${SNAPSHOT_ID} from ${RESTORE_FROM_INSTANCE_ID}"


# we have created a new manual snapshot above
echo "Finding latest snapshot for ${SNAPSHOT_TARGET_INSTANCE_ID}"
SNAPSHOT_ID=$( aws rds describe-db-snapshots --db-instance-identifier $RESTORE_FROM_INSTANCE_ID --query 'DBSnapshots[-1].[DBSnapshotIdentifier]' --output text )
echo "Snapshot found: ${SNAPSHOT_ID}"

echo "Restoring snapshot ${SNAPSHOT_ID} to a new db instance ${TARGET_INSTANCE_ID}..."
aws rds restore-db-instance-from-db-snapshot \
    --db-instance-identifier $TARGET_INSTANCE_ID \
    --db-snapshot-identifier $SNAPSHOT_ID \
    --db-instance-class $TARGET_INSTANCE_CLASS \
    --db-subnet-group-name $VPC_ID \
    --no-multi-az \
    --publicly-accessible \
    --auto-minor-version-upgrade


while [ "${exit_status}" != "0" ]
do
    echo "Waiting for ${TARGET_INSTANCE_ID} to enter 'available' state..."
    aws rds wait db-instance-available --db-instance-identifier $TARGET_INSTANCE_ID
    exit_status="$?"

    INSTANCE_STATUS=$( aws rds describe-db-instances --db-instance-identifier $TARGET_INSTANCE_ID --query 'DBInstances[0].[DBInstanceStatus]' --output text )
    echo "${TARGET_INSTANCE_ID} instance state is: ${INSTANCE_STATUS}"
done
echo "Finished creating instance ${TARGET_INSTANCE_ID} from snapshot ${SNAPSHOT_ID}"

echo "Updating instance ${TARGET_INSTANCE_ID} backup retention period to 0"
aws rds modify-db-instance \
    --db-instance-identifier $TARGET_INSTANCE_ID \
    --master-user-password $NEW_MASTER_PASS \
    --vpc-security-group-ids $SECURITY_GROUP_ID \
    --backup-retention-period 0 \
    --apply-immediately
aws rds wait db-instance-available --db-instance-identifier $TARGET_INSTANCE_ID

echo "Finished updating ${TARGET_INSTANCE_ID}"

echo "SUCCESS: Operation complete. Created instance ${TARGET_INSTANCE_ID} from snapshot ${SNAPSHOT_ID}"

#################################################################

#mysqldump
echo "Finding latest endpoint of new rds instance ${ENDPOINT_ADDRESS}"

ENDPOINT_ADDRESS=$( aws rds describe-db-instances  --query 'DBInstances[*].[Endpoint.Address]' --db-instance-identifier temp    --output text )
MYSQL_DATABASE=test
MYSQL_USER=admin
MYSQL_PASSWORD=********
MYSQL_PORT='3306'
BACKUP_DIR="/home/ubuntu"
BACKUP_FULL_PATH="$BACKUP_DIR/$MYSQL_DATABASE-$NOW_DATE.sql"
echo "Backup started for database - ${MYSQL_DATABASE}"

mysqldump -h ${ENDPOINT_ADDRESS}  -u ${MYSQL_USER}  -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} -P ${MYSQL_PORT} > ${BACKUP_FULL_PATH} --set-gtid-purged=OFF
echo "SUCCESS: dump completd"



###############################################################

echo "Deleting instance  ${TARGET_INSTANCE_ID}"
    aws rds delete-db-instance --db-instance-identifier $TARGET_INSTANCE_ID --skip-final-snapshot
    aws rds wait db-instance-deleted --db-instance-identifier $TARGET_INSTANCE_ID
    echo "Finished deleting ${TARGET_INSTANCE_ID}"


