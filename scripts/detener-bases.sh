#!/usr/bin/env bash
# Stops every UrbanAlert database that is running: RDS instances and DocumentDB clusters named urban-alert-*.
# AWS restarts a stopped database after 7 days; the daily Mantener pausa workflow calls this while paused.
# Identifiers have no spaces, so the text output splits safely on whitespace.
# A database in another state (starting, stopping, backing-up…) is left alone and retried on the next run.
# Usage: scripts/detener-bases.sh   (needs AWS credentials)
set -euo pipefail

detenidas=0

# DocumentDB instances also appear in describe-db-instances; they are stopped through their cluster.
instancias="$(aws rds describe-db-instances --output text \
  --query "DBInstances[?starts_with(DBInstanceIdentifier, 'urban-alert-') && Engine != 'docdb' && DBInstanceStatus == 'available'].DBInstanceIdentifier")"
for id in $instancias; do
  aws rds stop-db-instance --db-instance-identifier "$id" >/dev/null
  echo "stopping RDS instance $id"
  detenidas=$((detenidas + 1))
done

clusters="$(aws docdb describe-db-clusters --output text \
  --query "DBClusters[?starts_with(DBClusterIdentifier, 'urban-alert-') && Engine == 'docdb' && Status == 'available'].DBClusterIdentifier")"
for id in $clusters; do
  aws docdb stop-db-cluster --db-cluster-identifier "$id" >/dev/null
  echo "stopping DocumentDB cluster $id"
  detenidas=$((detenidas + 1))
done

echo "databases stopped in this run: $detenidas"
