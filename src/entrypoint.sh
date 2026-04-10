#!/bin/bash
set -eu

# Environment variables passed from the Dockerfile

PROBE_BINARY="/opt/paessler/mpprobe/prtgmpprobe"

HOSTNAME=$(hostname 2> /dev/null || cat /etc/hostname)

CONFIG_FILE="${PRTGMPPROBE__CONFIG_FILE:-/config/config.yml}"
PROBE_NAME="${PRTGMPPROBE__NAME:-linux-probe@$HOSTNAME}"
PROBE_ID_FILE="${PRTGMPPROBE__ID_FILE:-/config/id.txt}"
PROBE_ID="${PRTGMPPROBE__ID:-}"

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
if ! grep -q "^id:" "${CONFIG_FILE}"; then

    # If the environment variable 'PROBE_ID' is empty
    if [ -z "${PROBE_ID}" ]; then

        # If the ID file is not on the filesystem
        if [ ! -f "${PROBE_ID_FILE}" ]; then
            echo "Last resort measure: generate a PROBE ID from '/proc/sys/kernel/random/uuid'"

            # Try to make a random PROBE ID from UUID
            if ! cat /proc/sys/kernel/random/uuid > "${PROBE_ID_FILE}"; then
                echo "ERROR: Failed last resort: unable to read '/proc/sys/kernel/random/uuid'" >&2
                echo "Manual investigation is required" >&2
                exit 1
            fi
        fi

        PROBE_ID="$(cat ${PROBE_ID_FILE})"
    fi

    export PROBE_ID
fi

# Export all the environment variables

export PROBE_NAME
export PRTGMPPROBE__MOMO__DIR="${PRTGMPPROBE__MOMO__DIR:-/opt/paessler/mpprobe/monitoringmodules/}"
export PRTGMPPROBE__MAX_SCHEDULING_DELAY="${PRTGMPPROBE__MAX_SCHEDULING_DELAY:-300}"
export PRTGMPPROBE__HEARTBEAT_INTERVAL="${PRTGMPPROBE__HEARTBEAT_INTERVAL:-30}"
export PRTGMPPROBE__NATS__CLIENT_NAME="${PRTGMPPROBE__NATS__CLIENT_NAME:-$PROBE_NAME}"

export PRTGMPPROBE__LOGGING__CONSOLE__LEVEL="${PRTGMPPROBE__LOGGING__CONSOLE__LEVEL:-info}"
export PRTGMPPROBE__LOGGING__CONSOLE__WITHOUT_TIME="${PRTGMPPROBE__LOGGING__CONSOLE__WITHOUT_TIME:-true}"
export PRTGMPPROBE__LOGGING__JOURNALD__LEVEL="${PRTGMPPROBE__LOGGING__JOURNALD__LEVEL:-off}"
export PRTGMPPROBE__LOGGING__JOURNALD__FIELD_PREFIX="${PRTGMPPROBE__LOGGING__JOURNALD__FIELD_PREFIX:-PRTGMPROBE}"

# Print all the configuration which is going to be used
env | grep PRTGMPROBE__ >&2 || true

# Start the binary
echo $(date)
echo "Starting binary"
echo "---"

exec "${PROBE_BINARY}" \
  --config "${CONFIG_FILE}" \
  "$@"
