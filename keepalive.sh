#!/bin/bash
while true; do
  echo "$(date -u) | VPS alive | uptime: $(uptime -p)" >> ~/storage/uptime.log
  sleep 300
done
