#!/bin/sh
set -e

# Paths to watch recursively
PATHS="/mnt/gateway_config /mnt/node_config /mnt/node_data /mnt/workspace"

# If PUID is not provided or is 1000, no watcher needed
HOST_UID="${PUID:-1000}"
if [ "$HOST_UID" = "1000" ]; then
    echo "Host UID matches container UID (1000). Success is guaranteed. No watcher needed."
    # Signal that we are ready for other services (even if sitting idle)
    touch /tmp/ready
    # Sleep indefinitely to avoid a Docker restart loop (unless-stopped/always).
    exec sleep infinity
fi

echo "Starting dedicated permission watcher for host UID: ${HOST_UID}..."

# Filtering for paths that actually exist to prevent inotifywait from failing
EXISTING_PATHS=""
for p in $PATHS; do
    if [ -d "$p" ]; then
        EXISTING_PATHS="$EXISTING_PATHS $p"
    fi
done

if [ -z "$EXISTING_PATHS" ]; then
    echo "ERROR: No valid watch paths found at /mnt/. Exiting."
    exit 1
fi

# Initial pass to ensure current files are correct (Catch-up mode)
echo "Performing initial permission sync..."
setfacl -R -m u:1000:rwx,u:${HOST_UID}:rwx,d:u:1000:rwx,d:u:${HOST_UID}:rwx,m:rwx $EXISTING_PATHS || true

# Signal that the initial sync is finished (for Docker healthcheck)
touch /tmp/ready

# Watch recursively for creations, moves, and attribute changes (chmod)
inotifywait -m -r -e create,moved_to,attrib --format '%w%f' $EXISTING_PATHS | while IFS= read -r FILE
do
    if [ -e "$FILE" ]; then
        # Ensure node user (1000) and Host user (PUID) always have rwx.
        # We explicitly set default ACLs on directories to maintain inheritance for future files.
        if [ -d "$FILE" ]; then
            setfacl -m u:1000:rwx,u:${HOST_UID}:rwx,d:u:1000:rwx,d:u:${HOST_UID}:rwx,m:rwx "$FILE" 2>/dev/null || true
        else
            setfacl -m u:1000:rwx,u:${HOST_UID}:rwx,m:rwx "$FILE" 2>/dev/null || true
        fi
    fi
done
