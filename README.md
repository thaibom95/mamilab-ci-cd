# MamiLab CI/CD Infrastructure

> Hệ thống tự động kiểm thử và triển khai (CI/CD) cho dự án **MamiLab**.  
> Được thiết kế theo mô hình tách biệt Repository tương tự `momlingo-ci-cd`.

---

## 1. Kiến trúc Hệ thống

```
┌────────────────────────────────────────┐
│  MamiLab Source Repo (Private)         │
│  github.com/thaibom95/mamilab          │
└──────────────────┬─────────────────────┘
                   │
                   │ Push/Merge vào `main`
                   ▼
┌────────────────────────────────────────┐
│  Trigger Deploy Workflow (~10 giây)     │
│  Gửi repository_dispatch qua GitHub API│
└──────────────────┬─────────────────────┘
                   │
                   │ Trigger
                   ▼
┌────────────────────────────────────────┐
│  MamiLab CI/CD Repo (Public Runner)    │
│  github.com/thaibom95/mamilab-ci-cd    │
│                                        │
│  1. Backup DB trên VPS trước deploy    │
│  2. Build Frontend (Next.js export)    │
│  3. Đóng gói mã nguồn release          │
│  4. SSH & SCP cập nhật lên VPS         │
│  5. Migrate DB & Clear/Warmup Caches   │
│  6. Restart Worker & Reload Nginx      │
│  7. Kiểm tra sức khỏe hệ thống         │
└──────────────────┬─────────────────────┘
                   │
                   │ SSH / SCP (Port 24700)
                   ▼
┌────────────────────────────────────────┐
│  MamiLab Production VPS (iNet)         │
│  IP: 103.166.182.62                    │
│  /var/www/mamilab                      │
│  Containers: backend, nginx, gotenberg │
└────────────────────────────────────────┘
```

---

## 2. Quy trình Phát triển & Triển khai (Git Flow)

* **Nhánh `dev`:**
  * Lập trình viên code các tính năng mới và push lên nhánh `dev`.
  * Mỗi lần push lên `dev` hoặc mở Pull Request vào `main`, workflow `ci.yml` sẽ tự động chạy:
    * Kiểm tra PHP Unit Test: `php artisan test`
    * Kiểm tra TypeScript: `pnpm run typecheck`
    * Kiểm tra Frontend Vitest: `pnpm test`
    * Kiểm tra build Next.js: `pnpm run build`
* **Nhánh `main`:**
  * Khi merge PR từ `dev` vào `main`, workflow `trigger-deploy.yml` tự động kích hoạt tiến trình triển khai trên repo này (`mamilab-ci-cd`).
  * Hệ thống tự động sao lưu Database, đóng gói phiên bản mới và cập nhật lên máy chủ VPS mà không làm gián đoạn người dùng.

---

## 3. Danh sách GitHub Secrets cần thiết lập

### A. Thiết lập trong repo nguồn `mamilab`:
Vào `github.com/thaibom95/mamilab` ➜ **Settings** ➜ **Secrets and variables** ➜ **Actions**:

| Tên Secret | Ý nghĩa | Cách lấy |
| :--- | :--- | :--- |
| `CI_TOKEN` | GitHub Personal Access Token (PAT) để kích hoạt deploy | Tạo PAT tại GitHub Settings ➜ Developer settings ➜ Personal access tokens (Tokens classic) với quyền `public_repo` hoặc `repo`. |

---

### B. Thiết lập trong repo CI/CD `mamilab-ci-cd`:
Vào `github.com/thaibom95/mamilab-ci-cd` ➜ **Settings** ➜ **Secrets and variables** ➜ **Actions**:

| Tên Secret | Ý nghĩa | Giá trị mẫu |
| :--- | :--- | :--- |
| `MAMILAB_SOURCE_TOKEN` | GitHub PAT để clone repo private `mamilab` | Dùng chung token PAT ở trên (cần quyền `repo`). |
| `MAMILAB_VPS_HOST` | Địa chỉ IP máy chủ VPS | `103.166.182.62` |
| `MAMILAB_VPS_PORT` | Cổng kết nối SSH máy chủ | `24700` |
| `MAMILAB_VPS_USER` | Tên tài khoản SSH máy chủ | `root` |
| `MAMILAB_VPS_SSH_KEY` | Khóa SSH bí mật (Private Key) kết nối VPS | Toàn bộ nội dung file `~/.ssh/id_ed25519` trên máy local. |

---

## 4. Cơ chế Sao lưu & Phục hồi Khẩn cấp (Rollback)

Trước mỗi lần triển khai, hệ thống sẽ tự động tạo một bản dump SQLite tại:
```bash
/var/www/mamilab/backups/sqlite/db_<timestamp>_pre-<commit-sha>.sqlite.gz
```
Hệ thống tự động lưu trữ **30 bản sao lưu gần nhất**.

Nếu phát sinh sự cố sau khi deploy, có thể khôi phục lại dữ liệu ngay lập tức bằng lệnh:
```bash
bash /var/www/mamilab/scripts/restore-db.sh
```
Script sẽ hiển thị danh sách các bản backup gần nhất để lựa chọn và khôi phục chỉ sau 2 giây.
