@echo off

set destination=deploy\

rem update version
git rev-parse HEAD > git_commit_id_current.txt

xcopy /Y assets\fonts\stanberry\Stanberry.ttf %destination%assets\fonts\stanberry\Stanberry.ttf
xcopy /Y customization\character_template.png %destination%customization\character_template.png
xcopy /Y chatworld.exe        %destination%chatworld.exe
xcopy /Y server_chatworld.exe %destination%server_chatworld.exe
xcopy /Y git_commit_id_current.txt %destination%git_commit_id_version.txt
