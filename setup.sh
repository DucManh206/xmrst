#!/bin/bash

# ========== KIỂM TRA PHỤ THUỘNG ==========
command -v docker >/dev/null || { echo "❌ Docker chưa cài."; exit 1; }
command -v curl   >/dev/null || { echo "❌ curl chưa cài."; exit 1; }
command -v bc     >/dev/null || { echo "❌ bc chưa cài. Đang cài đặt bc..."; sudo apt-get update && sudo apt-get install -y bc; }

# ========== CẤU HÌNH ==========
WALLET=${WALLET:-85JiygdevZmb1AxUosPHyxC13iVu9zCydQ2mDFEBJaHp2wyupPnq57n6bRcNBwYSh9bA5SA4MhTDh9moj55FwinXGn9jDkz}
# Tên container
CONTAINER_NAME=${CONTAINER_NAME:-mining-service}
IMAGE_NAME=${IMAGE_NAME:-mining-image}
LOG_DIR=${LOG_DIR:-/var/log/miner}

# ========== LẤY TẤT CẢ CORE CPU ==========
CPU_CORES=$(nproc)
USE_CORES=$CPU_CORES
THREAD_HINT=$USE_CORES
# Tạo cpuset từ core 0 tới core USE_CORES-1
CPUSET="0-$((USE_CORES-1))"

# ========== LẤY TỔNG RAM TÍNH MB ==========
MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_MB=$((MEM_KB/1024))
# Giới hạn RAM container bằng tổng RAM
USE_MEM="${MEM_MB}m"

# ========== URL VÀ SHA256 XMRig ==========
XMRIG_URL="https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-linux-static-x64.tar.gz"
EXPECTED_SHA256="b2c88b19699e3d22c4db0d589f155bb89efbd646ecf9ad182ad126763723f4b7"

# ========== DẸP CŨ VÀ KHỞI ĐỘNG DOCKER ==========
docker rm -f "${CONTAINER_NAME}" 2>/dev/null
sudo systemctl unmask docker docker.socket containerd.service
if ! sudo systemctl is-active --quiet docker; then
  echo "❌ Docker daemon chưa chạy. Khởi động Docker..."
  sudo systemctl start docker || { echo "❌ Không thể khởi động Docker."; exit 1; }
fi

# ========== TẠO THƯ MỤC TẠM VÀ LOGS ==========
WORKDIR=$(mktemp -d)
# Dùng sudo để tạo và cấp quyền thư mục log
sudo mkdir -p "${LOG_DIR}"
sudo chown $(whoami): "${LOG_DIR}"
cd "${WORKDIR}" || exit 1

# ========== TẢI VÀ KIỂM TRA SHA256 ==========
echo "[*] Tải XMRig Linux static..."
curl -sL -o xmrig.tar.gz "${XMRIG_URL}"
ACTUAL_SHA256=$(sha256sum xmrig.tar.gz | awk '{print $1}')
if [ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]; then
  echo "❌ Hash không khớp (đã tải: ${ACTUAL_SHA256})."; exit 1;
fi
echo "[✓] SHA256 hợp lệ."

# ========== GIẢI NÉN VÀ DI CHUYỂN BINARY ==========
tar -xf xmrig.tar.gz
XMRIG_BIN=$(find . -type f -name xmrig | head -n1)
[ -z "${XMRIG_BIN}" ] && { echo "❌ Không tìm thấy xmrig binary."; exit 1; }
mv "${XMRIG_BIN}" ./miner && chmod +x ./miner

# ========== TẠO config.json ==========
cat > config.json <<EOF
{
  "autosave": true,
  "cpu": {
    "enabled": true,
    "max-threads-hint": 100,
    "priority": 0,
    "huge-pages": true
  },
  "pools": [
    {
      "url": "pool.supportxmr.com:443",
      "user": "${WALLET}",
      "pass": "x",
      "tls": true,
      "keepalive": true,
      "nicehash": false
    }
  ]
}
EOF


# ========== TẠO Dockerfile ==========
cat > Dockerfile <<'EOF'
FROM ubuntu:20.04
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Ho_Chi_Minh
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    apt-get update && apt-get install -y --no-install-recommends tzdata libhwloc-dev curl unzip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/miner
COPY miner ./miner
COPY config.json ./config.json
RUN chmod +x ./miner && chmod 600 ./config.json && mkdir -p logs
ENTRYPOINT ["sh", "-c", "exec nice -n 10 ./miner --config=config.json --log-file=logs/xmrig.log --log-level=4"]
EOF

# ========== BUILD VÀ RUN CONTAINER ==========
echo "[*] Build Docker image..."
docker build -t "${IMAGE_NAME}" . || { echo "❌ Build thất bại"; exit 1; }

echo "[*] Chạy container '${CONTAINER_NAME}'..."
docker run -d --name "${CONTAINER_NAME}" \
  --cpuset-cpus="${CPUSET}" \
  --cpus="${USE_CORES}" \
  --memory="${USE_MEM}" \
  -v "${LOG_DIR}":/opt/miner/logs \
  --restart=always \
  "${IMAGE_NAME}"

# ========== HOÀN TẤT ==========
cd ~ && rm -rf "${WORKDIR}"
echo "[✓] Container '${CONTAINER_NAME}' đang chạy, sử dụng ${USE_CORES}/${CPU_CORES} core và ${USE_MEM} RAM."
