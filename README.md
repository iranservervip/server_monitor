# 📊 Linux Server Monitoring & Security Analyzer

A comprehensive, lightweight Bash script designed to monitor Linux server health, resource usage, and security status. It outputs all data in a clean **JSON format**, making it perfect for integration with custom dashboards, monitoring agents, or remote management tools.

## 🚀 Key Features

### 1. 🛡️ Security & Log Analysis (New)
* **Brute-Force Detection:** Scans authentication logs (`auth.log`, `secure`, `audit.log`, or `syslog`) to count failed login attempts.
* **Top Attacker Identification:** Identifies the IP address with the most failed attempts, automatically excluding the server's own local IPs to prevent false positives.
* **Targeted Service Analysis:** Detects which service is under attack (e.g., `sshd`, `dovecot`, `ftpd`).
* **Web Server Error Parsing:** Intelligent scanning of Nginx/Apache/LiteSpeed error logs. It retrieves the most common recent errors (last 7 days) to help diagnose website issues quickly.

### 2. 🖥️ System & Resources
* **OS Info:** Hostname, Kernel version, OS distribution, Uptime.
* **Network:** Public IPv4/IPv6 detection.
* **CPU & RAM:** Model, Cores, Load Average, Memory usage (Total/Used/Available).
* **Disk Usage:** JSON-formatted list of all physical partitions with usage percentages.
* **Traffic:** Network traffic (RX/TX) calculated in GB since the last boot.

### 3. ⚙️ Services & Software
* **Service Status:** precise detection of `Active`, `Failed`, `Inactive`, or `Not Installed` for:
    * **Web Servers:** LiteSpeed, Nginx, Apache (httpd/apache2).
    * **Databases:** MySQL, MariaDB, Percona.
    * **Mail:** Exim, Dovecot.
* **PHP Versions:** Detects installed PHP versions.
* **Control Panel:** Auto-detects cPanel, DirectAdmin, or aaPanel.
* **Docker:** Checks if Docker is installed and lists running containers.

### 4. 🔍 Auditing
* **Open Ports:** Lists all listening TCP/UDP ports.
* **User Count:** Counts users with home directories.
* **Backup Detection:** Scans Cron jobs for backup-related tasks.
* **WordPress:** Detects WordPress installations by scanning for `wp-config.php`.

---

## 📋 Prerequisites

* **Root Privileges:** The script requires `root` or `sudo` access to read system logs (`/var/log/*`) for security analysis.
* **Dependencies:** Standard Linux utilities (`awk`, `sed`, `grep`, `curl`, `systemctl`, `free`, `df`, `ss`). No heavy external packages required.

---

## 📥 Installation & Usage

1.  **Download the script:**
    ```bash
    curl -fsSL https://raw.githubusercontent.com/iranservervip/server_monitor/main/monitor.sh \
| bash \
| curl -X POST \
    -H "Content-Type: application/json" \
    -d @- \
    http://IP_MONITORING_SERVER/api/report/
    ```

2.  **Make it executable:**
    ```bash
    chmod +x monitor.sh
    ```

3.  **Run it:**
    ```bash
    sudo ./monitor.sh
    ```

    *Note: Using `sudo` is highly recommended to populate the "Security Analysis" and "Web Server Analysis" sections correctly.*

4.  **Pipe to a file (Optional):**
    ```bash
    sudo ./monitor.sh > server_status.json
    ```

---

## 📝 Output Example

The script generates a JSON object like this:

```json
{
  "system_info": {
    "hostname": "server.example.com",
    "os": "Ubuntu 22.04.3 LTS",
    "uptime": "up 3 weeks, 2 days"
  },
  "resource_usage": {
    "cpu": { "load_average": "0.45, 0.60, 0.55" },
    "ram_mb": { "total": 16000, "used": 4500, "available": 11500 },
    "traffic_gb": { "rx": "120.50", "tx": "85.20" }
  },
  "services": {
    "webserver": { "name": "Nginx", "status": "active" },
    "database": { "name": "mariadb", "status": "active" }
  },
  "security_analysis": {
    "log_file": "/var/log/auth.log",
    "total_auth_failures": 145,
    "top_attacker_ip": "192.168.1.50 (42 attempts)",
    "most_targeted_service": "sshd (140 attempts)"
  },
  "web_server_analysis": {
    "common_errors_summary": [
      "PHP Fatal error: Uncaught TypeError...",
      "client denied by server configuration..."
    ]
  }
}
