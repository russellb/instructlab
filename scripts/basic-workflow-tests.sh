#!/bin/sh
set -euf
# set -x

# This is a basic workflow test of the ilab CLI.
#
# We expect it to be run anywhere `ilab` would run, including the instructlab
# container images.
#
# It represents the tasks a typical user would run through to get familiar with ilab.
#
# It is written in shell script because this basic workflow *is* a shell
# workflow, run through step by step at a shell prompt by a user.

MINIMAL=0
NUM_INSTRUCTIONS=5
GENERATE_ARGS=
TRAIN_ARGS=
CI=0

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

set_defaults() {
    if [ "$MINIMAL" -eq 0 ]; then
        return
    fi

    NUM_INSTRUCTIONS=1
    GENERATE_ARGS="--num-cpus $(nproc)"
    TRAIN_ARGS="--num-epochs 1"
}

test_smoke() {
    task Smoke test InstructLab
    ilab | grep --color 'Usage: ilab'
}

test_init() {
    task Initializing ilab
    [ -f config.yaml ] || printf "taxonomy\ny" | ilab init

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
    cp $SCRIPTDIR/test-data/basic-workflow-fixture-qna.yaml taxonomy/knowledge/sports/overview/softball/qna.yaml
    head taxonomy/knowledge/sports/overview/softball/qna.yaml | grep --color '1st base'

    step Verification
    ilab diff
}

test_generate() {
    task Generate synthetic data
    ilab generate --model ./models/granite-7b-lab-Q4_K_M.gguf --num-instructions ${NUM_INSTRUCTIONS} ${GENERATE_ARGS}
}

test_train() {
    task Train the model

    device=
    if ls /dev/nvidia* > /dev/null 2> /dev/null; then
         step With CUDA
         device='--device=cuda'
    fi

    ilab train $device --gguf-model-path models/granite-7b-lab-Q4_K_M.gguf ${TRAIN_ARGS}
}

test_convert() {
    task Converting the trained model and serving it
    ilab convert
}

container_workarounds() {
    # TODO: Workarounds for running this inside the instructlab+cuda container

    # TODO: Keep this line until new containers are built that include
    # https://github.com/instructlab/instructlab/pull/988
    test -d taxonomy || git clone https://github.com/instructlab/taxonomy || true
    rm -f config.yaml

    # TODO: Keep this until libcudann8 is installed
    # https://github.com/instructlab/instructlab/pull/1018
    dnf install -y libcudnn8
}

test_exec() {
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

    # TODO: Haven't actually gotten past this point
    if [ "$CI" -eq 1 ]; then
        return
    fi

    # When you run this --
    #   `ilab convert` is only implemented for macOS with M-series chips for now
    #test_convert

    # Kill the serve process
    task Stopping the ilab serve
    step Kill ilab serve $PID
    kill $PID

    # TODO: chat with the new model
    # TODO: Haven't actually gotten here yet: Serve with the new model
    test_serve /tmp/somemodelthatispretrained.gguf
    PID=$!

    # TODO: Haven't actually gotton here yet: chat with the new model
    # TODO: Ask a qestion about softball
    test_chat

    # Kill the serve process
    task Stopping the ilab serve
    step Kill ilab serve $PID
    kill $PID
}

usage() {
    echo "Usage: $0 [-m] [-h]"
    echo "  -m  Run minimal configuration (run quicker when you have no GPU)"
    echo "  -c  Run in CI mode (explicitly skip steps we know will fail in linux CI)"
    echo "  -h  Show this help text"

}

# Process command line arguments
task "Configuring ..."
while getopts "cmh" opt; do
    case $opt in
        c)
            CI=1
            step "Running in CI mode."
            ;;
        m)
            MINIMAL=1
            step "Running minimal configuration."
            ;;
        h)
            usage
            exit 0
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            exit 1
            ;;
    esac
done

set_defaults
test_exec
