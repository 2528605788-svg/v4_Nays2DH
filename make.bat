@echo off
setlocal

for /f "usebackq tokens=*" %%I in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS2022INSTALLDIR=%%I"
if not defined VS2022INSTALLDIR exit /b 1
call "C:\Program Files (x86)\Intel\oneAPI\setvars.bat" intel64 vs2022 --force || exit /b 1
where ifx || exit /b 1

ifx .\src\iric.f90 /Qopenmp /assume:norealloc_lhs /MD /c /object:iric.obj || exit /b 1
ifx .\src\vegetation_dynamic.f90 /Qopenmp /assume:norealloc_lhs /MD /c /object:vegetation_dynamic.obj || exit /b 1
ifx .\src\Nays2DH.f90 /Qopenmp /assume:norealloc_lhs /MD /c /object:Nays2DH.obj || exit /b 1
ifx iric.obj vegetation_dynamic.obj Nays2DH.obj .\lib\iriclib.lib /Qopenmp /MD /Fe:Nays2DH.exe || exit /b 1

copy /y .\Nays2DH.exe .\install\Nays2DH.exe || exit /b 1
del /q *.obj *.mod 2>nul

endlocal
