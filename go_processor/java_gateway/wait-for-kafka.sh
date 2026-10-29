#!/bin/sh
# wait-for-kafka.sh

set -e

host="$1"
shift
cmd="$@"

until nc -z "$host" 9092; do
  >&2 echo "Kafka is unavailable - sleeping"
  sleep 1
done

>&2 echo "Kafka is up - executing command"
exec $cmd