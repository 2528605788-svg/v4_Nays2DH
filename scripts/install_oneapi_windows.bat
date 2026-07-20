@echo off
setlocal

set "ONEAPI_URL=https://registrationcenter-download.intel.com/akdlm/IRC_NAS/2a13d966-fcc5-4a66-9fcc-50603820e0c9/w_HPCKit_p_2023.1.0.46357_offline.exe"
set "ONEAPI_COMPONENT=intel.oneapi.win.ifort-compiler"

if "%~1"=="" (
  set "ONEAPI_INSTALLER=%RUNNER_TEMP%\w_HPCKit_p_2023.1.0.46357_offline.exe"
) else (
  set "ONEAPI_INSTALLER=%~1"
)
set "ONEAPI_EXTRACT=%RUNNER_TEMP%\oneapi-extracted"

if not exist "%ONEAPI_INSTALLER%" (
  curl.exe --fail --location --retry 5 --retry-delay 10 --output "%ONEAPI_INSTALLER%" "%ONEAPI_URL%" || exit /b 1
)

start /wait "" "%ONEAPI_INSTALLER%" -s -x -f "%ONEAPI_EXTRACT%" --log "%RUNNER_TEMP%\oneapi-extract.log"
if errorlevel 1 exit /b %errorlevel%

"%ONEAPI_EXTRACT%\bootstrapper.exe" -s --action install --components=%ONEAPI_COMPONENT% --eula=accept -p=NEED_VS2017_INTEGRATION=0 -p=NEED_VS2019_INTEGRATION=0 -p=NEED_VS2022_INTEGRATION=0 --log-dir="%RUNNER_TEMP%"
exit /b %errorlevel%
