@echo off
setlocal

set "ONEAPI_URL=https://registrationcenter-download.intel.com/akdlm/IRC_NAS/0d500705-397e-41b3-8b2b-2a3da1753fc2/w_HPCKit_p_2024.2.0.633_offline.exe"
set "ONEAPI_COMPONENT=intel.oneapi.win.ifort-compiler"

if "%~1"=="" (
  set "ONEAPI_INSTALLER=%RUNNER_TEMP%\w_HPCKit_p_2024.2.0.633_offline.exe"
) else (
  set "ONEAPI_INSTALLER=%~1"
)
set "ONEAPI_EXTRACT=%RUNNER_TEMP%\oneapi-extracted"

if not exist "%ONEAPI_INSTALLER%" (
  curl.exe --fail --location --retry 5 --retry-delay 10 --output "%ONEAPI_INSTALLER%" "%ONEAPI_URL%" || exit /b 1
)

start /wait "" "%ONEAPI_INSTALLER%" -s -x -f "%ONEAPI_EXTRACT%" --log "%RUNNER_TEMP%\oneapi-extract.log"
if errorlevel 1 exit /b %errorlevel%

"%ONEAPI_EXTRACT%\bootstrapper.exe" -s --action install --components=%ONEAPI_COMPONENT% --eula=accept --continue-with-optional-error=yes -p=NEED_VS2022_INTEGRATION=0 --log-dir="%RUNNER_TEMP%"
exit /b %errorlevel%
