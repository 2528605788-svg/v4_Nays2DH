@echo off
setlocal

call "C:\Program Files (x86)\Intel\oneAPI\setvars-vcvarsall.bat" vs2022 || exit /b 1

ifx .\src\iric.f90 /Qopenmp /assume:norealloc_lhs /MD /c /object:iric.obj || exit /b 1
ifx .\src\vegetation_dynamic.f90 /Qopenmp /assume:norealloc_lhs /MD /c /object:vegetation_dynamic.obj || exit /b 1
ifx .\src\Nays2DH.f90 /Qopenmp /assume:norealloc_lhs /MD /c /object:Nays2DH.obj || exit /b 1
ifx iric.obj vegetation_dynamic.obj Nays2DH.obj .\lib\iriclib.lib /Qopenmp /MD /Fe:Nays2DH.exe || exit /b 1

copy /y .\Nays2DH.exe .\install\Nays2DH.exe || exit /b 1
del /q *.obj *.mod 2>nul

endlocal
