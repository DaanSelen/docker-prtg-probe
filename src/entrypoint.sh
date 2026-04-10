#!/bin/bash
set -eu

# Environment variables passed from the Dockerfile

PROBE_BINARY="/opt/paessler/mpprobe/prtgmpprobe"
HOSTNAME=$(hostname 2> /dev/null || cat /etc/hostname)
CONFIG_FILE="${PRTGMPPROBE__CONFIG_FILE:-/config/config.yml}"

PRTGMPPROBE__ID_FILE="${PRTGMPPROBE__ID_FILE:-/config/id.txt}"

export PRTGMPPROBE__ID="${PRTGMPPROBE__ID:-}"
export PRTGMPPROBE__NAME="${PRTGMPPROBE__NAME:-linux-probe@$HOSTNAME}"

# Refuse to accept sensitive data as env variable

for var in \
  PRTGMPPROBE__ACCESS_KEY \
  PRTGMPPROBE__NATS__AUTHENTICATION__USER \
  PRTGMPPROBE__NATS__AUTHENTICATION__PASSWORD
do
  if [ -n "${!var-}" ]; then
    echo "ERROR: refusing to accept $var via environment variables" >&2
    echo "Use ${CONFIG_FILE} instead" >&2
    exit 1
  fi
done

# Validate configuration file exists
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "ERROR: Config file not found @ ${CONFIG_FILE}" >&2
    echo "Example configuration:" >&2
    echo "---" >&2
    exec "${PROBE_BINARY}" "example-config" >&2
    exit 1
fi

# If there is no line starting with: 'id:'
echo "Searching for the PRTG Multi-Platform Probe ID"
if ! grep -q "^id:" "${CONFIG_FILE}"; then
    echo "Did not find 'id' key in ${CONFIG_FILE}"

    # If the environment variable 'PRTGMPPROBE__ID' is empty
    if [ -z "${PRTGMPPROBE__ID}" ]; then
        echo "Did not find 'PRTGMPPROBE__ID' environment variable"

        # If the ID file is not on the filesystem
        if [ ! -f "${PRTGMPPROBE__ID_FILE}" ]; then
            echo "Last resort measure: generate a PROBE ID from '/proc/sys/kernel/random/uuid'"

            # Try to make a random PROBE ID from UUID
            if ! cat /proc/sys/kernel/random/uuid > "${PRTGMPPROBE__ID_FILE}"; then
                echo "ERROR: Failed last resort: unable to read '/proc/sys/kernel/random/uuid'" >&2
                echo "Manual investigation is required" >&2
                exit 1
            fi
        else
            echo "Found an existing file @ ${PRTGMPPROBE__ID_FILE}"
        fi

        export PRTGMPPROBE__ID="$(cat ${PRTGMPPROBE__ID_FILE})"
    else
        echo "Found a non-empty environment variable with the name 'PRTGMPPROBE__ID'"
    fi
else
    echo "Found an 'id' key in ${CONFIG_FILE} which will be used"
fi
echo "Runtime ID: ${PRTGMPPROBE__ID}"

if [ -z "${PRTGMPPROBE__NATS__CLIENT_NAME}" ]; then
    echo "Setting PRTGMPPROBE__NATS__CLIENT_NAME since its empty"
    PRTGMPPROBE__NATS__CLIENT_NAME="${PRTGMPPROBE__NAME}"
fi

env | grep "PRTGMPPROBE__"

# Start the binary
echo $(date)
echo "Starting binary"
echo "---"

exec gosu paessler_mpprobe:paessler_mpprobe \
    "${PROBE_BINARY}" --config "${CONFIG_FILE}" "$@"
