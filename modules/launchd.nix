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
          /Users/${username}/.local/bin/claude insights && \
          cp /Users/${username}/.claude/usage-data/report.html \
             /Users/${username}/.claude/usage-data/report-$(date +%Y%m%d).html
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
