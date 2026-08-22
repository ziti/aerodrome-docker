# Backup and Restore

The `aerodrome-data` named volume contains both durable Aerodrome assets:

```text
/data/config.yaml
/data/aircraft_history.db
```

Treat that volume as stateful application data. Container recreation is routine; losing the volume is not.

## Recommended Backup Strategy

For Dockhand deployments, configure Dockhand's built-in backup feature to back up the stack's named volume with Restic. In the intended homelab deployment, Restic stores the backup in Vault's Restic REST Server. Keep the repository credentials outside this Git repository.

Run backups on a schedule and before Aerodrome upgrades or significant configuration changes. If the backup system supports stopping or quiescing a service while snapshotting its volume, use that option to obtain a consistent SQLite database copy.

As a second recovery path, Aerodrome's **Backup & Restore** page can download an application-consistent backup created through SQLite's online backup API. Store downloaded backups outside the Docker host. Do not rely on server-side backups under `/opt/aerodrome/.backups`; that directory is part of the disposable container filesystem.

## Data-Loss Scenarios

Plan for more than an accidental `docker compose down -v`. The named volume can also be lost or damaged by:

* Docker volume pruning or manual removal
* Host disk or filesystem failure
* SQLite corruption or an interrupted write
* Operator error or unwanted configuration changes
* A failed application upgrade or migration
* Loss of the entire Docker host

A backup stored only on the Docker host does not protect against host loss.

## Restore Drill

Test restores periodically. A successful backup job proves that data was uploaded, not that the service can recover from it.

1. Stop the Aerodrome stack without deleting its volume.
2. Restore the `aerodrome-data` volume with Dockhand from a known-good Restic snapshot.
3. Start the stack.
4. Confirm that the container becomes healthy and `/api/ready` returns HTTP 200.
5. Confirm that the expected configuration and aircraft history are present in the web interface.
6. Run `restic check` according to the backup service's maintenance schedule.

Perform the first restore drill against a disposable Compose project or host. Do not overwrite the production volume merely to test recovery.
