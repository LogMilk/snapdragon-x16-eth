package com.logmilk.lteswitch;

import android.content.Context;
import android.content.res.AssetManager;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.InputStream;

/** Extracts the bundled qmi toolchain + script into the app's private dir. */
public class Extract {
    public static File dir(Context c) { return c.getFilesDir(); }
    public static String ctl(Context c) { return new File(c.getFilesDir(), "lte-ctl.sh").getAbsolutePath(); }

    public static synchronized boolean ensure(Context c) {
        File d = c.getFilesDir();
        int ver = 0;
        try { ver = c.getPackageManager().getPackageInfo(c.getPackageName(), 0).versionCode; } catch (Exception e) { }
        File mark = new File(d, ".ver");

        boolean ok = new File(d, "lte-ctl.sh").exists() && new File(d, "qmicli").exists();
        if (ok) {
            try {
                BufferedReader r = new BufferedReader(new FileReader(mark));
                String v = r.readLine();
                r.close();
                if (!String.valueOf(ver).equals(v)) ok = false;
            } catch (Exception e) { ok = false; }
        }
        if (!ok) {
            File[] fs = d.listFiles();
            if (fs != null) for (File f : fs) if (!"tile.log".equals(f.getName())) f.delete();
            try { copy(c, "qmi"); copy(c, "lte"); }
            catch (Exception e) { return false; }
            try {
                Runtime.getRuntime().exec(new String[]{"/system/bin/su", "-c",
                        "chmod 755 " + d.getAbsolutePath() + "/*"}).waitFor();
            } catch (Exception e) { }
            try { FileWriter w = new FileWriter(mark); w.write(String.valueOf(ver)); w.close(); } catch (Exception e) { }
        }
        return new File(d, "lte-ctl.sh").exists();
    }

    private static void copy(Context c, String sub) throws Exception {
        AssetManager am = c.getAssets();
        String[] files = am.list(sub);
        if (files == null) return;
        for (String f : files) {
            InputStream in = am.open(sub + "/" + f);
            File out = new File(c.getFilesDir(), f);
            FileOutputStream os = new FileOutputStream(out);
            byte[] b = new byte[65536];
            int n;
            while ((n = in.read(b)) > 0) os.write(b, 0, n);
            os.close(); in.close();
            out.setExecutable(true, false);
            out.setReadable(true, false);
        }
    }
}
