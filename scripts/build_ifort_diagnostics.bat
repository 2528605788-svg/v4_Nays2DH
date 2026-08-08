@echo off
setlocal

for /f "usebackq tokens=*" %%I in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS2022INSTALLDIR=%%I"
if not defined VS2022INSTALLDIR exit /b 1
call "%VS2022INSTALLDIR%\Common7\Tools\VsDevCmd.bat" -arch=amd64 -host_arch=amd64 || exit /b 1
call "C:\Program Files (x86)\Intel\oneAPI\setvars.bat" intel64 --force || exit /b 1
where ifort || exit /b 1

if not exist diagnostic-dynamic mkdir diagnostic-dynamic
ifort .\src\iric.f90 /Qopenmp /nostandard-realloc-lhs /MD /Od /check:bounds /traceback /fpe:0 /Qinit:snan /c /object:dynamic_snan_iric.obj || exit /b 1
ifort .\src\vegetation_dynamic.f90 /Qopenmp /nostandard-realloc-lhs /MD /Od /check:bounds /traceback /fpe:0 /Qinit:snan /c /object:dynamic_snan_vegetation.obj || exit /b 1
ifort .\src\Nays2DH.f90 /Qopenmp /nostandard-realloc-lhs /MD /Od /check:bounds /traceback /fpe:0 /Qinit:snan /c /object:dynamic_snan_Nays2DH.obj || exit /b 1
ifort dynamic_snan_iric.obj dynamic_snan_vegetation.obj dynamic_snan_Nays2DH.obj .\lib\iriclib.lib /traceback /fpe:0 -o diagnostic-dynamic\Nays2DHDynamicSnan.exe || exit /b 1
del /q dynamic_snan_*.obj *.mod 2>nul

endlocal
