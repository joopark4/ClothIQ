#!/bin/zsh

# ClothIQ Log Collection Script
# 디바이스에서 최근 로그를 수집하여 파일로 저장

DEVICE_ID="00008027-001A65243499802E"
OUTPUT_DIR="../Reference"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$OUTPUT_DIR/device_log_$TIMESTAMP.txt"

echo "📋 Collecting logs from device..."
echo "Output: $LOG_FILE"

log show --device "$DEVICE_ID" \
  --predicate 'subsystem == "com.eunyeon.ClothIQ"' \
  --last 5m \
  --info > "$LOG_FILE"

echo "✅ Logs collected: $(wc -l < "$LOG_FILE") lines"
echo ""
echo "Key metrics:"
grep -E "(ClothingType|측정|confidence|좌표)" "$LOG_FILE" | tail -20
