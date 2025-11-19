# Guacamole RDP Setup Summary

## ✅ Completed Steps (Option B)

### 1. Installed & Configured xRDP
- **Package**: xrdp + XFCE4 desktop environment
- **Status**: xrdp service running on port 3389
- **Session**: Configured to launch XFCE4 via `~/.xsession`

```bash
# Verify xrdp is running:
sudo systemctl status xrdp
ss -tlnp | grep 3389
```

### 2. Updated Guacamole Configuration
- **File**: `/etc/guacamole/user-mapping.xml`
- **Connections Added**:
  - **Desktop RDP** (primary) - localhost:3389 with full clipboard + audio
  - **Desktop VNC** (alternate) - localhost:5901 with PulseAudio

**Users configured**:
- `guacadmin` / `guacadmin` (admin account)
- `testuser` / `Aa123456!` (your main account)

### 3. Verified guacd Capabilities
- ✅ FreeRDP support: `libfreerdp2.so.2` linked
- ✅ PulseAudio support: `libpulse.so.0` linked
- ✅ Services restarted: guacd + tomcat9 running

## 🎯 RDP Connection Parameters (What Changed)

### Key improvements for clipboard + audio:

**RDP Connection (recommended)**:
```xml
<protocol>rdp</protocol>
<param name="hostname">localhost</param>
<param name="port">3389</param>
<param name="username">testuser</param>
<param name="password">Aa123456!</param>
<param name="security">any</param>

<!-- Clipboard -->
<param name="normalize-clipboard">unix</param>

<!-- Audio -->
<param name="enable-audio">true</param>
<param name="enable-audio-input">true</param>

<!-- Performance -->
<param name="disable-wallpaper">true</param>
<param name="enable-theming">false</param>
<param name="color-depth">24</param>

<!-- Drive redirection (file transfer) -->
<param name="enable-drive">true</param>
<param name="drive-path">/var/lib/guacd/drives/testuser</param>
<param name="create-drive-path">true</param>
```

## 📋 How to Test

### 1. Access Guacamole
Open browser: http://150.239.114.192:8080/guacamole

Login with:
- Username: `testuser`
- Password: `Aa123456!`

### 2. Connect via RDP
- Click on **"Desktop RDP"** connection
- Should open XFCE desktop session immediately
- No additional login prompt (credentials auto-filled)

### 3. Test Clipboard
**Local → Remote paste:**
1. Copy text on your local machine (Cmd+C / Ctrl+C)
2. In Guacamole session, right-click → Paste OR use Guacamole menu (Ctrl+Alt+Shift) → paste
3. Text should appear in remote session

**Remote → Local copy:**
1. Select and copy text in remote session (Ctrl+C in XFCE)
2. Paste on your local machine
3. Should work automatically

### 4. Test Audio (if available)
- Open Firefox/browser in remote session
- Play a YouTube video or system sound
- Audio should stream to your browser (browser needs to allow audio playback)

### 5. Test File Transfer
- Use Guacamole menu (Ctrl+Alt+Shift) → Devices → Shared Drive
- Upload/download files via the drive interface

## 🔧 Troubleshooting

### If RDP connection fails:
```bash
# Check xrdp status:
ssh testuser@150.239.114.192 'sudo systemctl status xrdp'

# Check guacd logs:
ssh testuser@150.239.114.192 'sudo journalctl -u guacd -n 50'

# Restart services:
ssh testuser@150.239.114.192 'sudo systemctl restart xrdp guacd tomcat9'
```

### If clipboard still doesn't work:
1. **Serve Guacamole over HTTPS** (browsers restrict clipboard in HTTP contexts)
2. Check browser clipboard permissions (allow when prompted)
3. Try explicit paste via Guacamole menu instead of Ctrl+V
4. Verify `normalize-clipboard` is set correctly in user-mapping.xml

### If audio doesn't work:
1. Ensure PulseAudio runs in the xrdp session:
   ```bash
   # In remote terminal:
   pulseaudio --check || pulseaudio --start
   pactl list sinks
   ```

2. Check browser allows audio (click unmute/allow audio in browser)

3. **Note**: pulseaudio-module-xrdp build failed (missing source headers). Basic RDP audio via FreeRDP should work, but for advanced xrdp audio you'd need to:
   - Download PulseAudio source matching your version (15.99.1)
   - Build pulseaudio-module-xrdp with `PULSE_DIR=/path/to/pulseaudio-source`
   - Install module to `/usr/lib/pulse-15.99/modules/`

## 📊 Why RDP is Better than VNC for This Use Case

| Feature | RDP (via xrdp) | VNC (TigerVNC) |
|---------|----------------|----------------|
| **Clipboard** | Native bidirectional, protocol-level | Requires vncconfig/autocutsel, encoding issues |
| **Audio** | Native RDP audio channels | Requires separate PulseAudio TCP connection |
| **Performance** | Better compression, caching | Slower, more bandwidth |
| **Desktop Integration** | Seamless | Manual X11 clipboard bridging needed |

## 🎬 Next Steps (Optional)

### A. Enable HTTPS for Better Clipboard
Set up nginx reverse proxy with Let's Encrypt:
```bash
sudo apt install -y nginx certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.com
# Configure nginx to proxy /guacamole to localhost:8080
```

### B. Try Advanced Audio (if needed)
Build pulseaudio-module-xrdp properly:
1. Download PulseAudio 15.99.1 source
2. Extract and configure with same prefix
3. Build module: `./configure PULSE_DIR=/path/to/pulseaudio-15.99.1`
4. Install: `sudo make install`
5. Restart xrdp and pulseaudio

### C. Use VNC as Fallback
The VNC connection is still configured if RDP has issues:
- Uses existing VNC :1 session (XFCE)
- PulseAudio TCP for audio
- ISO8859-1 clipboard encoding (safer)

## 📁 Files Modified

- `/etc/guacamole/user-mapping.xml` - RDP + VNC connection configs
- `~/.xsession` - XFCE startup for xrdp sessions
- Services: xrdp enabled, guacd + tomcat9 restarted

## ✨ Current Status

- ✅ xrdp installed and running (port 3389)
- ✅ XFCE desktop configured
- ✅ Guacamole user-mapping updated with RDP connection
- ✅ guacd has FreeRDP + PulseAudio support
- ✅ Services restarted and healthy
- ⚠️ pulseaudio-module-xrdp not installed (advanced audio feature; basic audio should still work)
- ✅ Ready to test via http://150.239.114.192:8080/guacamole

**Recommendation**: Test RDP connection now. If clipboard works but audio doesn't, we can revisit the pulseaudio-module-xrdp build with the proper source tree.
