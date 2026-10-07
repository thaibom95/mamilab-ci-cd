#!/usr/bin/env bash
# ============================================================
# MamiLab — Script khôi phục Database SQLite từ bản sao lưu
#
# Cách dùng trên VPS:
#   bash /var/www/mamilab/scripts/restore-db.sh
# hoặc truyền đường dẫn file:
#   bash /var/www/mamilab/scripts/restore-db.sh /var/www/mamilab/backups/sqlite/db_20261007_pre-d1c277d.sqlite.gz
# ============================================================

set -euo pipefail

BACKUP_DIR="/var/www/mamilab/backups/sqlite"
TARGET_DB="/var/www/mamilab/backend/database/database.sqlite"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ Thư mục backup không tồn tại: $BACKUP_DIR"
    exit 1
fi

FILE="${1:-}"

if [ -z "$FILE" ]; then
    echo "=== Danh sách 10 bản sao lưu gần nhất ==="
    mapfile -t BACKUPS < <(ls -1t "$BACKUP_DIR"/*.sqlite.gz 2>/dev/null | head -n 10)
    
    if [ ${#BACKUPS[@]} -eq 0 ]; then
        echo "Không có bản backup nào trong $BACKUP_DIR"
        exit 1
    fi

    for i in "${!BACKUPS[@]}"; do
        printf "[%d] %s (%s)\n" "$((i + 1))" "$(basename "${BACKUPS[$i]}")" "$(du -h "${BACKUPS[$i]}" | cut -f1)"
    done

    read -rp "Chọn số thứ tự bản sao lưu muốn khôi phục [1-${#BACKUPS[@]}]: " CHOICE
    if [[ ! "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "${#BACKUPS[@]}" ]; then
        echo "Lựa chọn không hợp lệ."
        exit 1
    fi
    FILE="${BACKUPS[$((CHOICE - 1))]}"
fi

if [ ! -f "$FILE" ]; then
    echo "❌ File backup không tồn tại: $FILE"
    exit 1
fi

echo ">> Đang chuẩn bị khôi phục từ: $FILE"
read -rp "⚠️ Hành động này sẽ ghi đè database hiện tại! Bạn có chắc chắn? (y/N): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Đã hủy thao tác."
    exit 0
fi

# Tạm thời backup DB hiện tại trước khi ghi đè
SAFETY_BACKUP="$BACKUP_DIR/db_safety_before_restore_$(date +%Y%m%d_%H%M%S).sqlite"
if [ -f "$TARGET_DB" ]; then
    cp "$TARGET_DB" "$SAFETY_BACKUP"
    gzip -f "$SAFETY_BACKUP"
    echo "✓ Đã tạo bản phòng hộ an toàn: ${SAFETY_BACKUP}.gz"
fi

# Khôi phục file
gunzip -c "$FILE" > "$TARGET_DB.tmp"
mv "$TARGET_DB.tmp" "$TARGET_DB"

# Cấp quyền
chown www-data:www-data "$TARGET_DB"
chmod 775 "$TARGET_DB"

# Re-cache / restart queue
if docker ps --format '{{.Names}}' | grep -qx "mamilab-backend"; then
    docker exec -T mamilab-backend php artisan queue:restart
fi

echo "✅ Khôi phục Database SQLite thành công!"
