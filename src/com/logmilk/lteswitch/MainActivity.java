package com.logmilk.lteswitch;

import android.app.Activity;
import android.content.SharedPreferences;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.InputType;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.HashMap;
import java.util.Map;

/** Info/control screen. Localized (default English, zh-rCN translated). */
public class MainActivity extends Activity {
    private final Map<String, TextView> rows = new HashMap<String, TextView>();
    private EditText etApn;
    private Switch swValidate, swLte;
    private TextView tvSignal, tvTitle;
    private SharedPreferences prefs;
    private volatile boolean busy = false;

    private int c(String name, int fb) {
        int id = getResources().getIdentifier(name, "attr", "android");
        if (id == 0) return fb;
        TypedValue tv = new TypedValue();
        if (getTheme().resolveAttribute(id, tv, true)) {
            if (tv.type >= TypedValue.TYPE_FIRST_COLOR_INT && tv.type <= TypedValue.TYPE_LAST_COLOR_INT) return tv.data;
            if (tv.resourceId != 0) { try { return getColor(tv.resourceId); } catch (Exception e) { } }
        }
        return fb;
    }
    private int onPrimary() { return c("colorOnPrimary", 0xFFFFFFFF); }
    private int surface()   { return c("colorSurface", c("colorBackground", 0xFF121318)); }
    private int onSurface() { return c("colorOnSurface", c("colorForeground", 0xFFE6E8EE)); }
    private int onSurfaceV(){ return c("colorOnSurfaceVariant", 0xFF8B93A7); }
    private int outline()   { return c("colorOutline", 0xFF3A3F4B); }
    private int tonal()     { return c("colorSecondaryContainer", 0xFF2A2F3A); }
    private int onTonal()   { return c("colorOnSecondaryContainer", onSurface()); }

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        prefs = getSharedPreferences("lte", MODE_PRIVATE);
        setContentView(build());
        refresh();
    }

    private View build() {
        ScrollView sc = new ScrollView(this);
        sc.setBackgroundColor(surface());
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int p = dp(20);
        root.setPadding(p, dp(24), p, dp(24));
        sc.addView(root);

        tvTitle = new TextView(this);
        tvTitle.setText(R.string.title_idle);
        tvTitle.setTextSize(24); tvTitle.setTextColor(onSurface()); tvTitle.setTypeface(null, 1);
        root.addView(tvTitle);
        TextView sub = new TextView(this);
        sub.setText(R.string.subtitle);
        sub.setTextSize(13); sub.setTextColor(onSurfaceV());
        sub.setPadding(0, dp(2), 0, dp(16));
        root.addView(sub);

        LinearLayout st = card();
        row(st, "root", R.string.f_root);
        row(st, "modem", R.string.f_modem);
        row(st, "wdm", R.string.f_wdm);
        row(st, "net", R.string.f_net);
        row(st, "eth", R.string.f_eth);
        row(st, "wifi", R.string.f_wifi);
        row(st, "default", R.string.f_default);
        row(st, "wlan_ip", R.string.f_wlan_ip);
        row(st, "wwan_ip", R.string.f_wwan_ip);
        row(st, "apn", R.string.f_apn);
        root.addView(st);

        LinearLayout sg = card();
        sg.addView(header(R.string.sec_signal));
        tvSignal = new TextView(this);
        tvSignal.setTextSize(14); tvSignal.setTextColor(onSurfaceV());
        tvSignal.setText(R.string.signal_reading);
        sg.addView(tvSignal);
        root.addView(sg);

        LinearLayout ap = card();
        ap.addView(header(R.string.sec_settings));
        etApn = new EditText(this);
        etApn.setHint(R.string.apn_hint);
        etApn.setText(prefs.getString("apn", "ctlte"));
        etApn.setInputType(InputType.TYPE_CLASS_TEXT);
        etApn.setTextColor(onSurface());
        ap.addView(etApn);
        Button save = button(getString(R.string.save_apn), tonal(), onTonal());
        save.setOnClickListener(new View.OnClickListener() { public void onClick(View v) {
            prefs.edit().putString("apn", etApn.getText().toString().trim()).apply();
            toast(getString(R.string.apn_saved));
        }});
        ap.addView(save, lp(0, dp(8)));
        swValidate = new Switch(this);
        swValidate.setText(R.string.validate);
        swValidate.setTextColor(onSurface());
        swValidate.setChecked(prefs.getBoolean("validate", false));
        swValidate.setOnCheckedChangeListener(new android.widget.CompoundButton.OnCheckedChangeListener() {
            public void onCheckedChanged(android.widget.CompoundButton v, boolean on) {
                prefs.edit().putBoolean("validate", on).apply();
            }
        });
        ap.addView(swValidate, lp(0, dp(12)));
        root.addView(ap);

        LinearLayout bt = card();
        swLte = new Switch(this);
        swLte.setText(R.string.lte_toggle);
        swLte.setTextColor(onSurface());
        swLte.setOnCheckedChangeListener(new android.widget.CompoundButton.OnCheckedChangeListener() {
            public void onCheckedChanged(android.widget.CompoundButton v, boolean on) {
                if (busy) return;
                act(on ? "eth-on" : "eth-off", getString(on ? R.string.busy_on : R.string.busy_off));
            }
        });
        bt.addView(swLte);
        Button bR = button(getString(R.string.refresh), tonal(), onTonal());
        bR.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { refresh(); } });
        bt.addView(bR, lp(0, dp(10)));
        root.addView(bt);
        return sc;
    }

    private TextView header(int res) {
        TextView h = new TextView(this);
        h.setText(res);
        h.setTextSize(15); h.setTextColor(onSurface()); h.setTypeface(null, 1);
        h.setPadding(0, 0, 0, dp(6));
        return h;
    }

    private void act(final String cmd, final String msg) {
        busy = true;
        tvTitle.setText(msg);
        new Thread(new Runnable() { public void run() {
            Extract.ensure(MainActivity.this);
            final String out = su(env() + "sh " + Extract.ctl(MainActivity.this) + " " + cmd);
            runOnUiThread(new Runnable() { public void run() { busy = false; tvTitle.setText(R.string.title_idle); refresh(); } });
        }}).start();
    }

    private String env() {
        String apn = prefs.getString("apn", "ctlte");
        String val = prefs.getBoolean("validate", false) ? "1" : "0";
        return "APN=" + apn + " VALIDATE=" + val + " ";
    }

    private void refresh() {
        new Thread(new Runnable() { public void run() {
            String dir = Extract.ensure(MainActivity.this) ? Extract.ctl(MainActivity.this) : null;
            final String root = su("id");
            final Map<String, String> info = dir == null ? new HashMap<String, String>() : kv(su(env() + "sh " + dir + " info"));
            final Map<String, String> sig  = dir == null ? new HashMap<String, String>() : signal(su(env() + "sh " + dir + " signal"));
            runOnUiThread(new Runnable() { public void run() {
                boolean granted = root.contains("uid=0");
                set("root", granted ? getString(R.string.root_granted) : getString(R.string.root_denied, trim(root)));
                for (Map.Entry<String, String> e : info.entrySet()) {
                    if ("wifi".equals(e.getKey())) {
                        boolean on = "connected".equals(e.getValue());
                        set("wifi", getString(on ? R.string.st_connected : R.string.st_disconnected));
                    } else {
                        set(e.getKey(), e.getValue());
                    }
                }
                String eth = info.get("eth");
                busy = true; swLte.setChecked(eth != null && !eth.isEmpty()); busy = false;

                StringBuilder sb = new StringBuilder();
                if (sig.containsKey("op"))   sb.append(getString(R.string.sig_op, sig.get("op"))).append('\n');
                if (sig.containsKey("reg"))  sb.append(getString(R.string.sig_reg, sig.get("reg"))).append('\n');
                if (sig.containsKey("rsrp")) sb.append("RSRP ").append(sig.get("rsrp"));
                if (sig.containsKey("rsrq")) sb.append("   RSRQ ").append(sig.get("rsrq"));
                if (sig.containsKey("snr"))  sb.append("   SNR ").append(sig.get("snr"));
                tvSignal.setText(sb.length() == 0 ? getString(R.string.signal_none) : sb.toString());
            }});
        }}).start();
    }

    private void set(String key, String val) {
        TextView t = rows.get(key);
        if (t != null) t.setText(val == null || val.isEmpty() ? "-" : val);
    }
    private String trim(String s) { s = s == null ? "" : s.replace("\n", " ").trim(); return s.length() > 40 ? s.substring(0, 40) : s; }

    private static Map<String, String> kv(String s) {
        Map<String, String> m = new HashMap<String, String>();
        for (String l : (s == null ? "" : s).split("\n")) { int i = l.indexOf('='); if (i > 0) m.put(l.substring(0, i).trim(), l.substring(i + 1).trim()); }
        return m;
    }
    private static Map<String, String> signal(String s) {
        Map<String, String> m = new HashMap<String, String>();
        if (s == null) return m;
        for (String l : s.split("\n")) {
            int i;
            if ((i = l.indexOf("RSRP:")) >= 0) m.put("rsrp", l.substring(i + 5).trim().replace("'", ""));
            else if ((i = l.indexOf("RSRQ:")) >= 0) m.put("rsrq", l.substring(i + 5).trim().replace("'", ""));
            else if ((i = l.indexOf("SNR:")) >= 0)  m.put("snr",  l.substring(i + 4).trim().replace("'", ""));
            else if ((i = l.indexOf("Description:")) >= 0) m.put("op", l.substring(i + 12).trim().replace("'", ""));
            else if ((i = l.indexOf("Registration state:")) >= 0) m.put("reg", l.substring(i + 19).trim().replace("'", ""));
        }
        return m;
    }

    private void row(LinearLayout parent, String key, int labelRes) {
        LinearLayout r = new LinearLayout(this);
        r.setOrientation(LinearLayout.HORIZONTAL);
        r.setPadding(0, dp(6), 0, dp(6));
        TextView k = new TextView(this);
        k.setText(labelRes); k.setTextSize(14); k.setTextColor(onSurfaceV());
        k.setLayoutParams(new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        r.addView(k);
        TextView v = new TextView(this);
        v.setText("-"); v.setTextSize(14); v.setTextColor(onSurface()); v.setGravity(Gravity.END);
        r.addView(v);
        rows.put(key, v);
        parent.addView(r);
    }

    private LinearLayout card() {
        LinearLayout l = new LinearLayout(this);
        l.setOrientation(LinearLayout.VERTICAL);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(tonal());
        bg.setCornerRadius(dp(20));
        bg.setStroke(dp(1), outline());
        l.setBackground(bg);
        l.setPadding(dp(16), dp(14), dp(16), dp(14));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = dp(14);
        l.setLayoutParams(lp);
        return l;
    }
    private Button button(String text, int bg, int fg) {
        Button b = new Button(this);
        b.setText(text);
        b.setTextColor(fg);
        b.setAllCaps(false);
        GradientDrawable g = new GradientDrawable();
        g.setColor(bg); g.setCornerRadius(dp(24));
        b.setBackground(g);
        return b;
    }
    private LinearLayout.LayoutParams lp(int top, int bottom) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.topMargin = top; lp.bottomMargin = bottom;
        return lp;
    }
    private int dp(int v) { return (int) (v * getResources().getDisplayMetrics().density + 0.5f); }
    private void toast(String s) { Toast.makeText(this, s, Toast.LENGTH_SHORT).show(); }
    private String su(String cmd) {
        try {
            Process pr = Runtime.getRuntime().exec(new String[]{"/system/bin/su", "-c", cmd + " 2>&1"});
            BufferedReader r = new BufferedReader(new InputStreamReader(pr.getInputStream()));
            StringBuilder sb = new StringBuilder(); String l;
            while ((l = r.readLine()) != null) sb.append(l).append('\n');
            pr.waitFor();
            return sb.toString();
        } catch (Exception e) { return "err:" + e; }
    }
}
