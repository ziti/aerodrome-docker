# Backup and Restore

The `aerodrome-data` named volume holds Aerodrome's durable data:

```text
/data/config.yaml
/data/aircraft_history.db
/data/.backups/
```

Treat that volume as stateful application data. Container recreation is routine; losing the volume is not.

The volume can also hold `aircraft_history.db.bak.*.pre-restore` database copies, which Aerodrome keeps from recent restores and prunes on its own, as well as server-side backup zips in `.backups/`. They use volume space and will be included in volume backups.

## Recommended Backup Strategy

Back up the named volume on a schedule to storage outside the Docker host, using any volume backup tool you trust. Keep repository credentials outside this Git repository. Back up before Aerodrome upgrades and significant configuration changes too.

If your tool supports stopping the service while it snapshots the volume, use that option to get a consistent SQLite database copy.

`config.yaml` has mode `0600` and belongs to UID 65532. A backup job must run as root or UID 65532 to read it.

As a second recovery path, Aerodrome's **Backup & Restore** page can download an application-consistent backup created through SQLite's online backup API. Store downloaded backups outside the Docker host. Server-side backups in `/data/.backups` survive a container recreate, but they share the volume's fate, so they do not protect against losing it.

## Restoring from the Web Interface

Restoring from Aerodrome's **Backup & Restore** page stages the backup, then waits for a restart. Aerodrome cannot restart itself in a container, so finish the restore yourself:

```bash
docker compose restart aerodrome
```

Keep these limits in mind:

* Use `restart`, not a recreate. If the container is recreated while a restore waits, the restore is not applied, your current data is kept, and the Settings page says so.
* A restore that waits more than an hour is dropped, and nothing changes.
* Saving settings is refused while a restore waits.
* The pre-restore copy of `config.yaml` is kept on the container filesystem, so it does not survive a recreate.

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
2. Restore the `aerodrome-data` volume from a known-good backup, keeping file ownership and modes.
3. Start the stack.
4. Confirm that the container becomes healthy and `/api/ready` returns HTTP 200.
5. Confirm that the expected configuration and aircraft history are present in the web interface.
6. Verify your backup repository's integrity according to your backup tool's guidance.

Perform the first restore drill against a disposable Compose project or host. Do not overwrite the production volume merely to test recovery.
