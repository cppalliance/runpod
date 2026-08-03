#!/bin/bash

set -xe
image=cppalliance/vllm-openai:v0.24.0v2
echo image is $image

# Monitoring servers the agents in the image should trust.
# Leave these empty to use the Dockerfile defaults:
#   MONITOR_HOST/MONITOR_IP      monitor.cppalliance.org / 54.193.145.236  (nrpe, munin)
#   PROMETHEUS_HOST/PROMETHEUS_IP  prometheus2.cpp.al / 35.193.106.93      (node_exporter)
MONITOR_HOST=""
MONITOR_IP=""
PROMETHEUS_HOST=""
PROMETHEUS_IP=""

build_args=()
for v in MONITOR_HOST MONITOR_IP PROMETHEUS_HOST PROMETHEUS_IP ; do
    if [ -n "${!v}" ] ; then
        build_args+=(--build-arg "${v}=${!v}")
    fi
done

docker buildx build "${build_args[@]}" -t $image .

echo $?
# if [ "$?" = "0" ] ; then
#     docker push $image
# fi
