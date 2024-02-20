@echo off

set destination=deploy\

xcopy /Y assets\fonts\stanberry\Stanberry.ttf %destination%assets\fonts\stanberry\Stanberry.ttf
xcopy /Y customization\character_template.png %destination%customization\character_template.png
xcopy /Y chatworld.exe        %destination%chatworld.exe
xcopy /Y server_chatworld.exe %destination%server_chatworld.exe