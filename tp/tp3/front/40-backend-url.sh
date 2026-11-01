#!/bin/sh
set -eu
cat > /usr/share/nginx/html/assets/config.js <<EOF
window.dynamicConf = {
  BACKEND_URL: "${BACKEND_URL}"
};
EOF