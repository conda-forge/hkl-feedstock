@echo off
REM Thin wrapper that hands off to recipe/build.sh, invoked under
REM MSYS2 bash + clang-on-Windows from the autotools_clang_conda
REM build-prefix package. See:
REM   https://github.com/conda-forge/autotools_clang_conda-feedstock
REM for how this works.
call %BUILD_PREFIX%\Library\bin\run_autotools_clang_conda_build.bat
if errorlevel 1 exit 1
