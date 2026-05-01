{
  config,
  pkgs,
  username,
  ...
}:

{
  launchd.agents.claude-insights = {
    enable = true;
    config = {
      Label = "com.claude.insights-monthly";
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          set -u
          REPORT="/Users/${username}/.claude/usage-data/report.html"
          DATED="/Users/${username}/.claude/usage-data/report-$(date +%Y%m%d).html"

          echo "===== $(date) /insights run ====="

          /Users/${username}/.local/bin/claude -p "Run the /insights slash command to generate this month's shareable usage insights report. Do not ask clarifying questions; just execute the command and report the output file path." || {
            echo "ERROR: claude /insights invocation failed"
            exit 1
          }

          # Only snapshot if report.html was regenerated in the last 15 minutes
          if [ -f "$REPORT" ] && [ -n "$(find "$REPORT" -mmin -15 -print 2>/dev/null)" ]; then
            cp "$REPORT" "$DATED"
            echo "Saved snapshot: $DATED"
          else
            echo "ERROR: report.html was not regenerated within the last 15 minutes"
            exit 1
          fi
        ''
      ];
      StartCalendarInterval = [
        {
          Day = 1;
          Hour = 10;
          Minute = 0;
        }
      ];
      StandardOutPath = "/Users/${username}/.claude/usage-data/insights-latest.log";
      StandardErrorPath = "/Users/${username}/.claude/usage-data/insights-latest.log";
    };
  };
}
