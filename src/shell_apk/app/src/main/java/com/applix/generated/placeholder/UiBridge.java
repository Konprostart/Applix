package com.applix.generated.placeholder;

import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.os.VibratorManager;
import android.view.View;
import android.view.Window;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;

/**
 * Native chrome for generated apps: system bars, insets, native dialogs,
 * native toasts, haptics and the share sheet.
 *
 * Exposed to the page as `iappyxUi.*` and wired into the public bridge as
 * `iappyx.ui.*` (see SPEC.md).
 */
public class UiBridge {

    private final ShellActivity act;
    private volatile boolean edgeToEdge = false;

    UiBridge(ShellActivity act) {
        this.act = act;
    }

    // ── System bars ────────────────────────────────────────────────────────

    @JavascriptInterface
    public void setStatusBar(String color, boolean lightIcons) {
        final int c = parseColor(color);
        act.runOnUiThread(() -> {
            try {
                act.getWindow().setStatusBarColor(c);
                setBarIconAppearance(lightIcons, true);
            } catch (Exception ignored) {
            }
        });
    }

    @JavascriptInterface
    public void setNavigationBar(String color, boolean lightIcons) {
        final int c = parseColor(color);
        act.runOnUiThread(() -> {
            try {
                act.getWindow().setNavigationBarColor(c);
                setBarIconAppearance(lightIcons, false);
            } catch (Exception ignored) {
            }
        });
    }

    @JavascriptInterface
    public void setEdgeToEdge(boolean enabled) {
        this.edgeToEdge = enabled;
        act.runOnUiThread(() -> {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    act.getWindow().setDecorFitsSystemWindows(!enabled);
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    act.getWindow().getDecorView().setSystemUiVisibility(
                            enabled ? View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                                    | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                                    | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                                    : 0);
                }
            } catch (Exception ignored) {
            }
        });
    }

    @JavascriptInterface
    public void setImmersive(boolean enabled) {
        act.runOnUiThread(() -> {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    act.getWindow().setDecorFitsSystemWindows(!enabled);
                    WindowInsetsController c = act.getWindow().getInsetsController();
                    if (c != null) {
                        if (enabled) {
                            c.hide(android.view.WindowInsets.Type.systemBars());
                        } else {
                            c.show(android.view.WindowInsets.Type.systemBars());
                        }
                    }
                } else {
                    act.getWindow().getDecorView().setSystemUiVisibility(
                            enabled ? View.SYSTEM_UI_FLAG_FULLSCREEN
                                    | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                                    | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                                    : 0);
                }
            } catch (Exception ignored) {
            }
        });
    }

    /** Insets of the system bars in CSS pixels. Zero unless edge-to-edge is on. */
    @JavascriptInterface
    public String getInsets() {
        try {
            if (!edgeToEdge) {
                return "{\"top\":0,\"bottom\":0,\"left\":0,\"right\":0}";
            }
            final float density = act.getResources().getDisplayMetrics().density;
            int top = 0, bottom = 0, left = 0, right = 0;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                android.view.WindowInsets insets = act.getWindow().getDecorView().getRootWindowInsets();
                if (insets != null) {
                    android.graphics.Insets bars = insets.getInsets(
                            android.view.WindowInsets.Type.systemBars()
                                    | android.view.WindowInsets.Type.displayCutout());
                    top = bars.top;
                    bottom = bars.bottom;
                    left = bars.left;
                    right = bars.right;
                }
            }
            int topPx = (int) (top / density);
            int bottomPx = (int) (bottom / density);
            int leftPx = (int) (left / density);
            int rightPx = (int) (right / density);
            return "{\"top\":" + topPx + ",\"bottom\":" + bottomPx
                    + ",\"left\":" + leftPx + ",\"right\":" + rightPx
                    + ",\"density\":" + density + "}";
        } catch (Exception e) {
            return "{\"top\":0,\"bottom\":0,\"left\":0,\"right\":0,\"density\":1}";
        }
    }

    // ── Native dialogs & feedback ──────────────────────────────────────────

    @JavascriptInterface
    public void toast(final String message) {
        if (message == null) return;
        act.runOnUiThread(() -> android.widget.Toast.makeText(
                act.getApplicationContext(), message, android.widget.Toast.LENGTH_SHORT).show());
    }

    @JavascriptInterface
    public void alert(final String title, final String message) {
        act.runOnUiThread(() -> new AlertDialog.Builder(act)
                .setTitle(title == null ? "" : title)
                .setMessage(message == null ? "" : message)
                .setPositiveButton("OK", null)
                .show());
    }

    /** Native confirm dialog. The result is delivered to the cbId callback. */
    @JavascriptInterface
    public void confirm(final String title, final String message, final String cbId) {
        act.runOnUiThread(() -> new AlertDialog.Builder(act)
                .setTitle(title == null ? "" : title)
                .setMessage(message == null ? "" : message)
                .setPositiveButton("OK", (d, w) -> act.deliverResult(cbId, "true"))
                .setNegativeButton("Cancel", (d, w) -> act.deliverResult(cbId, "false"))
                .setOnCancelListener(d -> act.deliverResult(cbId, "false"))
                .show());
    }

    /** Haptic feedback: light | medium | heavy | success | error | selection. */
    @JavascriptInterface
    public void haptic(final String type) {
        long ms;
        int amplitude;
        if ("medium".equals(type)) {
            ms = 20; amplitude = 140;
        } else if ("heavy".equals(type)) {
            ms = 30; amplitude = 220;
        } else if ("success".equals(type)) {
            ms = 40; amplitude = 180;
        } else if ("error".equals(type)) {
            ms = 60; amplitude = 240;
        } else if ("selection".equals(type)) {
            ms = 12; amplitude = 90;
        } else {
            ms = 16; amplitude = 110;
        }
        try {
            Vibrator vibrator;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                VibratorManager manager = (VibratorManager) act.getSystemService(Context.VIBRATOR_MANAGER_SERVICE);
                vibrator = manager.getDefaultVibrator();
            } else {
                vibrator = (Vibrator) act.getSystemService(Context.VIBRATOR_SERVICE);
            }
            if (vibrator == null || !vibrator.hasVibrator()) return;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createOneShot(ms, amplitude));
            } else {
                vibrator.vibrate(ms);
            }
        } catch (Exception ignored) {
        }
    }

    // ── Sharing ────────────────────────────────────────────────────────────

    @JavascriptInterface
    public void shareText(final String text, final String title) {
        share("text/plain", text == null ? "" : text, title);
    }

    @JavascriptInterface
    public void shareUrl(final String url, final String title) {
        share("text/plain", url == null ? "" : url, title);
    }

    private void share(final String mime, final String payload, final String title) {
        act.runOnUiThread(() -> {
            try {
                Intent send = new Intent(Intent.ACTION_SEND);
                send.setType(mime);
                send.putExtra(Intent.EXTRA_TEXT, payload);
                Intent chooser = Intent.createChooser(send, title == null ? "Share" : title);
                chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                act.startActivity(chooser);
            } catch (Exception ignored) {
            }
        });
    }

    // ── Misc ───────────────────────────────────────────────────────────────

    /** Opens this app's system settings page. */
    @JavascriptInterface
    public void openSettings() {
        act.runOnUiThread(() -> {
            try {
                Intent intent = new Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
                intent.setData(Uri.fromParts("package", act.getPackageName(), null));
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                act.startActivity(intent);
            } catch (Exception ignored) {
            }
        });
    }

    @JavascriptInterface
    public void setKeepScreenOn(final boolean on) {
        act.runOnUiThread(() -> {
            try {
                if (on) {
                    act.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                } else {
                    act.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                }
            } catch (Exception ignored) {
            }
        });
    }

    @JavascriptInterface
    public void setOrientation(final String mode) {
        act.runOnUiThread(() -> {
            try {
                int value;
                if ("portrait".equals(mode)) {
                    value = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT;
                } else if ("landscape".equals(mode)) {
                    value = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE;
                } else {
                    value = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED;
                }
                act.setRequestedOrientation(value);
            } catch (Exception ignored) {
            }
        });
    }

    /** Screen geometry and refresh rate. */
    @JavascriptInterface
    public String getScreenInfo() {
        try {
            android.util.DisplayMetrics dm = act.getResources().getDisplayMetrics();
            float refresh = 60f;
            try {
                android.view.Display display = act.getWindowManager().getDefaultDisplay();
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    refresh = display.getRefreshRate();
                } else {
                    refresh = display.getRefreshRate();
                }
            } catch (Exception ignored) {
            }
            return "{\"width\":" + dm.widthPixels + ",\"height\":" + dm.heightPixels
                    + ",\"density\":" + dm.density + ",\"refreshRate\":" + refresh + "}";
        } catch (Exception e) {
            return "{\"width\":0,\"height\":0,\"density\":1,\"refreshRate\":60}";
        }
    }

    // ── helpers ────────────────────────────────────────────────────────────

    private void setBarIconAppearance(boolean lightIcons, boolean statusBar) {
        try {
            Window w = act.getWindow();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                WindowInsetsController controller = w.getInsetsController();
                if (controller == null) return;
                int mask = statusBar
                        ? WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                        : WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
                controller.setSystemBarsAppearance(lightIcons ? mask : 0, mask);
            } else {
                int flags = w.getDecorView().getSystemUiVisibility();
                if (statusBar) {
                    flags = lightIcons
                            ? (flags | View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR)
                            : (flags & ~View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR);
                } else {
                    flags = lightIcons
                            ? (flags | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR)
                            : (flags & ~View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
                }
                w.getDecorView().setSystemUiVisibility(flags);
            }
        } catch (Exception ignored) {
        }
    }

    private int parseColor(String color) {
        try {
            if (color == null || color.isEmpty()) return Color.parseColor("#12122a");
            return Color.parseColor(color.trim());
        } catch (Exception e) {
            return Color.parseColor("#12122a");
        }
    }
}
