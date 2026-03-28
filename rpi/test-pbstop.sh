#!/bin/bash
#test-pbstop.sh
set -e

CHIP=0
STATUS_PIN=17

pulse_v2() {
   /usr/bin/gpioset -c "$CHIP" \
      --toggle 220ms,70ms,90ms,70ms,90ms,70ms,90ms,0 \
      "$STATUS_PIN=1"
}

SERVICE="powerblock.service"

echo "Stopping $SERVICE..."
sudo systemctl stop "$SERVICE"

echo "Checking for running gpio processes..."

# Get PIDs of gpio processes (excluding the grep itself)
PIDS=$(ps -ef | grep gpio | grep -v grep | awk '{print $2}')

if [ -z "$PIDS" ]; then
    echo "No gpio processes found."
else
    echo "Found gpio process(es): $PIDS"
    echo "Killing process(es)..."
    sudo kill $PIDS
    echo "Done."
fi

# optional short settle delay after stop
sleep 0.1

echo "Run Pulse test..."
pulse_v2
echo "Pulse Sent..."

echo "Starting $SERVICE..."
sudo systemctl start "$SERVICE"

