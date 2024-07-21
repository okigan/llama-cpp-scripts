#!/bin/bash

# Set the model URL
MODEL_URL="https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF/resolve/main/mistral-7b-instruct-v0.2.Q4_K_S.gguf"

LM_STUDIO_CACHE="${HOME}/.cache/lm-studio/models"
MODEL_AUTHOR=$(echo "${MODEL_URL}" | sed -n 's|.*huggingface\.co/\([^/]*\)/.*|\1|p')
MODEL_NAME=$(echo "${MODEL_URL}" | sed -n 's|.*/\([^/]*\)/resolve/.*|\1|p')
MODEL_FILENAME=$(basename "${MODEL_URL}")
MODEL_PATH="${LM_STUDIO_CACHE}/${MODEL_AUTHOR}/${MODEL_NAME}/${MODEL_FILENAME}"

LLAMA_DIR=../../chat-namer/llama.cpp
LLAMA_SERVER=${LLAMA_DIR}/llama-server

# Check if LLAMA_SERVER exists
if [ ! -f "${LLAMA_SERVER}" ]; then
    echo "Error: ${LLAMA_SERVER} not found. Please ensure llama.cpp is properly built and the executable is in the correct location."
    exit 1
fi

# Ensure the directory exists
mkdir -p "$(dirname "${MODEL_PATH}")"

# Download the model if it doesn't exist
if [ ! -f "${MODEL_PATH}" ]; then
    echo "Model not found. Downloading..."
    curl -L ${MODEL_URL} -o "${MODEL_PATH}"
    if [ $? -ne 0 ]; then
        echo "Failed to download the model. Please check your internet connection and try again."
        exit 1
    fi
    echo "Model downloaded successfully."
else
    echo "Model already exists. Skipping download."
fi

# Function to test chat completion
test_chat_completion() {
    echo "Testing chat completion..."
    curl -s -v http://localhost:10080/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer no-key" \
    -d '{
        "model": "mistral-7b-instruct",
        "messages": [
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": "What is the capital of France?"}
        ]
    }' -o /dev/null 2>&1 | grep HTTP
    echo -e "\n"
}

# Function to test embeddings
test_embeddings() {
    echo "Testing embeddings..."
    curl -s -v http://localhost:10080/v1/embeddings \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer no-key" \
    -d '{
        "input": "Hello, world!",
        "model": "mistral-7b-instruct"
    }' -o /dev/null 2>&1 | grep HTTP
    echo -e "\n"
}

# Run server without --embeddings flag
echo "Running server WITHOUT --embeddings flag..."
${LLAMA_SERVER} -m "${MODEL_PATH}" -c 2048 --host 0.0.0.0 --port 10080 --verbosity 0 > /dev/null 2>&1 & 
SERVER_PID=$!

# Wait for server to start
echo "Waiting for server to start..."
until curl -s http://localhost:10080/health | grep -q '"status":"ok"'
do
    sleep 1
done
echo "Server is ready."

test_chat_completion
test_embeddings

echo ####################################
echo

# Stop the server
kill $SERVER_PID
sleep 5  # Wait for server to stop

# Run server with --embeddings flag
echo "Running server with --embeddings flag..."
${LLAMA_SERVER} -m "${MODEL_PATH}" -c 2048 --host 0.0.0.0 --port 10080 --embeddings --verbosity 0 > /dev/null 2>&1 &
SERVER_PID=$!

# Wait for server to start
echo "Waiting for server to start..."
until curl -s http://localhost:10080/health | grep -q '"status":"ok"'
do
    sleep 1
done
echo "Server is ready."

test_chat_completion
test_embeddings

# Stop the server
kill $SERVER_PID

echo "Tests completed."