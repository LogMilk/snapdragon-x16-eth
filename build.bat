@echo off
setlocal

rem =====================================================================
rem  LTE Switch - standalone build (Android SDK build-tools, no Gradle)
rem
rem  Run build.bat from anywhere; it locates the project by its own path
rem  and writes the result to lteswitch.apk in the project root.
rem
rem  Requirements: JDK 11+ and Android SDK build-tools.
rem  Everything is auto-detected; override with environment variables:
rem    ANDROID_SDK / ANDROID_HOME / ANDROID_SDK_ROOT  SDK location
rem    BUILD_TOOLS     build-tools version, e.g. 34.0.0 (default: newest)
rem    ANDROID_JAR     explicit ...\platforms\android-XX\android.jar
rem    JAVA_HOME       JDK 11+ (default: javac/java on PATH)
rem    KEYSTORE KS_PASS KEY_ALIAS KEY_PASS   signing config
rem    MIN_SDK TARGET_SDK                    default 30 / 33
rem =====================================================================

rem ---- project root = this script's directory ----
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
if not exist "%ROOT%\AndroidManifest.xml" (
  echo ERROR: AndroidManifest.xml not found next to build.bat.
  exit /b 1
)
set "OUT=%ROOT%\out"

rem ---- Java ----
if defined JAVA_HOME if exist "%JAVA_HOME%\bin\javac.exe" set "PATH=%JAVA_HOME%\bin;%PATH%"
where javac >nul 2>nul || (
  echo ERROR: javac not found. Install a JDK ^(11+^) or set JAVA_HOME.
  exit /b 1
)

rem ---- Android SDK ----
set "SDK="
if defined ANDROID_SDK      set "SDK=%ANDROID_SDK%"
if not defined SDK if defined ANDROID_HOME     set "SDK=%ANDROID_HOME%"
if not defined SDK if defined ANDROID_SDK_ROOT set "SDK=%ANDROID_SDK_ROOT%"
if not defined SDK for %%d in (
  "%LOCALAPPDATA%\Android\Sdk"
  "%USERPROFILE%\AppData\Local\Android\Sdk"
  "%USERPROFILE%\Android\Sdk"
  "%ProgramFiles%\Android\Sdk"
) do if not defined SDK if exist "%%~d\platforms" set "SDK=%%~d"
if not defined SDK (
  echo ERROR: Android SDK not found. Set ANDROID_HOME to your SDK path.
  exit /b 1
)

rem ---- build-tools (newest unless BUILD_TOOLS is set) ----
set "BT="
if defined BUILD_TOOLS (
  set "BT=%SDK%\build-tools\%BUILD_TOOLS%"
) else (
  for /f "delims=" %%v in ('dir /b /ad /o-n "%SDK%\build-tools" 2^>nul') do if not defined BT set "BT=%SDK%\build-tools\%%v"
)
if not defined BT (
  echo ERROR: build-tools not found under "%SDK%\build-tools".
  exit /b 1
)
if not exist "%BT%\aapt2.exe" (
  echo ERROR: aapt2.exe not found in "%BT%".
  exit /b 1
)

rem ---- android.jar (newest platform unless ANDROID_JAR is set) ----
set "AJ=%ANDROID_JAR%"
if not defined AJ for /f "delims=" %%p in ('dir /b /ad /o-n "%SDK%\platforms" 2^>nul') do (
  if not defined AJ if exist "%SDK%\platforms\%%p\android.jar" set "AJ=%SDK%\platforms\%%p\android.jar"
)
if not defined AJ (
  echo ERROR: android.jar not found under "%SDK%\platforms".
  exit /b 1
)

if not defined MIN_SDK    set "MIN_SDK=30"
if not defined TARGET_SDK set "TARGET_SDK=33"

echo SDK         : %SDK%
echo build-tools : %BT%
echo android.jar : %AJ%
javac -version

rem ---- clean output ----
if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%OUT%"

echo == aapt2 compile ==
"%BT%\aapt2.exe" compile --dir "%ROOT%\res" -o "%OUT%\res.zip" || goto :err

echo == aapt2 link (with assets) ==
"%BT%\aapt2.exe" link -o "%OUT%\app.unaligned.apk" -I "%AJ%" --manifest "%ROOT%\AndroidManifest.xml" "%OUT%\res.zip" --min-sdk-version %MIN_SDK% --target-sdk-version %TARGET_SDK% --java "%OUT%\gen" || goto :err

echo == javac ==
javac --release 8 -Xlint:-options -encoding UTF-8 -cp "%AJ%" -d "%OUT%\classes" ^
  "%ROOT%\src\com\logmilk\lteswitch\Extract.java" ^
  "%ROOT%\src\com\logmilk\lteswitch\LteTile.java" ^
  "%ROOT%\src\com\logmilk\lteswitch\MainActivity.java" ^
  "%OUT%\gen\com\logmilk\lteswitch\R.java" || goto :err

echo == jar ==
jar cf "%OUT%\classes.jar" -C "%OUT%\classes" . || goto :err

echo == d8 ==
call "%BT%\d8.bat" --lib "%AJ%" --min-api %MIN_SDK% --output "%OUT%" "%OUT%\classes.jar" || goto :err

echo == add dex + assets ==
cd /d "%OUT%"
jar uf app.unaligned.apk classes.dex || goto :err
jar uf app.unaligned.apk -C "%ROOT%" assets || goto :err

echo == key ==
set "KS=%ROOT%\app.keystore"
if defined KEYSTORE set "KS=%KEYSTORE%"
set "KSP=android"
if defined KS_PASS set "KSP=%KS_PASS%"
set "KA=a"
if defined KEY_ALIAS set "KA=%KEY_ALIAS%"
set "KP=android"
if defined KEY_PASS set "KP=%KEY_PASS%"
if not exist "%KS%" keytool -genkeypair -keystore "%KS%" -alias "%KA%" -keyalg RSA -keysize 2048 -validity 10000 -storepass "%KSP%" -keypass "%KP%" -dname "CN=lte,O=x,C=CN"

echo == zipalign + sign ==
call "%BT%\zipalign.exe" -f 4 app.unaligned.apk app.aligned.apk || goto :err
call "%BT%\apksigner.bat" sign --ks "%KS%" --ks-pass "pass:%KSP%" --key-pass "pass:%KP%" --out "%ROOT%\lteswitch.apk" app.aligned.apk || goto :err

echo == done ==
dir "%ROOT%\lteswitch.apk"
exit /b 0

:err
echo FAILED
exit /b 1
