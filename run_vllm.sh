#!/bin/bash
# usage: ./run_vllm.sh <model> <clones>
if [ "$#" -ne 2 ]; then
    echo "Usage: ./run_vllm.sh <model> <clones>"
    exit 1
fi

function kill_servers() {
    echo "Killing servers"
    pkill -9 -f "python -m vllm.entrypoints.openai.api_server"
    pkill -9 -f "run_vllm.sh"
    exit 0
}
trap kill_servers SIGINT

# string of balancers. e.g. "-b localhost:8000 -b localhost:8001 ..."
BALANCERS=""

function spawn_vllm_server() {
    local gpu_id=$1
    echo "gpu id $gpu_id"
    local model=$2
    local port=$3
    local served_model_name=$4
    while true; do
        export ENGINE_ITERATION_TIMEOUT_S=600
        export VLLM_ENGINE_ITERATION_TIMEOUT_S=600
        CUDA_VISIBLE_DEVICES=$((gpu_id-1)) python -m vllm.entrypoints.openai.api_server \
            --model "$model" \
            --trust-remote-code \
            --served-model-name "$served_model_name" \
            --disable-frontend-multiprocessing \
            --max-model-len 20000 \
            --enforce-eager \
            --dtype bfloat16 \
            --disable-log-requests \
            --port "$port" 2>&1 | tee /tmp/vllm-$gpu_id.log

        echo "Server on GPU $gpu_id crashed. Restarting in 5 seconds..."
        sleep 5
    done
}

BASE_PORT=8000
for i in $(seq 1 $2); do
    PORT=$((BASE_PORT + i))
    BALANCERS="$BALANCERS -b http://127.0.0.1:$PORT"
    echo "Starting server on port $PORT"
    if [[ "$1" == /* ]]; then
        SERVED_MODEL_NAME=$(basename "$1")
    else
        SERVED_MODEL_NAME=$1
    fi
    spawn_vllm_server "$i" "$1" "$PORT" "$SERVED_MODEL_NAME" &
done

# run load balancer
echo "Starting load balancer on port $BASE_PORT - balancers: $BALANCERS"
./bin/load-balancer-linux -p 8000 $BALANCERS
