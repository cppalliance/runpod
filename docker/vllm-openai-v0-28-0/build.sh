#!/bin/bash

set -xe
image=cppalliance/vllm-openai:v0.28.0
echo image is $image
docker buildx build -t $image .

echo $?
# if [ "$?" = "0" ] ; then
#     docker push $image
# fi
