#!/bin/bash
# G9 Sports Daily Automation Cron Setup
# Run this on the VPS: bash bin/setup_cron.sh
# Makes the script executable: chmod +x bin/setup_cron.sh

set -e

echo "🚀 G9 Sports Cron Setup"
echo "======================="
echo ""

# Determine the docker container name
echo "Finding gate9_sports container..."
CONTAINER=$(docker ps --filter "name=gate9" --format "{{.Names}}" 2>/dev/null | head -1)

if [ -z "$CONTAINER" ]; then
  echo "❌ Error: No gate9 container found"
  echo "Make sure the container is running: docker ps"
  exit 1
fi

echo "✓ Found container: $CONTAINER"
echo ""

# Create temporary cron file with G9 Sports jobs
cat > /tmp/g9_cron << 'CRON'
# ============================================================
# G9 Sports Daily Pipeline (Gate9 Sports Automation)
# All times in UTC. VPS timezone reference:
# UTC 20:00 = KST 05:00 (next day) = ET 15:00 (prev day)
# UTC 21:00 = KST 06:00 (next day) = ET 16:00 (prev day)
# UTC 08:00 = KST 17:00 (same day) = ET 03:00 (same day)
# ============================================================

# 1. NBA Data Fetch - 20:00 UTC (05:00 KST next day)
# Fetches schedule, odds, injuries, lineups, calculates edge
0 20 * * * docker exec CONTAINER_NAME bin/rails nba:fetch_all >> /var/log/g9_data.log 2>&1

# 2. LLM Report Generation - 21:00 UTC (06:00 KST next day)
# Generates Claude-powered analysis reports for today's games
0 21 * * * docker exec CONTAINER_NAME bin/rails report:daily_llm >> /var/log/g9_reports.log 2>&1

# 3. Result Recording - 08:00 UTC (17:00 KST same day)
# Records game results after NBA games end (~04:00 UTC games end)
0 8 * * * docker exec CONTAINER_NAME bin/rails report:record_results >> /var/log/g9_results.log 2>&1

# 4. Weekly Stats Update - Sunday 10:00 UTC (18:00 KST)
# Aggregates weekly performance statistics
0 10 * * 0 docker exec CONTAINER_NAME bin/rails report:stats >> /var/log/g9_stats.log 2>&1

# ============================================================
CRON

# Replace placeholder with actual container name
sed -i "s/CONTAINER_NAME/$CONTAINER/g" /tmp/g9_cron

echo "📋 Cron entries to be installed:"
echo "---"
grep -v "^#" /tmp/g9_cron | grep -v "^$" || true
echo "---"
echo ""

# Backup existing crontab and merge with G9 jobs
echo "Installing cron jobs..."
{
  # Get existing crontab, filter out G9 entries (avoid duplicates)
  crontab -l 2>/dev/null | grep -v "G9 Sports" | grep -v "g9_" | grep -v "^#.*Gate9" || true
  # Add G9 jobs
  cat /tmp/g9_cron
} | crontab -

# Verify installation
echo "✓ Cron jobs installed"
echo ""
echo "Current G9 Sports cron jobs:"
echo "---"
crontab -l 2>/dev/null | grep -E "nba:|report:" || echo "(none)"
echo "---"
echo ""

echo "📊 Log files location:"
echo "  /var/log/g9_data.log      - NBA data fetch"
echo "  /var/log/g9_reports.log   - LLM report generation"
echo "  /var/log/g9_results.log   - Result recording"
echo "  /var/log/g9_stats.log     - Weekly stats"
echo ""

echo "🔍 To monitor logs in real-time:"
echo "  tail -f /var/log/g9_data.log"
echo ""

echo "📝 To edit cron jobs:"
echo "  crontab -e"
echo ""

echo "✅ Setup complete!"
