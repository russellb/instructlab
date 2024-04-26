#!/bin/sh
set -euf
# set -x

# This is a basic workflow test of the containers containing the tasks
# that a typical user would run through to use them and get familiar with ilab
#
# It is written in shell script because this basic workflow *is* a shell
# workflow, run through step by step at a shell prompt by a user.

export GREP_COLORS='mt=1;33'
BOLD='\033[1m'
NC='\033[0m' # No Color

SCRIPTDIR=$(dirname "$0")

step() {
    echo -e "$BOLD$@$NC"
}

task() {
    echo -e "$BOLD------------------------------------------------------$NC"
    step $@
}

test_smoke() {
    task Smoke test InstructLab
    ilab | grep --color 'Usage: ilab'
}

test_init() {
    task Initializing ilab
    printf "taxonomy\ny" | ilab init

    step Checking config.yaml
    cat config.yaml | grep merlinite
}

test_download() {
    task Download the model

    ilab download --repository instructlab/granite-7b-lab-GGUF --filename granite-7b-lab-Q4_K_M.gguf
}

test_serve() {
    # Accepts an argument of the model, or default here
    model="${1:-./models/granite-7b-lab-Q4_K_M.gguf}"

    task Serve the model
    ilab serve --model-path $model &

    ret=1
    for i in $(seq 1 10); do
        sleep 5
    	step $i/10: Waiting for model to start
        if curl -sS http://localhost:8000/docs > /dev/null; then
            ret=0
            break
        fi
    done

    return $ret
}

test_chat() {
    task Chat with the model
    printf 'Say "Hello"\n' | ilab chat  -m models/granite-7b-lab-Q4_K_M.gguf | grep --color 'Hello'
}

test_taxonomy() {
    task Update the taxonomy
    ls -al | grep --color 'taxonomy'

    step Make new taxonomy
    mkdir -p taxonomy/knowledge/sports/overview/softball

    step Put new qna file into place
    cp $SCRIPTDIR/basic-workflow-fixture-qna.yaml taxonomy/knowledge/sports/overview/softball/qna.yaml
    head taxonomy/knowledge/sports/overview/softball/qna.yaml | grep --color '1st base'

    step Verification
    ilab diff
}

test_generate() {
    task Generate synthetic data
    ilab generate --model ./models/granite-7b-lab-Q4_K_M.gguf --num-instructions 5
}

test_train() {
    task Train the model
    ilab train --gguf-model-path models/granite-7b-lab-Q4_K_M.gguf
}

test_convert() {
    task Converting the trained model and serving it
    ilab convert
}

# TODO: Workarounds

# TODO: Keep this line until new containers are built that include
# https://github.com/instructlab/instructlab/pull/988
test -d taxonomy || git clone https://github.com/instructlab/taxonomy || true
rm -f config.yaml

# TODO: Keep this until libcudann8 is installed
# https://github.com/instructlab/instructlab/pull/1018
dnf install -y libcudnn8

# The list of actual tests to run through in workflow order
test_smoke
test_init
test_download

# See below for cleanup, this runs an ilab serve in the background
test_serve
PID=$!

test_chat
test_taxonomy
test_generate
test_train
test_convert

# Kill the serve process
task Stopping the ilab serve
step Kill ilab serve $PID
kill $PID

# Serve with the new model
test_serve /tmp/somemodelthatispretrained.gguf
PID=$!

# TODO: chat with the new model
test_chat

# Kill the serve process
task Stopping the ilab serve
step Kill ilab serve $PID
kill $PID


