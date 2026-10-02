package com.ltegopher.ltesolo;

import android.content.SharedPreferences;
import android.graphics.drawable.Icon;
import android.os.Handler;
import android.os.Looper;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;

/** Quick Settings tile: toggles LTE and shows signal % while on. Localized. */
public class LteTile extends TileService {
    private final Handler h = new Handler(Looper.getMainLooper());
    private volatile String lastSub = "";
    private final Runnable poll = new Runnable() {
        public void run() { startQuery(); h.postDelayed(this, 20000); }
    };

    private boolean lteOn() { return curEth() != null; }
    private String curEth() {
        for (String n : new String[]{"eth0","eth1","eth2","eth3"}) {
            if (new File("/sys/class/net/" + n + "/cdc_ncm").exists()) return n;
        }
        return null;
    }
    private String env() {
        SharedPreferences p = getSharedPreferences("lte", MODE_PRIVATE);
        String apn = p.getString("apn", "ctlte");
        String val = p.getBoolean("validate", false) ? "1" : "0";
        return "APN=" + apn + " VALIDATE=" + val + " ";
    }
    private String L() { return getString(R.string.tile_label); }

    @Override public void onStartListening() { Extract.ensure(this); update(); h.removeCallbacks(poll); h.postDelayed(poll, 20000); }
    @Override public void onStopListening()  { h.removeCallbacks(poll); }
    @Override public void onTileAdded()      { Extract.ensure(this); update(); }

    @Override public void onClick() {
        final boolean wasOn = lteOn();
        setTile(L(), getString(R.string.tile_wait), Tile.STATE_ACTIVE);
        new Thread(new Runnable() { public void run() {
            if (!Extract.ensure(LteTile.this)) { h.post(new Runnable(){ public void run(){ setTile(L(), getString(R.string.tile_fail), Tile.STATE_INACTIVE); }}); return; }
            su(env() + "sh " + Extract.ctl(LteTile.this) + (wasOn ? " eth-off" : " eth-on"));
            h.post(new Runnable() { public void run() { update(); } });
        }}).start();
    }

    private void setTile(String label, String sub, int state) {
        Tile t = getQsTile();
        if (t == null) return;
        t.setIcon(Icon.createWithResource(this, R.drawable.ic_lte));
        t.setState(state);
        t.setLabel(label);
        if (sub != null) t.setSubtitle(sub);
        t.updateTile();
    }

    private void update() {
        if (!lteOn()) { setTile(L(), getString(R.string.tile_off), Tile.STATE_INACTIVE); return; }
        setTile(L(), lastSub.isEmpty() ? getString(R.string.tile_reading) : lastSub, Tile.STATE_ACTIVE);
        startQuery();
    }

    private void startQuery() {
        if (!lteOn()) { setTile(L(), getString(R.string.tile_off), Tile.STATE_INACTIVE); return; }
        new Thread(new Runnable() { public void run() {
            if (!Extract.ensure(LteTile.this)) return;
            final String raw = su(env() + "sh " + Extract.ctl(LteTile.this) + " signal");
            h.post(new Runnable() { public void run() { apply(raw); } });
        }}).start();
    }

    private void apply(String raw) {
        if (!lteOn()) { setTile(L(), getString(R.string.tile_off), Tile.STATE_INACTIVE); return; }
        String rsrp = pick(raw, "RSRP:");
        String rsrq = pick(raw, "RSRQ:");
        String rssi = pick(raw, "RSSI:");
        String snr  = pick(raw, "SNR:");
        String op   = pick(raw, "Description:");
        String reg  = pick(raw, "Registration state:");

        int dbm = num(rsrp);
        if (dbm == Integer.MIN_VALUE) dbm = num(rssi);
        if (dbm == Integer.MIN_VALUE) { setTile(L(), lastSub.isEmpty() ? getString(R.string.tile_reading) : lastSub, Tile.STATE_ACTIVE); return; }
        String label = getString(R.string.tile_pct, percent(dbm));
        StringBuilder sub = new StringBuilder();
        if (rsrp != null) sub.append(rsrp);
        if (rsrq != null) sub.append(sub.length() > 0 ? "  " : "").append("RSRQ ").append(rsrq);
        if (snr  != null) sub.append(sub.length() > 0 ? "  " : "").append("SNR ").append(snr);
        if (op   != null) sub.append(sub.length() > 0 ? "  " : "").append(op);
        else if (reg != null) sub.append(sub.length() > 0 ? "  " : "").append(reg);
        lastSub = sub.toString();
        setTile(label, lastSub.isEmpty() ? getString(R.string.tile_enabled) : lastSub, Tile.STATE_ACTIVE);
    }

    private static int percent(int dbm) {
        int p = (int) Math.round((dbm + 140) * 100.0 / 70.0);
        if (p < 0) p = 0; if (p > 100) p = 100; return p;
    }
    private static int num(String s) {
        if (s == null) return Integer.MIN_VALUE;
        try {
            int i = 0; StringBuilder d = new StringBuilder();
            if (s.charAt(0) == '-') { d.append('-'); i = 1; }
            while (i < s.length() && Character.isDigit(s.charAt(i))) d.append(s.charAt(i++));
            if (d.length() == 0 || (d.length() == 1 && d.charAt(0) == '-')) return Integer.MIN_VALUE;
            return Integer.parseInt(d.toString());
        } catch (Exception e) { return Integer.MIN_VALUE; }
    }
    private static String pick(String text, String key) {
        if (text == null) return null;
        for (String line : text.split("\n")) {
            int i = line.indexOf(key);
            if (i >= 0) return line.substring(i + key.length()).trim().replace("'", "").replace("\"", "");
        }
        return null;
    }
    private String su(String cmd) {
        try {
            Process p = Runtime.getRuntime().exec(new String[]{"/system/bin/su", "-c", cmd + " 2>&1"});
            BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
            StringBuilder sb = new StringBuilder(); String l;
            while ((l = r.readLine()) != null) sb.append(l).append('\n');
            p.waitFor();
            return sb.toString();
        } catch (Exception e) { return "err:" + e; }
    }
}
