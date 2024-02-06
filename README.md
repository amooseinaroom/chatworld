# chatworld
online game to hang out and chat, maybe

# build
This project uses the C like lang compiler as a git submodule.
In order to compile the lang compiler and the project you need to build inside the Visual Studio x64 Command Prompt.
32bit compilation is not supported.

## initial build
1. Checkout the repository with `git clone --recurse-submodules https://github.com/amooseinaroom/chatworld.git`.
2. In Visual Studio x64 Command Prompt run `init_build.bat`.

or

1. Checkout the repository with `git clone --recurse-submodules https://github.com/amooseinaroom/chatworld.git`.
2. Go into the `lang` directory.
3. In Visual Studio x64 Command Prompt run `build_lang.bat`, `build_stb_truetype_lib.bat` and `build_stb_image_lib.bat`.
4. Go back up to the `chatworld` directory.
5. In Visual Studio x64 Command Prompt run `build_embedded_files.bat` to initialize embedded files.
6. In Visual Studio x64 Command Prompt run `build.bat`.

## continuous build
1. In `build.bat` you can enable/disable debugging by setting `set debug=1` or `set debug=0` respectively.
2. This project requires hot realoading building process, so always leave `set hot_code_reloading=1` as is.
3. In `code\build\hot_reloading.t` you can enable/disable hot reloading by setting `override def enable_hot_reloading = true;` or `override def enable_hot_reloading = false;` respectively.
4. In Visual Studio x64 Command Prompt run `build.bat`
