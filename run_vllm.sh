#!/bin/bash
# usage: ./run_vllm.sh <model> <clones>
if [ "$#" -ne 2 ]; then
    echo "Usage: ./run_vllm.sh <model> <clones>"
    exit 1
fi

PIDS=()
# kill if ctrl+c
function kill_servers() {
    echo "Killing servers"
    for pid in ${PIDS[@]}; do
        kill -9 $pid
    done
    exit 0
}
trap kill_servers SIGINT

# string of balancers. e.g. "-b localhost:8000 -b localhost:8001 ..."
BALANCERS=""

BASE_PORT=8000
for i in $(seq 1 $2); do
    PORT=$((BASE_PORT + i))
    BALANCERS="$BALANCERS -b http://127.0.0.1:$PORT"
    echo "Starting server on port $PORT"
    PIDS+=($!)
    if [[ "$1" == /* ]]; then
        SERVED_MODEL_NAME=$(basename "$1")
    else
        SERVED_MODEL_NAME=$1
    fi
    CUDA_VISIBLE_DEVICES=$((i-1)) python -m vllm.entrypoints.openai.api_server \
        --model $1 \
        --trust-remote-code \
        --served-model-name $SERVED_MODEL_NAME \
        --disable-frontend-multiprocessing \
        --max-model-len 32000 \
        --enforce-eager \
        --dtype bfloat16 \
        --port $PORT &
done

# run load balancer
echo "Starting load balancer on port $BASE_PORT - balancers: $BALANCERS"
./bin/load-balancer-linux -p 8000 $BALANCERS
