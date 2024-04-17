#!/bin/bash
# usage: ./run_vllm.sh <model> <clones>
if [ "$#" -ne 2 ]; then
    echo "Usage: ./run_vllm.sh <model> <clones>"
    exit 1
fi

# python -m vllm.entrypoints.openai.api_server --model bigcode/starcoder2-15b --dtype bfloat16 --port 800

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
    CUDA_VISIBLE_DEVICES=$((i-1))
    echo "Starting server on port $PORT with CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
    PIDS+=($!)
    CUDA_VISIBLE_DEVICES=$((i-1)) python -m vllm.entrypoints.openai.api_server --model $1 --dtype bfloat16 --port $PORT &
done

# run load balancer
echo "Starting load balancer on port $BASE_PORT - balancers: $BALANCERS"
./bin/load-balancer-linux -p 8000 $BALANCERS
