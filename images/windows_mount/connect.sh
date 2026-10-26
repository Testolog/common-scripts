docker run -it \
  -v ~/projects/deep_fake:/mnt/shared \
  -v ~/.ssh/deep:/key/deep \
  -v ~/.config/nvim:/root/.config/nvim \
  --device /dev/fuse \
  --privileged \
  --cap-add SYS_ADMIN \
  -e SSH_USER=testolog \
  -e SSH_HOST=100.120.251.44 \
  -e SSH_PATH="D:\\" \
  windows_mount 
