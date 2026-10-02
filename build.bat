@echo off
setlocal
set JAVA_HOME=C:\Program Files\Java\jdk-17
set PATH=C:\Program Files\Java\jdk-17\bin;%PATH%
set BT=C:\Users\19114\Desktop\Tools\.android-sdk\build-tools\34.0.0
set AJ=C:\Users\19114\Desktop\Tools\.android-sdk\platforms\android-35\android.jar
set P=C:\Users\19114\AppData\Local\Temp\commandcode\--wsl-localhost-Ubuntu-home-logmilk-projects\e52217a9-ba7f-423f-9616-95bed422173f\scratchpad\ltesolo
rmdir /s /q "%P%\out" 2>nul
mkdir "%P%\out"
echo == aapt2 compile ==
"%BT%\aapt2.exe" compile --dir "%P%\res" -o "%P%\out\res.zip" || goto :err
echo == aapt2 link (with assets) ==
"%BT%\aapt2.exe" link -o "%P%\out\app.unaligned.apk" -I "%AJ%" --manifest "%P%\AndroidManifest.xml" "%P%\out\res.zip" --min-sdk-version 30 --target-sdk-version 33 --java "%P%\out\gen" || goto :err
echo == javac ==
javac --release 8 -Xlint:-options -encoding UTF-8 -cp "%AJ%" -d "%P%\out\classes" "%P%\src\com\ltegopher\ltesolo\Extract.java" "%P%\src\com\ltegopher\ltesolo\LteTile.java" "%P%\src\com\ltegopher\ltesolo\MainActivity.java" "%P%\out\gen\com\ltegopher\ltesolo\R.java" || goto :err
echo == jar ==
jar cf "%P%\out\classes.jar" -C "%P%\out\classes" . || goto :err
echo == d8 ==
call "%BT%\d8.bat" --lib "%AJ%" --min-api 30 --output "%P%\out" "%P%\out\classes.jar" || goto :err
echo == add dex + assets ==
cd /d "%P%\out"
jar uf app.unaligned.apk classes.dex || goto :err
jar uf app.unaligned.apk -C "%P%" assets || goto :err
echo == key ==
if not exist "%P%\app.keystore" keytool -genkeypair -keystore "%P%\app.keystore" -alias a -keyalg RSA -keysize 2048 -validity 10000 -storepass android -keypass android -dname "CN=lte,O=x,C=CN"
echo == zipalign + sign ==
call "%BT%\zipalign.exe" -f 4 app.unaligned.apk app.aligned.apk || goto :err
call "%BT%\apksigner.bat" sign --ks "%P%\app.keystore" --ks-pass pass:android --key-pass pass:android --out "%P%\ltesolo.apk" app.aligned.apk || goto :err
echo == done ==
dir "%P%\ltesolo.apk"
exit /b 0
:err
echo FAILED
exit /b 1
