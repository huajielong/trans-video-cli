@echo off
rem Cross-platform launcher for trans_video_cli (Windows).
rem Usage: trans.cmd selftest
rem        trans.cmd vtv movie.mp4 --source zh-cn --target en
python "%~dp0.claude\skills\trans-video-cli\scripts\trans_cli.py" %*
