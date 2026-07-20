@echo off
setlocal

for /f "usebackq tokens=*" %%I in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS2022INSTALLDIR=%%I"
if not defined VS2022INSTALLDIR exit /b 1
call "C:\Program Files (x86)\Intel\oneAPI\setvars.bat" intel64 vs2022 --force || exit /b 1
where ifx || exit /b 1

set "DIAGNOSTIC_FLAGS=/Od /check:bounds /traceback /fpe:0"
ifx .\.baseline\src\iric.f90 /Qopenmp /assume:norealloc_lhs /MD %DIAGNOSTIC_FLAGS% /c /object:baseline_iric.obj || exit /b 1
ifx .\.baseline\src\Nays2DH.f90 /Qopenmp /assume:norealloc_lhs /MD %DIAGNOSTIC_FLAGS% /c /object:baseline_Nays2DH.obj || exit /b 1
ifx baseline_iric.obj baseline_Nays2DH.obj .\.baseline\lib\iriclib.lib /Qopenmp /MD %DIAGNOSTIC_FLAGS% /Fe:Nays2DHBaseline.exe || exit /b 1

if not exist diagnostic mkdir diagnostic
copy /y .\Nays2DHBaseline.exe .\diagnostic\Nays2DHBaseline.exe || exit /b 1
del /q baseline_*.obj *.mod 2>nul

endlocal
