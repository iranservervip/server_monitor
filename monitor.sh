#!/bin/bash

# --- توابع کمکی ---
jsonify_array() {
    echo -n "$1" | sed 's/^", "//' | sed 's/, $//'
}

bytes_to_gb() {
    awk -v val="$1" 'BEGIN {printf "%.2f", val / 1024 / 1024 / 1024}'
}

get_service_status() {
    if systemctl is-active --quiet "$1"; then
        echo "active"
    elif systemctl is-failed --quiet "$1"; then
        echo "failed"
    else
        if systemctl list-unit-files "$1.service" > /dev/null 2>&1; then
             echo "inactive"
        else
             echo "not_installed"
        fi
    fi
}

echo "{"

# ===========================
# 1. سیستم و شبکه
# ===========================
HOSTNAME=$(hostname)
KERNEL=$(uname -r)
if [ -f /etc/os-release ]; then
    OS=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
else
    OS=$(cat /etc/issue | head -n 1)
fi
IPV4=$(hostname -I | awk '{print $1}')
IPV6=$(ip -6 addr show scope global | grep inet6 | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
UPTIME=$(uptime -p)

echo "  \"system_info\": {"
echo "    \"hostname\": \"$HOSTNAME\","
echo "    \"kernel\": \"$KERNEL\","
echo "    \"os\": \"$OS\","
echo "    \"ipv4\": \"$IPV4\","
echo "    \"ipv6\": \"$IPV6\","
echo "    \"uptime\": \"$UPTIME\""
echo "  },"

# ===========================
# 2. منابع سرور
# ===========================
read RAM_TOTAL RAM_USED RAM_FREE RAM_AVAILABLE <<< $(free -m | awk '/Mem:/ {print $2, $3, $4, $7}')
CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')
CPU_CORES=$(nproc)
LOAD_AVG=$(uptime | awk -F'load average:' '{ print $2 }' | sed 's/,//g' | xargs)

DISK_JSON=""
while read -r line; do
    MOUNT=$(echo $line | awk '{print $7}')
    TYPE=$(echo $line | awk '{print $2}')
    SIZE=$(echo $line | awk '{print $3}')
    USED=$(echo $line | awk '{print $4}')
    AVAIL=$(echo $line | awk '{print $5}')
    PERCENT=$(echo $line | awk '{print $6}')
    DISK_JSON+="{\"mount\": \"$MOUNT\", \"type\": \"$TYPE\", \"total\": \"$SIZE\", \"used\": \"$USED\", \"free\": \"$AVAIL\", \"usage_percent\": \"$PERCENT\"}, "
done < <(df -hT -x tmpfs -x devtmpfs -x overlay -x squashfs | grep -v "Filesystem")
DISK_JSON=$(echo "$DISK_JSON" | sed 's/, $//')

read RX_BYTES TX_BYTES <<< $(awk '/:/ {if ($1 != "lo:") {rx+=$2; tx+=$10}} END {print rx, tx}' /proc/net/dev)
RX_GB=$(bytes_to_gb $RX_BYTES)
TX_GB=$(bytes_to_gb $TX_BYTES)

echo "  \"resource_usage\": {"
echo "    \"cpu\": {"
echo "      \"model\": \"$CPU_MODEL\","
echo "      \"cores\": $CPU_CORES,"
echo "      \"load_average\": \"$LOAD_AVG\""
echo "    },"
echo "    \"ram_mb\": {"
echo "      \"total\": $RAM_TOTAL,"
echo "      \"used\": $RAM_USED,"
echo "      \"available\": $RAM_AVAILABLE"
echo "    },"
echo "    \"disks\": [$DISK_JSON],"
echo "    \"traffic_gb\": {"
echo "      \"rx\": \"$RX_GB\","
echo "      \"tx\": \"$TX_GB\""
echo "    }"
echo "  },"

# ===========================
# 3. کنترل پنل
# ===========================
PANEL="None"
if [ -d "/usr/local/cpanel" ]; then PANEL="cPanel"; fi
if [ -d "/usr/local/directadmin" ]; then PANEL="DirectAdmin"; fi
if [ -d "/www/server/panel" ]; then PANEL="aaPanel"; fi
echo "  \"control_panel\": \"$PANEL\","

# ===========================
# 4. سرویس‌ها
# ===========================
WEBSERVER_NAME="None"
WEBSERVER_STATUS="not_installed"

if systemctl list-unit-files | grep -q lsws; then 
    WEBSERVER_NAME="LiteSpeed"
    WEBSERVER_STATUS=$(get_service_status lsws)
elif systemctl list-unit-files | grep -q nginx; then 
    WEBSERVER_NAME="Nginx"
    WEBSERVER_STATUS=$(get_service_status nginx)
elif systemctl list-unit-files | grep -q httpd; then 
    WEBSERVER_NAME="Apache (httpd)"
    WEBSERVER_STATUS=$(get_service_status httpd)
elif systemctl list-unit-files | grep -q apache2; then 
    WEBSERVER_NAME="Apache (apache2)"
    WEBSERVER_STATUS=$(get_service_status apache2)
fi

DB_NAME="none"
DB_STATUS="not_installed"
if systemctl list-unit-files | grep -q mysqld; then DB_NAME="mysqld"; DB_STATUS=$(get_service_status mysqld);
elif systemctl list-unit-files | grep -q mariadb; then DB_NAME="mariadb"; DB_STATUS=$(get_service_status mariadb);
elif systemctl list-unit-files | grep -q mysql; then DB_NAME="mysql"; DB_STATUS=$(get_service_status mysql);
fi

EXIM_STATUS=$(get_service_status exim)
DOVECOT_STATUS=$(get_service_status dovecot)

PHP_VERSIONS="[]"
PHP_DIRS=$(ls -d /usr/local/php* 2>/dev/null | xargs -n 1 basename | sed 's/php//g' | sort -u | paste -sd "," - | sed 's/,/", "/g')
if [ ! -z "$PHP_DIRS" ]; then PHP_VERSIONS="[\"$PHP_DIRS\"]"; fi

echo "  \"services\": {"
echo "    \"webserver\": { \"name\": \"$WEBSERVER_NAME\", \"status\": \"$WEBSERVER_STATUS\" },"
echo "    \"database\": { \"name\": \"$DB_NAME\", \"status\": \"$DB_STATUS\" },"
echo "    \"mail\": { \"exim\": \"$EXIM_STATUS\", \"dovecot\": \"$DOVECOT_STATUS\" },"
echo "    \"php_versions\": $PHP_VERSIONS"
echo "  },"

# ===========================
# 5. تحلیل لاگ‌های امنیتی (اصلاح شده)
# ===========================
# تعیین فایل لاگ بر اساس اولویت
AUTH_LOG=""
if [ -f "/var/log/auth.log" ]; then
    AUTH_LOG="/var/log/auth.log" # Debian/Ubuntu Standard
elif [ -f "/var/log/secure" ]; then
    AUTH_LOG="/var/log/secure"   # RHEL/CentOS Standard
elif [ -f "/var/log/audit/audit.log" ]; then
    AUTH_LOG="/var/log/audit/audit.log" # Audit Log
elif [ -f "/var/log/syslog" ]; then
    AUTH_LOG="/var/log/syslog"   # Fallback
elif [ -f "/var/log/messages" ]; then
    AUTH_LOG="/var/log/messages" # Fallback
fi

AUTH_FAIL_COUNT=0
TOP_ATTACKER_IP="None"
TOP_FAILED_SERVICE="None"

if [ ! -z "$AUTH_LOG" ]; then
    # شمارش کل خطاها
    AUTH_FAIL_COUNT=$(grep -ciE "failed|failure|auth.*fail" "$AUTH_LOG")

    if [ "$AUTH_FAIL_COUNT" -gt 0 ]; then
        # دریافت تمام آی‌پی‌های سرور برای نادیده گرفتن آنها در لیست مهاجمین
        # این کار باعث می‌شود IP خود سرور (lip) به عنوان مهاجم شناخته نشود
        LOCAL_IPS=$(hostname -I | sed 's/ /|/g')
        if [ -z "$LOCAL_IPS" ]; then LOCAL_IPS="127.0.0.1"; fi
        
        # استخراج آی‌پی‌ها و حذف آی‌پی‌های لوکال
        # دستور grep -vE "$LOCAL_IPS" آی‌پی‌های خود سرور را از نتایج حذف می‌کند
        TOP_ATTACKER_IP=$(grep -iE "failed|failure|auth.*fail" "$AUTH_LOG" | \
            grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | \
            grep -vE "^($LOCAL_IPS|127\.0\.0\.1)$" | \
            sort | uniq -c | sort -nr | head -n 1 | awk '{print $2 " (" $1 " attempts)"}')
        
        # استخراج نام سرویس (Dovecot, SSH, etc)
        TOP_FAILED_SERVICE=$(grep -iE "failed|failure|auth.*fail" "$AUTH_LOG" | \
            awk '{for(i=1;i<=NF;i++) if($i ~ /\[[0-9]+\]:/) print $i}' | \
            cut -d'[' -f1 | sort | uniq -c | sort -nr | head -n 1 | awk '{print $2 " (" $1 " attempts)"}')
            
        # تلاش دوم برای سرویس‌هایی که فرمت PID ندارند
        if [ -z "$TOP_FAILED_SERVICE" ]; then
             TOP_FAILED_SERVICE=$(grep -iE "failed|failure|auth.*fail" "$AUTH_LOG" | awk '{print $5}' | cut -d'[' -f1 | cut -d':' -f1 | sort | uniq -c | sort -nr | head -n 1 | awk '{print $2 " (" $1 " attempts)"}')
        fi
    fi
fi

# هندل کردن مقادیر خالی
[ -z "$TOP_ATTACKER_IP" ] && TOP_ATTACKER_IP="None"
[ -z "$TOP_FAILED_SERVICE" ] && TOP_FAILED_SERVICE="None"
[ -z "$AUTH_LOG" ] && AUTH_LOG="Not Found"

echo "  \"security_analysis\": {"
echo "    \"log_file\": \"$AUTH_LOG\","
echo "    \"total_auth_failures\": $AUTH_FAIL_COUNT,"
echo "    \"top_attacker_ip\": \"$TOP_ATTACKER_IP\","
echo "    \"most_targeted_service\": \"$TOP_FAILED_SERVICE\""
echo "  },"

# ===========================
# 6. تحلیل خطاهای وب
# ===========================
WEB_LOG_DIR=""
if [ -d "/var/log/httpd/domains" ]; then WEB_LOG_DIR="/var/log/httpd/domains";
elif [ -d "/var/log/nginx/domains" ]; then WEB_LOG_DIR="/var/log/nginx/domains";
elif [ -d "/www/wwwlogs" ]; then WEB_LOG_DIR="/www/wwwlogs";
elif [ -d "/var/log/apache2" ]; then WEB_LOG_DIR="/var/log/apache2";
elif [ -d "/var/log/httpd" ]; then WEB_LOG_DIR="/var/log/httpd";
elif [ -d "/var/log/nginx" ]; then WEB_LOG_DIR="/var/log/nginx";
fi

WEB_ERRORS_JSON="[]"
if [ ! -z "$WEB_LOG_DIR" ] && [ -d "$WEB_LOG_DIR" ]; then
    COMMON_ERRORS=$(find "$WEB_LOG_DIR" -maxdepth 2 -type f -name "*error.log*" -mtime -7 -print0 | xargs -0 tail -n 200 2>/dev/null | grep -i "error" | \
    sed -E 's/^\[[^]]+\] //g' | sed -E 's/^[0-9\/ :.-]+ \[error\] //g' | sed -E 's/client [0-9.]+//g' | \
    sort | uniq -c | sort -nr | head -n 5)
    
    if [ ! -z "$COMMON_ERRORS" ]; then
        WEB_ERRORS_JSON=$(echo "$COMMON_ERRORS" | awk '{ $1=""; print substr($0,2) }' | sed 's/"/\\"/g' | awk '{printf "\"%s\", ", $0}' | sed 's/, $//')
        WEB_ERRORS_JSON="[$WEB_ERRORS_JSON]"
    fi
fi

echo "  \"web_server_analysis\": {"
echo "    \"scanned_directory\": \"$WEB_LOG_DIR\","
echo "    \"common_errors_summary\": $WEB_ERRORS_JSON"
echo "  },"

# ===========================
# 7. داکر
# ===========================
DOCKER_INSTALLED="no"
CONTAINERS="[]"
if command -v docker &> /dev/null; then
    DOCKER_INSTALLED="yes"
    CONTAINER_LIST=$(docker ps --format '{{.Names}} ({{.Image}})' | paste -sd "," - | sed 's/,/", "/g')
    if [ ! -z "$CONTAINER_LIST" ]; then CONTAINERS="[\"$CONTAINER_LIST\"]"; fi
fi

echo "  \"docker\": {"
echo "    \"installed\": \"$DOCKER_INSTALLED\","
echo "    \"running_containers\": $CONTAINERS"
echo "  },"

# ===========================
# 8. پورت‌ها و یوزرها
# ===========================
PORTS=$(ss -tuln | awk 'NR>1 {print $5}' | awk -F: '{print $NF}' | sort -u | paste -sd "," - | sed 's/,/", "/g')
USER_COUNT=$(find /home -maxdepth 1 -mindepth 1 -type d | wc -l)

echo "  \"network_security\": {"
echo "    \"open_ports\": [\"$PORTS\"],"
echo "    \"home_users_count\": $USER_COUNT"
echo "  },"

# ===========================
# 9. بکاپ و وردپرس
# ===========================
BACKUP_CRONS=$(grep -r "backup" /var/spool/cron/ /etc/cron* 2>/dev/null | grep -v "^#" | head -n 5)
CRON_JSON="[]"
if [ ! -z "$BACKUP_CRONS" ]; then
    CLEAN_CRONS=$(echo "$BACKUP_CRONS" | sed 's/"/\\"/g' | awk '{printf "\"%s\", ", $0}' | sed 's/, $//')
    CRON_JSON="[$CLEAN_CRONS]"
fi

WP_PATHS=$(find /home -maxdepth 6 -name "wp-config.php" 2>/dev/null | grep -v "wp-content" | grep -v "plugins" | head -n 20)
WP_JSON="[]"
if [ ! -z "$WP_PATHS" ]; then
    CLEAN_WP=$(echo "$WP_PATHS" | awk '{printf "\"%s\", ", $0}' | sed 's/, $//')
    WP_JSON="[$CLEAN_WP]"
fi

echo "  \"backup_info\": { \"crons\": $CRON_JSON },"
echo "  \"wordpress_sites\": $WP_JSON"

echo "}"
