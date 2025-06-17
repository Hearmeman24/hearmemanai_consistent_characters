#!/usr/bin/env bash

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

pip install insightface==0.7.3 &
pip install facexlib &
pip install onnxruntime-gpu &
pip install timm &
pip install onnxruntime &


# Set the network volume path
NETWORK_VOLUME="/workspace"

# This is in case there's any special installs or overrides that needs to occur when starting the machine before starting ComfyUI
if [ -f "/workspace/additional_params.sh" ]; then
    chmod +x /workspace/additional_params.sh
    echo "Executing additional_params.sh..."
    /workspace/additional_params.sh
else
    echo "additional_params.sh not found in /workspace. Skipping..."
fi

if ! which aria2 > /dev/null 2>&1; then
    echo "Installing aria2..."
    apt-get update && apt-get install -y aria2
else
    echo "aria2 is already installed"
fi

# Check if NETWORK_VOLUME exists; if not, use root directory instead
if [ ! -d "$NETWORK_VOLUME" ]; then
    echo "NETWORK_VOLUME directory '$NETWORK_VOLUME' does not exist. You are NOT using a network volume. Setting NETWORK_VOLUME to '/' (root directory)."
    NETWORK_VOLUME="/"
    echo "NETWORK_VOLUME directory doesn't exist. Starting JupyterLab on root directory..."
    jupyter-lab --ip=0.0.0.0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True --notebook-dir=/ &
else
    echo "NETWORK_VOLUME directory exists. Starting JupyterLab..."
    jupyter-lab --ip=0.0.0.0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True --notebook-dir=/workspace &
fi

COMFYUI_DIR="$NETWORK_VOLUME/ComfyUI"
WORKFLOW_DIR="$NETWORK_VOLUME/ComfyUI/user/default/workflows"
MODEL_WHITELIST_DIR="$NETWORK_VOLUME/ComfyUI/user/default/ComfyUI-Impact-Subpack/model-whitelist.txt"
DIFFUSION_MODELS_DIR="$NETWORK_VOLUME/ComfyUI/models/diffusion_models"
TEXT_ENCODERS_DIR="$NETWORK_VOLUME/ComfyUI/models/text_encoders"
VAE_DIR="$NETWORK_VOLUME/ComfyUI/models/vae"
INSIGHTFACE_DIR="$NETWORK_VOLUME/ComfyUI/models/insightface/models"
PULID_DIR="$NETWORK_VOLUME/ComfyUI/models/pulid"
CONTROLNET_DIR="$NETWORK_VOLUME/ComfyUI/models/controlnet"

if [ ! -d "$COMFYUI_DIR" ]; then
    mv /ComfyUI "$COMFYUI_DIR"
else
    echo "Directory already exists, skipping move."
fi

echo "Downloading CivitAI download script to /usr/local/bin"
git clone "https://github.com/Hearmeman24/CivitAI_Downloader.git" || { echo "Git clone failed"; exit 1; }
mv CivitAI_Downloader/download_with_aria.py "/usr/local/bin/" || { echo "Move failed"; exit 1; }
chmod +x "/usr/local/bin/download_with_aria.py" || { echo "Chmod failed"; exit 1; }
rm -rf CivitAI_Downloader  # Clean up the cloned repo

download_model() {
    local url="$1"
    local full_path="$2"

    local destination_dir=$(dirname "$full_path")
    local destination_file=$(basename "$full_path")

    mkdir -p "$destination_dir"

    # Simple corruption check: file < 10MB or .aria2 files
    if [ -f "$full_path" ]; then
        local size_bytes=$(stat -f%z "$full_path" 2>/dev/null || stat -c%s "$full_path" 2>/dev/null || echo 0)
        local size_mb=$((size_bytes / 1024 / 1024))

        if [ "$size_bytes" -lt 10485760 ]; then  # Less than 10MB
            echo "🗑️  Deleting corrupted file (${size_mb}MB < 10MB): $full_path"
            rm -f "$full_path"
        else
            echo "✅ $destination_file already exists (${size_mb}MB), skipping download."
            return 0
        fi
    fi

    # Check for and remove .aria2 control files
    if [ -f "${full_path}.aria2" ]; then
        echo "🗑️  Deleting .aria2 control file: ${full_path}.aria2"
        rm -f "${full_path}.aria2"
        rm -f "$full_path"  # Also remove any partial file
    fi

    echo "📥 Downloading $destination_file to $destination_dir..."

    # Download without falloc (since it's not supported in your environment)
    aria2c -x 16 -s 16 -k 1M --continue=true -d "$destination_dir" -o "$destination_file" "$url" &

    echo "Download started in background for $destination_file"
}

if [ "$download_flux" == "true" ]; then
  download_model "https://huggingface.co/lllyasviel/flux1_dev/resolve/main/flux1-dev-fp8.safetensors" "$DIFFUSION_MODELS_DIR/flux1-dev-fp8.safetensors"
  download_model "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors" "$TEXT_ENCODERS_DIR/clip_l.safetensors"
  download_model "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn_scaled.safetensors" "$TEXT_ENCODERS_DIR/t5xxl_fp8_e4m3fn_scaled.safetensors"
  download_model "https://huggingface.co/realung/flux1-dev.safetensors/resolve/main/ae.safetensors" "$VAE_DIR/ae.safetensors"
  download_model "https://huggingface.co/guozinan/PuLID/resolve/main/pulid_flux_v0.9.1.safetensors" "$PULID_DIR/pulid_flux_v0.9.1.safetensors"
  download_model "https://huggingface.co/Shakker-Labs/FLUX.1-dev-ControlNet-Union-Pro-2.0/resolve/main/diffusion_pytorch_model.safetensors" "$CONTROLNET_DIR/flux_union_controlnet_2.0.safetensors"
fi

if [ "$download_sdxl" == "true" ]; then
  # Define target directories
  IPADAPTER_DIR="$NETWORK_VOLUME/ComfyUI/models/ipadapter"
  CLIPVISION_DIR="$NETWORK_VOLUME/ComfyUI/models/clip_vision"

  # Create directories if they don't exist
  mkdir -p "$IPADAPTER_DIR"
  mkdir -p "$CLIPVISION_DIR"

  # Download IP-Adapter files
  echo "📥 Starting IP-Adapter downloads..."
  download_model "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus-face_sdxl_vit-h.safetensors" "$IPADAPTER_DIR/ip-adapter-plus-face_sdxl_vit-h.safetensors"
  download_model "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors" "$IPADAPTER_DIR/ip-adapter-plus_sdxl_vit-h.safetensors"
  download_model "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter_sdxl_vit-h.safetensors" "$IPADAPTER_DIR/ip-adapter_sdxl_vit-h.safetensors"
  download_model "https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl.bin" "$IPADAPTER_DIR/ip-adapter-faceid-plusv2_sdxl.bin"
  download_model "https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl_lora.safetensors" "$NETWORK_VOLUME/ComfyUI/models/loras/ip-adapter-faceid-plusv2_sdxl_lora.safetensors"

  # Download CLIP Vision files
  echo "📥 Starting CLIP Vision downloads..."
  download_model "https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors" "$CLIPVISION_DIR/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors"
  download_model "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/image_encoder/model.safetensors" "$CLIPVISION_DIR/CLIP-ViT-bigG-14-laion2B-39B-b160k.safetensors"

  # Download FaceID LoRA
  echo "📥 Starting ControlNet download..."
  download_model "https://huggingface.co/thibaud/controlnet-openpose-sdxl-1.0/resolve/main/OpenPoseXL2.safetensors" "$CONTROLNET_DIR/OpenPoseXL2.safetensors"
  download_model "https://huggingface.co/SargeZT/controlnet-sd-xl-1.0-depth-16bit-zoe/resolve/main/depth-zoe-xl-v1.0-controlnet.safetensors" "$CONTROLNET_DIR/depth-zoe-xl-v1.0-controlnet.safetensors"
fi

# Download additional models
echo "📥 Starting additional model downloads..."

# Download upscale model
download_model "https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth" "$NETWORK_VOLUME/ComfyUI/models/upscale_models/4x_foolhardy_Remacri.pt"

# Download face segmentation model
download_model "https://huggingface.co/24xx/segm/resolve/main/face_yolov8m-seg_60.pt" "$NETWORK_VOLUME/ComfyUI/models/ultralytics/segm/face_yolov8m-seg_60.pt"

# Download SAM model
download_model "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/sams/sam_vit_b_01ec64.pth" "$NETWORK_VOLUME/ComfyUI/models/sams/sam_vit_b_01ec64.pth"

mkdir -p "$NETWORK_VOLUME/ComfyUI/models/ultralytics/bbox"
if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/ultralytics/bbox/Eyes.pt" ]; then
    if [ -f "/Eyes.pt" ]; then
        mv "/Eyes.pt" "$NETWORK_VOLUME/ComfyUI/models/ultralytics/bbox/Eyes.pt"
        echo "Moved Eyes.pt to the correct location."
    else
        echo "Eyes.pt not found in the root directory."
    fi
else
    echo "Eyes.pt already exists. Skipping."
fi
if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/upscale_models/4xLSDIR.pth" ]; then
    if [ -f "/4xLSDIR.pth" ]; then
        mv "/4xLSDIR.pth" "$NETWORK_VOLUME/ComfyUI/models/upscale_models/4xLSDIR.pth"
        echo "Moved 4xLSDIR.pth to the correct location."
    else
        echo "4xLSDIR.pth not found in the root directory."
    fi
else
    echo "4xLSDIR.pth already exists. Skipping."
fi

if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/upscale_models/4xFaceUpDAT.pth" ]; then
    if [ -f "/4xFaceUpDAT.pth" ]; then
        cd "$NETWORK_VOLUME/ComfyUI/models/upscale_models/4xFaceUpDAT.pth"
        wget "https://huggingface.co/RafaG/models-ESRGAN/resolve/82caaaedb2d27e9f76472351828178b62995c2f1/4xFaceUpLDAT.pth"
        echo "Downloaded 4xFaceUpDAT.pth to the correct location."
        cd /
    else
        echo "4xFaceUpDAT.pth not found in the root directory."
    fi
else
    echo "4xFaceUpDAT.pth already exists. Skipping."
fi

echo "Finished downloading models!"

declare -A MODEL_CATEGORIES=(
    ["$NETWORK_VOLUME/ComfyUI/models/checkpoints"]="$CHECKPOINT_IDS_TO_DOWNLOAD"
    ["$NETWORK_VOLUME/ComfyUI/models/loras"]="$LORAS_IDS_TO_DOWNLOAD"
)

# Counter to track background jobs
download_count=0

# Ensure directories exist and schedule downloads in background
for TARGET_DIR in "${!MODEL_CATEGORIES[@]}"; do
    mkdir -p "$TARGET_DIR"
    IFS=',' read -ra MODEL_IDS <<< "${MODEL_CATEGORIES[$TARGET_DIR]}"

    for MODEL_ID in "${MODEL_IDS[@]}"; do
        sleep 6
        echo "🚀 Scheduling download: $MODEL_ID to $TARGET_DIR"
        (cd "$TARGET_DIR" && download_with_aria.py -m "$MODEL_ID") &
        ((download_count++))
    done
done

echo "📋 Scheduled $download_count downloads in background"

# Wait for all downloads to complete
echo "⏳ Waiting for downloads to complete..."
while pgrep -x "aria2c" > /dev/null; do
    echo "🔽 Downloads still in progress..."
    sleep 5  # Check every 5 seconds
done

echo "✅ All models downloaded successfully!"

echo "Checking and copying workflow..."
mkdir -p "$WORKFLOW_DIR"

# Ensure the file exists in the current directory before moving it
cd /

SOURCE_DIR="/hearmemanai_consistent_characters/workflows"

# Ensure destination directory exists
mkdir -p "$WORKFLOW_DIR"

# Loop over each file in the source directory
for file in "$SOURCE_DIR"/*; do
    # Skip if it's not a file
    [[ -f "$file" ]] || continue

    dest_file="$WORKFLOW_DIR/$(basename "$file")"

    if [[ -e "$dest_file" ]]; then
        echo "File already exists in destination. Deleting: $file"
        rm -f "$file"
    else
        echo "Moving: $file to $WORKFLOW_DIR"
        mv "$file" "$WORKFLOW_DIR"
    fi
done

# Workspace as main working directory
echo "cd $NETWORK_VOLUME" >> ~/.bashrc


echo "Updating default preview method..."
CONFIG_PATH="$NETWORK_VOLUME/ComfyUI/user/default/ComfyUI-Manager"
CONFIG_FILE="$CONFIG_PATH/config.ini"

# Ensure the directory exists
mkdir -p "$CONFIG_PATH"

# Create the config file if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating config.ini..."
    cat <<EOL > "$CONFIG_FILE"
[default]
preview_method = auto
git_exe =
use_uv = False
channel_url = https://raw.githubusercontent.com/ltdrdata/ComfyUI-Manager/main
share_option = all
bypass_ssl = False
file_logging = True
component_policy = workflow
update_policy = stable-comfyui
windows_selector_event_loop_policy = False
model_download_by_agent = False
downgrade_blacklist =
security_level = normal
skip_migration_check = False
always_lazy_install = False
network_mode = public
db_mode = cache
EOL
else
    echo "config.ini already exists. Updating preview_method..."
    sed -i 's/^preview_method = .*/preview_method = auto/' "$CONFIG_FILE"
fi
echo "Config file setup complete!"
echo "Default preview method updated to 'auto'"

echo "Downloading AntelopeV2"
mkdir -p INSIGHTFACE_DIR
cd INSIGHTFACE_DIR
wget https://github.com/deepinsight/insightface/releases/download/v0.7/antelopev2.zip
python3 -c "
import zipfile
import os
with zipfile.ZipFile('antelopev2.zip', 'r') as zip_ref:
    for member in zip_ref.infolist():
        if not member.is_dir():
            member.filename = os.path.basename(member.filename)
            zip_ref.extract(member, '.')
"
mkdir INSIGHTFACE_DIR/antelopev2
mv *.onnx INSIGHTFACE_DIR/antelopev2

URL="http://127.0.0.1:8188"
echo "Starting ComfyUI"
nohup python3 "$NETWORK_VOLUME/ComfyUI/main.py" --listen > "$NETWORK_VOLUME/comfyui_${RUNPOD_POD_ID}_nohup.log" 2>&1 &
until curl --silent --fail "$URL" --output /dev/null; do
  echo "🔄  ComfyUI Starting Up... You can view the startup logs here: $NETWORK_VOLUME/comfyui_${RUNPOD_POD_ID}_nohup.log"
  sleep 2
done
echo "ComfyUI is UP, overriding model whitelist..."
cat > $NETWORK_VOLUME/ComfyUI/user/default/ComfyUI-Impact-Subpack/model-whitelist.txt << 'EOF'
Eyes.pt
face_yolov8m-seg_60.pt
person_yolov8m-seg.pt
EOF
echo "🚀 ComfyUI is ready"
sleep infinity

