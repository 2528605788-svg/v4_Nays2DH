@echo off
setlocal

for /f "usebackq tokens=*" %%I in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS2022INSTALLDIR=%%I"
if not defined VS2022INSTALLDIR exit /b 1
call "%VS2022INSTALLDIR%\Common7\Tools\VsDevCmd.bat" -arch=amd64 -host_arch=amd64 || exit /b 1
call "C:\Program Files (x86)\Intel\oneAPI\setvars.bat" intel64 --force || exit /b 1
where ifort || exit /b 1

ifort .\.baseline\src\iric.f90 /Qopenmp /nostandard-realloc-lhs /MD /c /object:baseline_iric.obj || exit /b 1
ifort .\.baseline\src\Nays2DH.f90 /Qopenmp /nostandard-realloc-lhs /MD /c /object:baseline_Nays2DH.obj || exit /b 1
ifort baseline_iric.obj baseline_Nays2DH.obj .\.baseline\lib\iriclib.lib -o Nays2DHBaseline.exe || exit /b 1

if not exist diagnostic mkdir diagnostic
copy /y Nays2DHBaseline.exe diagnostic\Nays2DHBaseline.exe || exit /b 1
del /q baseline_*.obj *.mod 2>nul
