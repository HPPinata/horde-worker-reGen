#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ignore_hordelib=false

# Parse command line arguments
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    --hordelib)
    hordelib=true
    shift # past argument
    ;;
    --scribe)
    scribe=true
    shift
    ;;
    *)    # unknown option
    echo "Unknown option: $key"
    exit 1
    ;;
esac
shift # past argument or value
done

CONDA_ENVIRONMENT_FILE=environment.rocm.yaml

# Determine if the user has a flash attention supported card.
SUPPORTED_CARD=$(rocminfo | grep -c -e gfx1100 -e gfx1101 -e gfx1102)
if [ "$SUPPORTED_CARD" -gt 0 ]; then export FLASH_ATTENTION_TRITON_AMD_ENABLE="${FLASH_ATTENTION_TRITON_AMD_ENABLE:=TRUE}"; fi

wget -qO- https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-linux-64.tar.bz2 | tar -xvj -C "${SCRIPT_DIR}"
if [ ! -f "$SCRIPT_DIR/conda/envs/linux/bin/python" ]; then
    ${SCRIPT_DIR}/bin/micromamba create --no-shortcuts -r "$SCRIPT_DIR/conda" -n linux -f ${CONDA_ENVIRONMENT_FILE} -y
fi
${SCRIPT_DIR}/bin/micromamba create --no-shortcuts -r "$SCRIPT_DIR/conda" -n linux -f ${CONDA_ENVIRONMENT_FILE} -y

if [ "$hordelib" = true ]; then
 ${SCRIPT_DIR}/bin/micromamba run -r "$SCRIPT_DIR/conda" -n linux python -s -m pip uninstall -y hordelib horde_engine horde_sdk horde_model_reference
 ${SCRIPT_DIR}/bin/micromamba run -r "$SCRIPT_DIR/conda" -n linux python -s -m pip install horde_engine horde_model_reference --extra-index-url https://download.pytorch.org/whl/rocm6.2
else
 ${SCRIPT_DIR}/bin/micromamba run -r "$SCRIPT_DIR/conda" -n linux python -s -m pip install -r "$SCRIPT_DIR/requirements.rocm.txt" -U --extra-index-url https://download.pytorch.org/whl/rocm6.2
fi

${SCRIPT_DIR}/bin/micromamba run -r "$SCRIPT_DIR/conda" -n linux python -s -m pip uninstall -y pynvml nvidia-ml-py

# Check if we are running in WSL2
WSL_KERNEL=$(uname -a | grep -c -e WSL2 )
if [ "$WSL_KERNEL" -gt 0 ]; then
    export IN_WSL="TRUE"
    echo "WSL environment detected. Patching ROCm libhsa-runtime64.so"
    for i in $(find ./ -iname libhsa-runtime64.so); do cp /opt/rocm/lib/libhsa-runtime64.so $i; done
fi

${SCRIPT_DIR}/bin/micromamba run -r "$SCRIPT_DIR/conda" -n linux "$SCRIPT_DIR/horde_worker_regen/amd_go_fast/install_amd_go_fast.sh"
