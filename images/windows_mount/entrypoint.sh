#!/bin/sh
set -e

: "${SSH_USER:?Missing SSH_USER}"
: "${SSH_HOST:?Missing SSH_HOST}"
: "${SSH_PATH:?Missing SSH_PATH}"

MOUNT_POINT=/mnt/workdir
echo "${SSH_HOST}"
echo "${SSH_USER}"
echo "${SSH_PATH}"

mkdir -p "$MOUNT_POINT"
sshfs -o allow_other,default_permissions,IdentityFile=/key/deep \
      -o StrictHostKeyChecking=no \
      -o reconnect \
      -o ServerAliveInterval=15 \
      -o ServerAliveCountMax=3 \
    ${SSH_USER}@${SSH_HOST}:${SSH_PATH} /mnt/workdir

rsync -rtuav --exclude 'workspace' \
          --exclude '_internal/CUDA' \
          --exclude '_internal/CUDNN' \
          --exclude "_internal/VSCode" \
          --exclude "facelib" \
          --exclude "_internal/XnViewMP" \
          --exclude "_internal/_e" \
          --exclude "_internal/pretrain_Quick96" \
          --exclude "_internal/pretrain_faces" \
          --exclude "_internal/model_generic_xseg" \
          /mnt/workdir/DeepFaceLab_NVIDIA_RTX3000_series /mnt/shared

while inotifywait  -e modify,create,delete,move "/mnt/shared/DeepFaceLab_NVIDIA_RTX3000_series"; do
    rsync -rtuavz -O --delete --exclude 'workspace' \
              --exclude '_internal/CUDA' \
              --exclude '_internal/CUDNN' \
              --exclude "_internal/VSCode" \
              --exclude "facelib" \
              --exclude "_internal/XnViewMP" \
              --exclude "_internal/_e" \
              --exclude "_internal/pretrain_Quick96" \
              --exclude "_internal/pretrain_faces" \
              --exclude "_internal/model_generic_xseg" \
              /mnt/shared/DeepFaceLab_NVIDIA_RTX3000_series /mnt/workdir
done

echo "SSHFS mounted at $MOUNT_POINT"

# Keep container alive
exec cat 
