#!/bin/bash

docker build --tag populate-kafka .
docker run -it --rm --env-file populate_kafka_env.list populate-kafka
